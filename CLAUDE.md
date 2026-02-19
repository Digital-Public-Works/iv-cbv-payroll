# CLAUDE.md - Project Guide for Claude Code

## Project Overview
Consent-Based Verification (CBV) Payroll — an income verification system that lets benefit applicants verify income via payroll providers (Argyle, Pinwheel). Multi-tenant architecture supporting multiple state/agency partners.

## Tech Stack
- **Backend:** Ruby on Rails 7.2, Ruby 3.4
- **Frontend:** Hotwire (Turbo + Stimulus), USWDS (U.S. Web Design System)
- **Database:** PostgreSQL 14
- **Cache/Jobs:** Redis, AWS SQS
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
- Multi-tenant: site configs per agency partner (AZ DES, LA DHH, PA DHS, sandbox)
- i18n: all user-facing strings should use translation keys
- Service objects in `app/services/`
- ViewComponents in `app/components/`
- PDF generation (wkhtmltopdf) for income reports
- Aggregator integrations: Argyle and Pinwheel adapters

## CI/CD (GitHub Actions)
- `rspec.yml` — Ruby tests
- `e2e-tests.yml` — End-to-end tests
- `js-vitest.yml` — JavaScript tests
- `rubocop.yml` — Ruby linting
- `erblint.yml` — ERB linting
- `brakeman-analysis.yml` — Security scanning
- `i18n-health.yml` — Translation key validation
