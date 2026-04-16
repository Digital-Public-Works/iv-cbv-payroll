# Transmission Integration Tests

Integration tests verify that each transmitter can deliver payloads to real infrastructure. They run against local Docker containers instead of mocked services.

## Prerequisites

- Docker and Docker Compose
- The application's PostgreSQL database must be running
- Database migrations must be up to date (`bin/rails db:migrate`)

Note: PDF generation is stubbed in the integration specs to avoid requiring `sassc-rails` (which is not in the production bundle).

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
| `integration:docker:up` | Start the Docker services (SFTP, MinIO, webhook-api, json-api) |
| `integration:docker:down` | Stop the Docker services |
| `integration:docker:ps` | Show Docker service status |
| `integration:rspec:all` | Run every integration spec (verifies Docker is up first) |
| `integration:rspec:webhook` | Run just the webhook transmitter spec |
| `integration:rspec:sftp` | Run just the SFTP transmitter spec |
| `integration:rspec:encrypted_s3` | Run just the encrypted S3 transmitter spec |
| `integration:rspec:json` | Run just the JSON transmitter spec |
| `integration:partner:setup` | Create the `integration_test` partner and API service account (for e2e browser testing) |
| `integration:partner:teardown` | Remove the `integration_test` partner and service account |

List them all with `bundle exec rake -T integration`.

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

## Test Files

All integration specs carry the tag `integration: true` and are excluded from the default RSpec run.

| File | Transmitter | Infrastructure |
|---|---|---|
| `sftp_transmitter_integration_spec.rb` | `SftpTransmitter` | SFTP container |
| `encrypted_s3_transmitter_integration_spec.rb` | `EncryptedS3Transmitter` | MinIO container |
| `json_transmitter_integration_spec.rb` | `JsonTransmitter` | JSON API receiver (port 4567) |
| `webhook_transmitter_integration_spec.rb` | `WebhookTransmitter` | Webhook ref impl (port 9292) |

`SharedEmailTransmitter` does not have a Docker-backed integration test. It uses ActionMailer's test delivery mode and can be exercised without any running containers.

## How Each Test Connects to Its Service

**SFTP** — The spec passes `port: 2222` in the transmission config, which `SftpGateway` uses instead of the default port 22. The spec also overrides `Net::SSH.start` to use password-only auth (avoiding ed25519 key scanning).

**Encrypted S3** — The spec overrides `Aws::S3::Client.new` to add `endpoint: "http://localhost:9000"` and `force_path_style: true`, pointing the AWS SDK at MinIO. It also stubs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to `minioadmin`. GPG key generation is handled automatically by the `gpg_setup` shared context (`spec/support/context/gpg_setup.rb`).

**Webhook** — The spec calls `WebMock.allow_net_connect!` in a `before` block and restores the default in `after`, so real HTTP connections to `localhost:9292` are permitted only during these tests. The reference server validates the `X-VMI-*` headers (Timestamp, Signature, API-Key, Confirmation-Code), verifies the HMAC signature, and validates the JSON payload schema.

**JSON API** — Same WebMock pattern as webhook. The JSON API receiver validates `X-IVAAS-*` headers and HMAC signatures. It runs on port 4567 using the in-repo `lib/json_api_receiver.rb` Sinatra app.

## End-to-End Browser Testing (optional)

The `integration:partner:setup` task creates an `integration_test` partner and a service-account user with an API access token. This lets you exercise the full CBV flow end-to-end through a browser, with real webhook delivery to the Docker services.

```bash
# 1. Start Docker services
bundle exec rake integration:docker:up

# 2. Create the integration_test partner + API token
bundle exec rake integration:partner:setup

# 3. Start the Rails server
bin/rails server

# 4. The setup task prints a curl command — run it to create an invitation.
#    The response includes a `tokenized_url`; open it in your browser and
#    complete the CBV flow. The webhook transmitter will fire at the end.

# 5. Verify the webhook container received the payload:
docker compose -f docker-compose.integration.yml logs webhook-api

# 6. Clean up
bundle exec rake integration:partner:teardown
bundle exec rake integration:docker:down
```

The `integration_test` partner is configured with a single webhook transmission method (see `docs/app/integration-test-partner.yml`). Authentication uses API tokens — there is no caseworker UI or generic link.

## Verifying Services Manually

Use these commands to confirm a service is reachable.

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

## Troubleshooting

**`Aws::Errors::InvalidSSOToken`** — Your AWS SSO session is expired. Either run `aws sso login` or bypass it with dummy credentials:

```bash
AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy AWS_REGION=us-east-1 \
  AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  bundle exec rake integration:partner:setup
```

**Port already allocated** — A previous Docker run may still be holding a port. Run `bundle exec rake integration:docker:down` and try again.

**`Docker services not running`** — The `integration:rspec:*` tasks check that `sftp`, `minio`, `webhook-api`, and `json-api` containers are all running. If any are missing, run `integration:docker:up` first (the `minio-setup` helper exits after it creates the bucket; that's fine).
