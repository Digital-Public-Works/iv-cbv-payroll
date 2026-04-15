# Transmission Integration Tests

Integration tests verify that each transmitter can deliver payloads to real infrastructure. They run against local Docker containers instead of mocked services.

## Prerequisites

- Docker and Docker Compose
- GPG installed locally (required for the encrypted S3 tests)
- The application's PostgreSQL database must be running
- Database migrations must be up to date (`bin/rails db:migrate`)

Note: PDF generation is stubbed in unit-level integration tests to avoid requiring `sassc-rails` (which is not in the production bundle). The end-to-end partner test (below) exercises the full pipeline including PDF rendering.

To confirm GPG is available:

```bash
gpg --version
```

## Quick Start

```bash
# 1. Start the Docker infrastructure
docker compose -f docker-compose.integration.yml up -d

# 2. Set up the integration_test partner (generates GPG key, applies config, creates user)
bundle exec rake integration:setup

# 3. Run the RSpec integration tests
bundle exec rspec --tag integration

# 4. (Optional) Start the Rails server to test end-to-end through the browser
bin/rails server
# Then visit http://localhost:3000/integration_test
```

## End-to-End Partner Testing

The `integration:setup` rake task creates a fully functional partner called `integration_test` that transmits to all five methods simultaneously. This lets you test the complete CBV flow end-to-end through the browser.

### What `rake integration:setup` does

1. **Generates a GPG keypair** in `tmp/integration-gpg/` and exports the public key to `tmp/integration-gpg-public-key.asc`
2. **Loads** `docs/app/integration-test-partner.yml` and injects the GPG public key into the encrypted S3 config
3. **Applies** the partner config to the database (creates `PartnerConfig`, `PartnerTransmissionMethod`s, `PartnerTransmissionConfig`s, `PartnerApplicationAttribute`s, and `PartnerTranslation`s)
4. **Creates a test user** (`test@integration.local`) associated with the `integration_test` partner

### Transmission methods configured

| Method | Docker Service | Port | What to check |
|---|---|---|---|
| Webhook | dicit-webhook-api-ref-impl | 9292 | Container logs: `docker compose -f docker-compose.integration.yml logs webhook-api` |
| Encrypted S3 | MinIO | 9000 | MinIO console at http://localhost:9001 (minioadmin/minioadmin), browse `test-bucket` |
| SFTP | atmoz/sftp | 2222 | `sftp -P 2222 testuser@localhost` then `ls upload/` |
| JSON API | Sinatra receiver | 4567 | Container logs: `docker compose -f docker-compose.integration.yml logs json-api` |
| Shared email | ActionMailer | — | Check Rails server logs for email delivery (or use Mailcatcher) |

### Step-by-step walkthrough

```bash
# 1. Start Docker services
docker compose -f docker-compose.integration.yml up -d

# Wait for all services to be healthy
docker compose -f docker-compose.integration.yml ps

# 2. Run the setup rake task
bundle exec rake integration:setup

# 3. Start the Rails server
bin/rails server

# 4. In your browser:
#    - Go to http://localhost:3000/integration_test
#    - Log in via OmniAuth (test@integration.local)
#    - Create an invitation, then complete the CBV flow as the applicant
#    - When the caseworker submits the report, all 5 transmitters fire

# 5. Verify transmissions:
#    - Webhook: docker compose -f docker-compose.integration.yml logs webhook-api
#    - S3: open http://localhost:9001 and check test-bucket
#    - SFTP: sftp -P 2222 testuser@localhost, then ls upload/
#    - JSON: docker compose -f docker-compose.integration.yml logs json-api
#    - Email: check Rails server output or Mailcatcher
```

### Teardown

```bash
bundle exec rake integration:teardown
docker compose -f docker-compose.integration.yml down
```

### Troubleshooting

**`Aws::Errors::InvalidSSOToken`** — Your AWS SSO session is expired. Either run `aws sso login` or bypass it with dummy credentials:

```bash
AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy AWS_REGION=us-east-1 \
  AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  bundle exec rake integration:setup
```

**`PG::UndefinedTable: partner_transmission_methods`** — Run `bin/rails db:migrate` first.

**Port already allocated** — A previous Docker run may still be holding a port. Run `docker compose -f docker-compose.integration.yml down` and try again.

---

## RSpec Integration Tests

The sections below cover the RSpec-based integration tests (separate from the end-to-end partner test above). These are unit-level tests that exercise each transmitter individually against the Docker services.

## Docker Services

The file `docker-compose.integration.yml` defines the following services:

