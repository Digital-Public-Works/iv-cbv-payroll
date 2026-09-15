# AWS SNS, not Twilio, sends invitation SMS

Invitation SMS goes out through AWS SNS (`SmsService`). The original implementation used Twilio; we switched to keep SMS inside the AWS account the rest of the platform already runs in — no third-party vendor contract, no separate credential rotation, and the same IAM story as SES and SQS. The Twilio implementation is retained as `TwilioSmsService`, unreferenced but loadable and covered by its spec, because Twilio offers two things SNS does not, and either could bring us back: per-message delivery callbacks, and synchronous opt-out reporting.

`SmsService` and `TwilioSmsService` speak the same contract — `#send_message(to:, body:)` returns the provider's message id and raises `SmsService::DeliveryError` / `SmsService::PermanentDeliveryError` — so switching back is a one-line change in `InvitationSmsJob#sms_service`. Everything downstream is provider-agnostic: the `InvitationCommunication` state machine, the `sms_sender` SQS queue, the retry semantics (permanent failures do not re-raise; transient ones do, and SQS redelivers), and the `/admin` retry button.

## What changes about failure handling

Twilio raises a `RestError` carrying a numeric code, which made per-recipient classification exact. SNS `Publish` mostly succeeds at the API layer and reports carrier-level outcomes only through CloudWatch delivery-status logs, so classification is coarser: `InvalidParameter` and friends (plus `VerificationException` and `OptedOutException`) are treated as permanent, and everything else — throttling, `InternalError`, `AuthorizationError`, networking — stays retryable so a misconfiguration fails loudly rather than silently marking every invitation failed.

The consequence is that the `delivered` status on `InvitationCommunication` remains unreachable, as it was under Twilio: nothing subscribes to delivery events. Populating it would mean consuming SNS delivery-status logs from CloudWatch, or moving to AWS End User Messaging (Pinpoint SMS v2), which exposes delivery events directly.

## Two messages per invitation

Each SMS invitation sends two messages in order: a 10DLC opt-in confirmation ("Digital Public Works: You have opted in ... Reply HELP for help or STOP to cancel"), then the invitation itself. A failure on the first aborts before the second, since a number that rejects one will reject the other, and delivering the link without the notice defeats the notice's purpose.

SNS does not guarantee delivery order, and two publishes milliseconds apart are reordered often enough to matter — the notice promises a following message, so arriving second reads as a bug. The job therefore waits `SMS_INTER_MESSAGE_DELAY_SECONDS` (default 3) between them, which blocks the worker thread. That is acceptable at invitation volumes; if it stops being so, the two messages should become two jobs rather than a longer sleep.

For the prototype both messages share a single `InvitationCommunication` row, deliberately, to avoid a migration. That carries three known limitations:

- `provider_message_id` stores the invitation's id only; the notice's id is discarded.
- A failure cannot be attributed to one message or the other — `last_error` just says the send failed.
- If the notice succeeds and the invitation then fails transiently, SQS redelivery re-sends the notice, so an applicant can receive the opt-in text more than once.

**Before production this needs one row per message**: add a `kind` column to `invitation_communications` (`consent_notice` / `invitation`), create both rows up front, and have the job skip any already `sent`. That restores per-message ids and errors and makes redelivery idempotent. The admin views need a corresponding change, because `Admin::InvitationsController#latest_communication` takes `order(:created_at).last` to drive both the status board and the retry button, and would otherwise follow the notice row rather than the invitation.

The notice copy is deliberately not agency-branded — Digital Public Works is the sending party of record — and is currently the English text in both locales; Spanish copy is outstanding, as it is for the invitation body in `es.yml`.

## Current state: local demo only

This runs from local development against real AWS. The account is in the SNS SMS **sandbox**, so sends succeed only to destination phone numbers verified in the SNS console; any other number returns a permanent failure and the invitation is marked `failed` with the error visible in `/admin`.

Local configuration is `AWS_SNS_*` in `.env` — separate from the ambient `AWS_*` variables, which are Moto placeholders for SQS and would otherwise be picked up by the SNS client. `AWS_SNS_ENDPOINT` can point SNS at Moto to exercise the whole flow without sending a real text.

## What deployment would require

No infrastructure changes were made, since nothing is deployed. Moving forward would need:

- **IAM**: an `sns:Publish` policy added to the `extra_policies` map in `infra/app/service/main.tf`, alongside the existing `email_access_policy` (SES) and SQS entries. Those attach to `aws_iam_role.app_service`, which is the task role for both the web service and the async workers — and it is the worker that actually sends, since `InvitationSmsJob` runs off the `sms_sender` queue. Publishing to a phone number has no topic ARN, so the resource must be `*`, and SNS offers no condition key to narrow it (`sns:Protocol` and `sns:Endpoint` apply to `Subscribe`, not `Publish`). Containment therefore comes from the account-level SMS spend quota and the registered origination number, not from IAM.
- **Environment variables**: the deployed task uses the task role, so no credentials are needed — only `AWS_SNS_ORIGINATION_NUMBER` (if pinning a sender) and `AWS_SNS_REGION` (if SMS lives in a region other than the service's). Neither is a secret, so both belong in the plain environment-variable block rather than SSM.
- **Retire the Twilio SSM parameters**: `environment-variables.tf` still declares `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_MESSAGING_SERVICE_SID` as manually managed secrets. They are unused; remove the declarations and delete the underlying SSM parameters.
- **Leave the SMS sandbox**: a production-access request to AWS, plus 10DLC brand and campaign registration for US traffic, with the invitation message body and opt-out language submitted as the campaign use case. Registration takes carrier review time and is the long pole.
- **Spending limit**: the default account SMS spend quota is low; raise it in the same request or sends silently stop once it is hit.
- **Delivery-status logging**: enable SNS SMS delivery-status logging to CloudWatch so failures after the API call are observable, since `provider_message_id` alone proves only acceptance.
