# CBV Payroll (Verify My Income)

Income verification for benefit applicants: an applicant consents to retrieving their payroll data from an aggregator, and the resulting income report is sent to their benefits agency. Multi-tenant across partner agencies.

## Language

**Partner**:
A tenant agency (state or non-state) configured in the system. The legacy code term is `client_agency_id`.
_Avoid_: Client agency (in new writing), tenant

**Platform admin**:
A Digital Public Works staff member who operates the `/admin` portal to create and send invitations on behalf of any partner. Not tied to a single agency; the working agency is inferred from the partner subdomain.
_Avoid_: Caseworker, superuser

**Caseworker**:
An agency staff member (partner-side persona). The `/admin` portal is *branded* "VMI Caseworker Portal" in anticipation of caseworker users, but its operators today are platform admins.
_Avoid_: Staff user, agent

**VMI Caseworker Portal**:
The product name of the `/admin` portal. A branding term only — see Platform admin for who actually operates it.
_Avoid_: Admin portal (in user-facing copy)

**Applicant**:
The benefit applicant whose income is being verified (`CbvApplicant`). Identified to the partner by a partner identifier (e.g. case number).
_Avoid_: End user, claimant

**Invitation**:
A tokenized link authorizing one applicant to start the verification flow, created by a caseworker, the API, or a rake task (`CbvFlowInvitation`).
_Avoid_: Invite link, referral

**Communication**:
An applicant-facing send of an invitation over a channel (today: SMS) at the start of the flow, with its own lifecycle status. Tracked one row per send attempt.
_Avoid_: Transmission, delivery, notification

**Communication channel**:
A partner-level capability for how invitations may be communicated to applicants (SMS now; email planned). Enabled per partner as one boolean per channel.
_Avoid_: Delivery method, comms method

**Transmission**:
An agency-facing send of a completed income report (PDF/CSV) back to the partner (`CbvFlowTransmission`). Never used for applicant-facing sends.
_Avoid_: Communication, report send

**Redaction**:
The PII retention control: overwriting sensitive fields with typed sentinel values and stamping `redacted_at`, on a fixed schedule. The system redacts rather than encrypting PII at rest.
_Avoid_: Anonymization, deletion
