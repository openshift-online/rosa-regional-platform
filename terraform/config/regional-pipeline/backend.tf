# Backend configuration for Regional Pipeline infrastructure
#
# This backend is configured DYNAMICALLY by the Central Pipeline
# when it bootstraps the Regional Pipeline.
#
# The Central Pipeline will run:
#   terraform init -reconfigure \
#     -backend-config="bucket=<central-state-bucket>" \
#     -backend-config="key=rosa-regional-<region>-pipeline/terraform.tfstate" \
#     -backend-config="region=<central-region>"
#
# This ensures Regional Pipeline state is stored in the Central state bucket
# for centralized management and disaster recovery.

terraform {
  backend "s3" {
    # Configured dynamically via -backend-config flags
    # Do not hard-code values here
  }
}
