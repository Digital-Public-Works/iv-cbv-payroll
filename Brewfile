# Brewfile
# add any dependencies that must be installed from homebrew here

# Ruby version manager
brew "rbenv"

# NodeJS version manager
brew "nodenv"

# Python (required for moto and other development tools)
brew "python@3"

# production (Aurora PostgreSQL) and docker-compose use postgres 14
brew "postgresql@14", link: true

# docker is used for building images for deployment, and in the bin/with-server script
cask "docker-desktop"
brew "dockerize"

# helper scripts for creating new ADRs
brew "adr-tools"

# chromedriver for integration tests is downloaded automatically by Selenium Manager
# (selenium-webdriver >= 4.11); just have Google Chrome installed.

# used by rails-erd documentation tool
brew "graphviz"

# used in many scripts in "infra"
brew "jq"

# ngrok local tunnel to receive webhooks
cask "ngrok"

# Terraform version manager for infrastructure
brew "tfenv"

# AWS command-line utilities necessary for deploying and operations
brew "awscli"
cask "session-manager-plugin"

# necessary for file encryption
brew "gpg"

# linters / workflow tools
brew "pre-commit"
brew "shellcheck"
brew "checkov"
brew "actionlint"
brew "hadolint"
