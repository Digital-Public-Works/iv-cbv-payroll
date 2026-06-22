# Transmission Integration Tests

Integration tests verify that each transmitter can deliver payloads to real infrastructure. They run against local Docker containers instead of mocked services.

## Prerequisites

- Docker and Docker Compose
- The application's PostgreSQL database must be running
- Database migrations must be up to date (`bin/rails db:migrate`)

Note: PDF generation is stubbed in the integration specs.

## Quick Start

```bash
# 1. Start the Docker infrastructure
bundle exec rake integration:docker:up

# 2. Run all integration tests
bundle exec rake integration:rspec:all

# 3. When done, stop the Docker services
bundle exec rake integration:docker:down
```

## Rake Tasks

All integration-related tasks live under the `integration:` namespace:

| Task | Purpose |
|---|---|
| `integration:docker:up` | Start the Docker services (SFTP, webhook-api, S3) |
| `integration:docker:down` | Stop the Docker services |
| `integration:docker:ps` | Show Docker service status |
| `integration:rspec:all` | Run every integration spec (verifies Docker is up first) |
| `integration:rspec:webhook` | Run just the webhook transmitter spec |
| `integration:rspec:sftp` | Run just the SFTP transmitter spec |
| `integration:rspec:unencrypted_s3` | Run just the unencrypted S3 transmitter spec |
| `integration:rspec:encrypted_s3` | Run just the encrypted S3 transmitter spec |
| `integration:partner:setup` | Create the `integration_test` partner and API service account (for e2e browser testing) |
| `integration:partner:teardown` | Remove the `integration_test` partner and service account |

List them all with `bundle exec rake -T integration`.

## Docker Services

The file `docker-compose.integration.yml` defines the following services:

