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
| `integration:docker:up` | Start the Docker services (SFTP, webhook-api) |
| `integration:docker:down` | Stop the Docker services |
| `integration:docker:ps` | Show Docker service status |
| `integration:rspec:all` | Run every integration spec (verifies Docker is up first) |
| `integration:rspec:webhook` | Run just the webhook transmitter spec |
| `integration:rspec:sftp` | Run just the SFTP transmitter spec |
| `integration:partner:setup` | Create the `integration_test` partner and API service account (for e2e browser testing) |
| `integration:partner:teardown` | Remove the `integration_test` partner and service account |

List them all with `bundle exec rake -T integration`.

## Docker Services

The file `docker-compose.integration.yml` defines the following services:

| Service | Image | Port | Purpose |
|---|---|---|---|
| `sftp` | `atmoz/sftp:latest` | 2222 | SFTP server for `SftpTransmitter` |
| `webhook-api` | [dicit-webhook-api-ref-impl](https://github.com/Digital-Public-Works/dicit-webhook-api-ref-impl) | 9292 | Webhook reference server for `WebhookTransmitter` |

Credentials:

- SFTP: user `testuser`, password `testpass`, upload directory `/upload`
- Webhook API: API key `my-secure-guid` (set via `VMI_API_KEY`)

## Test Files

Integration specs carry the tag `integration: true` and are excluded from the default RSpec run.

| File | Transmitter | Infrastructure |
|---|---|---|
| `sftp_transmitter_integration_spec.rb` | `SftpTransmitter` | SFTP container |
| `webhook_transmitter_integration_spec.rb` | `WebhookTransmitter` | Webhook ref impl (port 9292) |

## How Each Test Connects to Its Service

**SFTP** — The spec passes `port: 2222` in the transmission config, which `SftpGateway` uses instead of the default port 22. The spec also overrides `Net::SSH.start` to use password-only auth (avoiding ed25519 key scanning).

**Webhook** — The spec calls `WebMock.allow_net_connect!` in a `before` block and restores the default in `after`, so real HTTP connections to `localhost:9292` are permitted only during these tests. The reference server validates the `X-VMI-*` headers (Timestamp, Signature, API-Key, Confirmation-Code), verifies the HMAC signature, and validates the JSON payload schema.

## End-to-End Browser Testing (optional)

The `integration:partner:setup` task creates an `integration_test` partner and a service-account user with an API access token. This lets you exercise the full CBV flow end-to-end through a browser, with real webhook delivery to the Docker services.

The `integration_test` partner is configured with a single webhook transmission method (see `docs/app/integration-test-partner.yml`). Authentication uses API tokens — there is no caseworker UI or generic link.

```bash
# 1. Start Docker services
bundle exec rake integration:docker:up

# 2. Create the integration_test partner + API token
bundle exec rake integration:partner:setup
# Note the API access token printed by this task.

# 3. Start the Rails server
bin/rails server
```

Then create an invitation using the API token from step 2:

```bash
curl -X POST http://localhost:3000/api/v1/invitations \
  -H 'Authorization: Bearer <YOUR_API_ACCESS_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{
    "language": "en",
    "agency_partner_metadata": {
      "case_number": "ABC1234",
      "first_name": "Jane",
      "last_name": "Doe"
    }
  }'
```

The response includes a `tokenized_url` — open it in your browser and complete the CBV flow. When the caseworker submits the report, the webhook transmitter fires.

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

## Troubleshooting

**Port already allocated** — A previous Docker run may still be holding a port. Run `bundle exec rake integration:docker:down` and try again.

**Connection refused from specs** — The `integration:rspec:*` tasks require the Docker services to be running. If you see `Errno::ECONNREFUSED` or SFTP timeouts, run `bundle exec rake integration:docker:ps` to check status and `bundle exec rake integration:docker:up` to start them.
