# Region Deployment Configuration

This directory contains the Terraform configuration for managing the lifecycle of AWS Accounts within the Organization. It serves as the "source of truth" for which regions and clusters should exist.

## Purpose

The primary goal of this component is to "mint" (create and configure) new AWS Accounts. It uses the `aws_organizations_account` resource to provision accounts that are then used by the Central Pipeline to deploy cluster infrastructure.

## Configuration

New accounts are defined by adding YAML files to the `regions/` subdirectory.

### File Format

Each YAML file represents a single AWS Account/Region combination.

**Path:** `regions/<region-name>.yaml`

**Content:**
```yaml
name: "rosa-regional-us-east-2"           # The name of the AWS Account
email: "something@example.com"  # The root email for the account (must be unique)
region: "us-east-2"                       # The AWS Region for the cluster
type: "regional"                          # Cluster Type: 'regional' or 'management'
```

## Workflow

1.  **Add a Region:** Create a new YAML file in `regions/`.
2.  **Commit & Push:** Push the change to the repository.
3.  **Pipeline Trigger:** The Central Pipeline detects the change.
4.  **Account Creation:**
    *   This Terraform module runs.
    *   It creates the new AWS Account via AWS Organizations.
    *   It outputs the new Account ID and Role ARN.
5.  **Cluster Provisioning:** The pipeline orchestrator sees the new account in the outputs and triggers the cluster deployment into it.

## Outputs

The module exports a map of accounts, which is used by the orchestration script:

*   `accounts`: A map where keys are the configuration names and values contain:
    *   `id`: AWS Account ID
    *   `arn`: AWS Account ARN
    *   `name`: Account Name
    *   `region`: Target AWS Region
    *   `type`: Cluster Type