| Service | Image | Port | Purpose |
|---|---|---|---|
| `sftp` | `atmoz/sftp:latest` | 2222 | SFTP server for `SftpTransmitter` |
| `webhook-api` | [dicit-webhook-api-ref-impl](https://github.com/Digital-Public-Works/dicit-webhook-api-ref-impl) | 9292 | Webhook reference server for `WebhookTransmitter` |
| `s3` | `andrewgaul/s3proxy:latest` | 9000 | S3-compatible storage for `UnencryptedS3Transmitter` and `EncryptedS3Transmitter` |

Credentials:

- SFTP: user `testuser`, password `testpass`, upload directory `/upload`
- Webhook API: API key `my-secure-guid` (set via `VMI_API_KEY`)
- S3: access key `s3test`, secret `s3test`

We use **s3proxy** so each uploaded object lands as a plain file at `tmp/integration_transmissions/s3/<bucket>/<key>`. A `bucket-init` service in the compose file creates the bucket directories before the real services start.

## Test Files

Integration specs carry the tag `integration: true` and are excluded from the default RSpec run.

| File | Transmitter | Infrastructure |
|---|---|---|
| `sftp_transmitter_integration_spec.rb` | `SftpTransmitter` | SFTP container |
| `webhook_transmitter_integration_spec.rb` | `WebhookTransmitter` | Webhook ref impl (port 9292) |
| `unencrypted_s3_transmitter_integration_spec.rb` | `UnencryptedS3Transmitter` | s3proxy (port 9000) |
| `encrypted_s3_transmitter_integration_spec.rb` | `EncryptedS3Transmitter` | s3proxy (port 9000) + locally generated GPG keypair |

## Running the webhook spec against a customer environment

The webhook integration spec can also run against a **partner's** webhook endpoint instead of the local reference server. This is a conformance check: it verifies that our outbound payload, request signing (`X-VMI-*` headers, HMAC-SHA512), and error handling are compatible with a receiver the partner built independently from our contract.

It is the same spec — only the target and a few inputs change, supplied via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `WEBHOOK_TEST_URL` | `http://localhost:9292/api/v1/income-report` | Full endpoint URL, **including path**. Point this at the partner's host. |
| `WEBHOOK_TEST_API_KEY` | `my-secure-guid` | API key used for the `X-VMI-API-Key` header and the HMAC signature. |
| `WEBHOOK_TEST_CLIENT_INFORMATION` | `case_number=ABC1234` | Comma-separated `key=value` pairs sent in the payload's `client_information` block. Values are sent verbatim, so you can match a partner's expected custom attributes. |
| `WEBHOOK_TEST_DEBUG` | _(unset)_ | When set, logs each request's outbound payload and the server's raw response (status + body), and enables an extra diagnostic example. Off by default so CI output stays clean. |

No Docker reference server is needed when targeting a partner — you hit their host directly. The spec turns VCR off and allows real network connections automatically, so HTTPS endpoints behave the same as the local HTTP one.

Run it inside the app container, against the partner's QA:

```bash
docker compose run --rm \
  -e RAILS_ENV=test \
  -e INTEGRATION_RUN_TESTS=1 \
  -e WEBHOOK_TEST_URL="https://partner-host/their/path" \
  -e WEBHOOK_TEST_API_KEY="<partner key>" \
  -e WEBHOOK_TEST_CLIENT_INFORMATION="case_number=ABC1234" \
  -e WEBHOOK_TEST_DEBUG=1 \
  app_rails bundle exec rspec spec/services/transmitters/webhook_transmitter_integration_spec.rb
```

- `RAILS_ENV=test` is **required** — the compose service defaults to `development`, where Factory Bot is not loaded (you'd get `uninitialized constant FactoryBot`).
- `INTEGRATION_RUN_TESTS=1` un-skips the `integration: true` tag when invoking `rspec` directly. (The `integration:rspec:*` rake tasks already pass `--tag integration`, so they don't need it.)
- If a gem was added/bumped since the image was last built, rebuild first with `docker compose build app_rails`.

**Interpreting failures:** the assertions are strict and faithful to our published contract — status codes *and* error-envelope shape (e.g. `error_code: "VALIDATION_ERROR"`, `AUTHENTICATION_ERROR`). The local reference server matches the contract, so CI stays green. A partner's independent implementation may diverge; when it does, the failures are **conformance findings to reconcile with the partner**, not bugs in the test. Use `WEBHOOK_TEST_DEBUG=1` to capture the exact request/response for those conversations.

## End-to-End Browser Testing (optional)

The `integration:partner:setup` task creates an `integration_test` partner and a service-account user with an API access token. This lets you exercise the full CBV flow end-to-end through a browser, with real webhook delivery to the Docker services.

The `integration_test` partner is configured with a single webhook transmission method (see `docs/app/integration-test-partner.yml`). Authentication uses API tokens — there is no caseworker UI or generic link.

```bash
# 1. Start Docker services
bundle exec rake integration:docker:up

# 2. Create the integration_test partner + API token + a ready-to-use invitation
bundle exec rake integration:partner:setup
# The task prints an API access token and a Tokenized URL.

# 3. Start the Rails server
bin/rails server
```

Open the **Tokenized URL** from step 2 in your browser and complete the CBV flow. When the caseworker submits the report, the webhook transmitter fires.

### Creating additional invitations via the API

The setup task creates one invitation automatically. To create more, use the API token printed by step 2.


```bash
# Verify the webhook container received the payload:
docker compose -f docker-compose.integration.yml logs webhook-api

# Clean up
bundle exec rake integration:partner:teardown
bundle exec rake integration:docker:down
```

## Verifying Services Manually

**SFTP:**

```bash
sftp -P 2222 testuser@localhost
# password: testpass
```

**Webhook reference server:**

```bash
curl http://localhost:9292/health
```

**S3:**

Uploaded objects are mounted to the host (usually in the repo's app folder):

```bash
ls tmp/integration_transmissions/s3/test-unencrypted-bucket
ls tmp/integration_transmissions/s3/test-encrypted-bucket
```

To wipe bucket contents between runs, take the stack down and remove the directory:

```bash
bundle exec rake integration:docker:down
rm -rf tmp/integration_transmissions/s3
```

## Troubleshooting

**Port already allocated** — A previous Docker run may still be holding a port. Run `bundle exec rake integration:docker:down` and try again.

**Connection refused from specs** — The `integration:rspec:*` tasks require the Docker services to be running. If you see `Errno::ECONNREFUSED` or SFTP timeouts, run `bundle exec rake integration:docker:ps` to check status and `bundle exec rake integration:docker:up` to start them.
