# Backend configuration for the Central Pipeline infrastructure
#
# This backend stores the state for the central-pipeline infrastructure itself.
#
# BOOTSTRAP PROBLEM:
# There's a chicken-and-egg problem here - we need an S3 bucket to store state,
# but we're creating that bucket with Terraform. The solution:
#
# 1. First deployment: Comment out this entire file and deploy with local state
# 2. Note the bucket name from terraform output "central_pipeline_state_bucket"
# 3. Uncomment this file and update the bucket name below
# 4. Run: terraform init -migrate-state
# 5. Confirm migration when prompted
# 6. Local state file can now be deleted
#
# For subsequent deployments, this backend configuration will be active.

# Uncomment after initial bootstrap:
# terraform {
#   backend "s3" {
#     # Update with actual bucket name from output: central_pipeline_state_bucket
#     bucket = "central-pipeline-state-XXXXXX"
#     key    = "central-pipeline/terraform.tfstate"
#     region = "us-east-1"  # Update to match var.region if different
#
#     # Enable state locking (optional but recommended)
#     # dynamodb_table = "central-pipeline-state-lock"
#   }
# }
