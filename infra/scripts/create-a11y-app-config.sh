#!/bin/bash

set -e

PROFILE="demo"
ENVIRONMENT="a11y"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== AWS STS Identity Check ===${NC}"
if ! STS_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>&1); then
  echo -e "${RED}ERROR: Failed to authenticate with AWS profile '$PROFILE'${NC}"
  echo "$STS_IDENTITY"
  exit 1
fi

ACCOUNT_ID=$(echo "$STS_IDENTITY" | grep Account | awk '{print $2}' | tr -d '"' | tr -d ',')
ARN=$(echo "$STS_IDENTITY" | grep Arn | awk '{print $2}' | tr -d '"' | tr -d ',')

echo -e "${GREEN}✓ Successfully authenticated${NC}"
echo "  Account ID: $ACCOUNT_ID"
echo "  ARN: $ARN"
echo ""

# Function to create parameter
create_parameter() {
  local name=$1
  local value=$2
  local type=$3
  local description=$4

  echo -ne "Creating $name... "

  if aws ssm put-parameter \
    --profile "$PROFILE" \
    --name "$name" \
    --value "$value" \
    --type "$type" \
    --description "$description" \
    --overwrite \
    --region us-east-1 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗${NC}"
    return 1
  fi
}

echo -e "${YELLOW}=== Creating Multi-Tenant Configuration Parameters ===${NC}"
echo ""
# Sandbox Tenant (Testing)
echo -e "${YELLOW}Sandbox Tenant${NC}"
create_parameter "/service/app-a11y/sandbox-domain-name" "a11y.divt.app" "String" "Domain for sandbox testing"
create_parameter "/service/app-a11y/sandbox-argyle-environment" "sandbox" "String" "Argyle environment: sandbox or production"
create_parameter "/service/app-a11y/sandbox-pinwheel-environment" "sandbox" "String" "Pinwheel environment: sandbox or production"
create_parameter "/service/app-a11y/agency-default-active" "false" "String" "Disable sandbox by default"
echo ""

# Arizona DES Tenant
echo -e "${YELLOW}Arizona DES Tenant${NC}"
create_parameter "/service/app-a11y/az-des-domain-name" "az.a11y.divt.app" "String" "Agency-specific domain"
create_parameter "/service/app-a11y/az-des-sftp-user" "change-me" "SecureString" "SFTP username for file transmission"
create_parameter "/service/app-a11y/az-des-sftp-password" "change-me" "SecureString" "SFTP password"
create_parameter "/service/app-a11y/az-des-sftp-url" "sftp.az-des.example.com" "String" "SFTP server URL"
create_parameter "/service/app-a11y/az-des-sftp-directory" "/reports" "String" "Target directory path"
create_parameter "/service/app-a11y/az-des-argyle-environment" "sandbox" "String" "Argyle environment: sandbox or production"
create_parameter "/service/app-a11y/az-des-pinwheel-environment" "sandbox" "String" "Pinwheel environment: sandbox or production"
create_parameter "/service/app-a11y/az-des-weekly-report-recipients" "operations-a11y-email-aaaatjjoloi6in3i54tkvqcwca@digitalpublicworks.slack.com" "String" "Comma-separated email list"
create_parameter "/service/app-a11y/agency-az-des-active" "true" "String" "Enable AZ DES tenant"
echo ""

# PA DHS Tenant
echo -e "${YELLOW}PA DHS Tenant${NC}"
create_parameter "/service/app-a11y/pa-dhs-domain-name" "pa.divt.app" "String" "Agency-specific domain"
create_parameter "/service/app-a11y/pa-dhs-sftp-user" "changeme" "SecureString" "SFTP username for file transmission"
create_parameter "/service/app-a11y/pa-dhs-sftp-password" "changeme" "SecureString" "SFTP password"
create_parameter "/service/app-a11y/pa-dhs-sftp-url" "sftp.pa-dhs.example.com" "String" "SFTP server URL"
create_parameter "/service/app-a11y/pa-dhs-sftp-directory" "/reports" "String" "Target directory path"
create_parameter "/service/app-a11y/pa-dhs-argyle-environment" "sandbox" "String" "Argyle environment: sandbox or production"
create_parameter "/service/app-a11y/pa-dhs-pinwheel-environment" "sandbox" "String" "Pinwheel environment: sandbox or production"
create_parameter "/service/app-a11y/pa-dhs-weekly-report-recipients" "operations-a11y-email-aaaatjjoloi6in3i54tkvqcwca@digitalpublicworks.slack.com" "String" "Comma-separated email list"
create_parameter "/service/app-a11y/agency-pa-dhs-active" "true" "String" "Enable PA DHS tenant"
echo ""

# Louisiana LDH Tenant (Deprecated)
echo -e "${YELLOW}Louisiana LDH Tenant (Deprecated)${NC}"
create_parameter "/service/app-a11y/la-ldh-domain-name" "la.divt.app" "String" "Agency-specific domain"
create_parameter "/service/app-a11y/la-ldh-email" "contact@la-ldh.example.com" "String" "Contact email for agency"
create_parameter "/service/app-a11y/la-ldh-pilot-enabled" "false" "String" "Pilot status"
create_parameter "/service/app-a11y/la-ldh-argyle-environment" "sandbox" "String" "Argyle environment: sandbox or production"
create_parameter "/service/app-a11y/la-ldh-pinwheel-environment" "sandbox" "String" "Pinwheel environment: sandbox or production"
create_parameter "/service/app-a11y/la-ldh-weekly-report-recipients" "operations-a11y-email-aaaatjjoloi6in3i54tkvqcwca@digitalpublicworks.slack.com" "String" "Comma-separated email list"
echo ""

# Azure AD Integration (Deprecated)
echo -e "${YELLOW}Azure AD Integration (Deprecated)${NC}"
create_parameter "/service/app-a11y/azure-sandbox-client-id" "YOUR_CLIENT_ID" "SecureString" "Azure AD Sandbox Client ID"
create_parameter "/service/app-a11y/azure-sandbox-client-secret" "YOUR_CLIENT_SECRET" "SecureString" "Azure AD Sandbox Client Secret"
create_parameter "/service/app-a11y/azure-sandbox-tenant-id" "YOUR_TENANT_ID" "SecureString" "Azure AD Sandbox Tenant ID"
echo ""

echo -e "${GREEN}=== All parameters created successfully ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review and update placeholder values in AWS Systems Manager Parameter Store"
echo "2. Configure real SFTP credentials for AZ DES and PA DHS"
echo "3. Update email addresses with actual recipient lists"
echo "4. Set Azure AD credentials if using that integration"
