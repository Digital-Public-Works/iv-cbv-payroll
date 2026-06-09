# CLAUDE.md - Project Guide for Claude Code

## Project Overview
Consent-Based Verification (CBV) Payroll, a.k.a. **Verify My Income (VMI)** — an income verification system that lets benefit applicants verify income by retrieving payroll data directly from payroll providers with the applicant's consent. **Argyle is the active provider; a Pinwheel integration exists in code but is NOT active in production.** Multi-tenant architecture supporting multiple **partners** (state agencies and non-state partners). Note: the system uses **no AI/ML** — it surfaces authoritative payroll data, and eligibility workers make benefit determinations.

## Tech Stack
- **Backend:** Ruby on Rails 7.2, Ruby 3.4
- **Frontend:** Hotwire (Turbo + Stimulus), USWDS (U.S. Web Design System)
- **Database:** PostgreSQL 14
- **Background jobs:** AWS SQS via Shoryuken (`config.active_job.queue_adapter = :shoryuken`)
- **Cache:** Rails in-process `:memory_store`. *(Redis is aspirational — NOT currently used; there is no Redis gem or running Redis.)*
- **Infra:** Terraform (in `/infra`), Docker, AWS (RDS, SES, S3, SQS)
- **JS Tests:** Vitest
- **Ruby Tests:** RSpec with Capybara, Selenium, VCR, Factory Bot

## Directory Structure
```
app/          - Rails application (models, controllers, views, services, components)
config/       - Rails configuration
db/           - Migrations and schema
spec/         - RSpec tests
infra/        - Terraform infrastructure code
docs/         - Documentation
analytics/    - Python Jupyter notebooks
.github/      - CI/CD workflows
```

## Common Commands
```bash
# Run all Ruby tests
bundle exec rspec

# Run a specific test file
bundle exec rspec spec/path/to/file_spec.rb

# Run JS tests
npx vitest run

# Start dev server (via Docker)
docker compose up

# Linting
bundle exec rubocop
bundle exec erblint --lint-all
npx prettier --check .

# Database
bin/rails db:migrate
bin/rails db:seed
```

## Testing Conventions
- Tests live in `spec/` mirroring `app/` structure
- Use Factory Bot for test data (factories in `spec/factories/`)
- VCR cassettes for external API calls
- Feature tests use Capybara + Selenium

## Code Style & Linting
- RuboCop with `rubocop-rails-omakase` and `rubocop-rspec`
- ERB Lint for templates
- Prettier for JavaScript (100 char width, 2-space indent)
- Pre-commit hooks configured in `.pre-commit-config.yaml`
- Follow existing Rails conventions in the codebase

## Key Patterns
- Multi-tenant: partner configs are **database-canonical** (`PartnerConfig`, hydrated by `ClientAgencyConfig` at boot — no runtime YAML; the `partner_config` rake task imports/exports YAML). Partners include PA DHS, AZ DES (live), LA LDH (legacy pilot), sandbox. Current term is "partner"; the legacy tenant column is still `client_agency_id`.
- i18n: all user-facing strings should use translation keys
- Service objects in `app/services/`
- ViewComponents in `app/components/`
- PDF generation (wkhtmltopdf) for income reports
- Aggregator integrations: **Argyle** (active). Pinwheel adapters exist in code but are **not in production use** — deprioritize Pinwheel-only concerns; re-enabling would require a full re-evaluation.

## CI/CD (GitHub Actions)
- `rspec.yml` — Ruby tests
- `e2e-tests.yml` — End-to-end tests
- `js-vitest.yml` — JavaScript tests
- `rubocop.yml` — Ruby linting
- `erblint.yml` — ERB linting
- `brakeman-analysis.yml` — Security scanning
- `i18n-health.yml` — Translation key validation
