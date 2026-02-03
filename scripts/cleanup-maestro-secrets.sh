#!/bin/bash
set -e

# =============================================================================
# Cleanup Maestro Secrets
# =============================================================================
# This script force-deletes the Secrets Manager secrets used by Maestro.
# Use this if you encounter "InvalidRequestException" during Terraform apply
# stating that a secret is "scheduled for deletion".
#
# Usage:
#   ./scripts/cleanup-maestro-secrets.sh
# =============================================================================

SECRETS=(
  "maestro/server-cert"
  "maestro/server-config"
  "maestro/db-credentials"
)

echo "Cleaning up Maestro secrets..."
echo "This will FORCE DELETE the following secrets without recovery:"

for secret in "${SECRETS[@]}"; do
  echo "  - $secret"
done

read -p "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Operation cancelled."
  exit 0
fi

for secret in "${SECRETS[@]}"; do
  echo "Deleting secret: $secret"
  # Attempt delete, suppress output, but allow error if it fails (e.g. permission issue)
  # We use || true to continue if the secret doesn't exist.
  aws secretsmanager delete-secret \
    --secret-id "$secret" \
    --force-delete-without-recovery \
    --no-cli-pager || echo "⚠️  Failed to delete $secret (it might not exist or you lack permissions)"
done

echo "----------------------------------------------------------------"
echo "✅ Cleanup commands executed."
echo "   Note: It may take a few seconds for AWS to fully process the deletion."
echo "----------------------------------------------------------------"