| Service | Image | Port | Purpose |
|---|---|---|---|
| `sftp` | `atmoz/sftp:alpine` | 2222 | SFTP server for `SftpTransmitter` |
| `minio` | `minio/minio` | 9000 (API), 9001 (console) | S3-compatible storage for `EncryptedS3Transmitter` |
| `webhook-api` | [dicit-webhook-api-ref-impl](https://github.com/Digital-Public-Works/dicit-webhook-api-ref-impl) | 9292 | Webhook reference server for `WebhookTransmitter` |
| `json-api` | `ruby:3.4-alpine` + `lib/json_api_receiver.rb` | 4567 | JSON API receiver for `JsonTransmitter` |

A `minio-setup` helper container runs once on startup to create the `test-bucket` bucket. It exits automatically after setup completes.

Credentials:

- SFTP: user `testuser`, password `testpass`, upload directory `/upload`
- MinIO: user `minioadmin`, password `minioadmin`
- Webhook API: API key `my-secure-guid` (set via `VMI_API_KEY`)
- JSON API: API key `test-json-api-key` (set via `JSON_API_KEY`)

## Starting the Services

```bash
docker compose -f docker-compose.integration.yml up -d
```

The first run builds the webhook reference server from its GitHub repo, which may take a minute. Subsequent runs use the cached image.

Wait until the `minio-setup` container exits successfully before running tests:

```bash
docker compose -f docker-compose.integration.yml ps
```

## Running the Tests

All integration specs carry the tag `integration: true` and are excluded from the default RSpec run.

Run all integration tests:

```bash
bundle exec rspec --tag integration
```

Run a specific file:

```bash
bundle exec rspec spec/services/transmitters/sftp_transmitter_integration_spec.rb
bundle exec rspec spec/services/transmitters/encrypted_s3_transmitter_integration_spec.rb
bundle exec rspec spec/services/transmitters/json_transmitter_integration_spec.rb
bundle exec rspec spec/services/transmitters/webhook_transmitter_integration_spec.rb
bundle exec rspec spec/services/transmitters/multi_transmit_integration_spec.rb
```

## Tearing Down

```bash
docker compose -f docker-compose.integration.yml down
```

## Test Files

| File | Transmitter | Infrastructure |
|---|---|---|
| `sftp_transmitter_integration_spec.rb` | `SftpTransmitter` | SFTP container |
| `encrypted_s3_transmitter_integration_spec.rb` | `EncryptedS3Transmitter` | MinIO container |
| `json_transmitter_integration_spec.rb` | `JsonTransmitter` | JSON API receiver (port 4567) |
| `webhook_transmitter_integration_spec.rb` | `WebhookTransmitter` | Webhook ref impl (port 9292) |
| `multi_transmit_integration_spec.rb` | `CaseWorkerTransmitterJob` | Webhook ref impl + MinIO |

`SharedEmailTransmitter` does not have a Docker-backed integration test. It uses ActionMailer's test delivery mode and can be exercised without any running containers.

## How Each Test Connects to Its Service

**SFTP** -- The spec passes `port: 2222` in the transmission config, which `SftpGateway` uses instead of the default port 22. The spec also overrides `Net::SSH.start` to use password-only auth (avoiding ed25519 key scanning).

**Encrypted S3** -- The spec overrides `Aws::S3::Client.new` to add `endpoint: "http://localhost:9000"` and `force_path_style: true`, pointing the AWS SDK at MinIO. It also stubs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to `minioadmin`. GPG key generation is handled automatically by the `gpg_setup` shared context (`spec/support/context/gpg_setup.rb`), which creates a temporary keyring under `tmp/gpghome/` and tears it down after the suite.

**Webhook** -- The spec calls `WebMock.allow_net_connect!` in a `before` block and restores the default in `after`, so real HTTP connections to `localhost:9292` are permitted only during these tests. The reference server validates the X-VMI-* headers (Timestamp, Signature, API-Key, Confirmation-Code), verifies the HMAC signature, and validates the JSON payload schema. The API key defaults to `my-secure-guid` (configurable via `WEBHOOK_TEST_API_KEY` env var in the spec).

**JSON API** -- Same WebMock pattern as webhook. The JSON API receiver validates X-IVAAS-* headers and HMAC signatures. It runs on port 4567 using the in-repo `lib/json_api_receiver.rb` Sinatra app.

**Multi-transmit** -- Exercises `CaseWorkerTransmitterJob` with two transmission methods configured simultaneously (webhook and encrypted S3). Verifies that both deliveries complete and that `cbv_flow.transmitted_at` is set.

## Verifying Services Manually

Use these commands to confirm a service is reachable before running tests.

**SFTP:**

```bash
sftp -P 2222 testuser@localhost
# password: testpass
```

**MinIO console** (browser): http://localhost:9001
Login: `minioadmin` / `minioadmin`

**MinIO API via AWS CLI:**

```bash
aws --endpoint-url http://localhost:9000 s3 ls s3://test-bucket/
```

**Webhook reference server:**

```bash
curl http://localhost:9292/health
```

**JSON API receiver:**

```bash
curl -X POST http://localhost:4567 \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```
