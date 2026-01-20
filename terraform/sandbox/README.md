# AWS Sandbox Account Leasing System

This repository implements a **"Lease, Test, Nuke, Recycle"** pattern for managing AWS sandbox accounts. It is designed to support automated testing (e.g., EKS Testing) in environments like FedRAMP where account creation/deletion is rate-limited or restricted. Instead of creating new accounts for every test, this system maintains a pool of reusable accounts that are locked ("leased") during tests and returned ("released") afterwards.

## Overview

The system prevents race conditions and ensures isolation between concurrent tests by using a centralized locking mechanism in DynamoDB. It also automates the cleanup ("nuking") of accounts between uses to ensure a clean slate.

### Workflow
1.  **Lease:** A test runner requests an account.
    *   The system atomically locks an `AVAILABLE` account.
    *   It runs `cloud-nuke` to ensure the account is clean.
    *   It creates a temporary IAM user (`sandbox-temporary-user`) with `AdministratorAccess`.
    *   It returns the credentials for this temporary user.
2.  **Test:** The runner uses the provided credentials to deploy infrastructure and run tests.
3.  **Recycle (Release):** The runner releases the account.
    *   The system attempts to run `cloud-nuke` again to clean up resources.
    *   It deletes the temporary IAM user.
    *   It updates the account status back to `AVAILABLE`.

## Architecture

### Components
*   **DynamoDB Table (`AccountPool`):** Stores the state of each account (`AVAILABLE`, `IN_USE`, or `DIRTY`).
*   **Python Scripts (`scripts/`):**
    *   `lease_account.py`: Scans for available accounts, locks one, assumes `OrganizationAccountAccessRole` to clean the account and create a temporary user.
    *   `release_account.py`: Cleans the account using `cloud-nuke`, deletes the temporary user, and returns the account to the pool.
*   **Infrastructure (`terraform/`):** Manages the DynamoDB table and seeds the initial account list.

### State Machine
*   **AVAILABLE:** Account is ready to be leased.
*   **IN_USE:** Account is currently locked by a test runner.
*   **DIRTY:** Account failed cleanup or encountered an error. Requires manual intervention.

## Prerequisites

*   **AWS CLI:** Configured with permissions to read/write the DynamoDB table and assume roles.
*   **Terraform:** v1.5.7 or later.
*   **Python:** 3.x with `boto3`.
*   **Access:** Permissions to assume `OrganizationAccountAccessRole` in the target sandbox accounts.

## Setup

### 1. Environment Setup
Run the provided setup script to install Terraform, AWS CLI, and Python dependencies:

```bash
./scripts/setup_env.sh
```

### 2. Infrastructure Deployment
Initialize and apply the Terraform configuration to create the `AccountPool` table.

```bash
cd terraform
terraform init
terraform apply
```

## Configuration

### Environment Variables
The Python scripts use the following environment variables:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `DYNAMODB_TABLE_NAME` | Name of the DynamoDB table. | `AccountPool` |
| `AWS_REGION` | AWS Region where the table resides and where `cloud-nuke` will operate. | `us-east-2` |
| `LEASE_TIMEOUT` | Seconds to wait for an available account. | `10` |

### Terraform Variables
Configure the pool size in `terraform/variables.tf` or via a `.tfvars` file:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `account_ids` | List of AWS Account IDs to populate in the pool. | `["109342711269", ...]` |

## Usage Guide

### 1. Lease an Account
Run the lease script to acquire an account. It will output a JSON object containing the `account_id` and temporary `credentials` for `sandbox-temporary-user`.

```bash
python3 scripts/lease_account.py
```

**Output Example:**
```json
{
  "account_id": "123456789012",
  "status": "success",
  "credentials": {
    "AccessKeyId": "AKIA...",
    "SecretAccessKey": "...",
    "SessionToken": null,
    "Expiration": null
  }
}
```

The script emits debug information to `stderr` (e.g., "Attempting to lease account...", "Running cloud-nuke..."), keeping `stdout` clean for JSON parsing.

### 2. Run Tests
Use the credentials from step 1 to run your tests. These credentials belong to an IAM user created specifically for this session.

### 3. Release the Account
Once testing is complete, release the account back to the pool. This triggers a final cleanup.

```bash
python3 scripts/release_account.py <ACCOUNT_ID>
```

**Example:**
```bash
python3 scripts/release_account.py 123456789012
```

## CI/CD Integration

This process is designed for AWS CodeBuild or other CI/CD. See [BUILDSPEC_SNIPPET.md](BUILDSPEC_SNIPPET.md) for a practical example of how to integrate these scripts into your `buildspec.yml`.

The typical pipeline flow is:
1.  **Pre_build:** Run `lease_account.py`, parse and export credentials.
2.  **Build:** Run tests (e.g., `go test`, `terraform apply`) using the exported credentials.
3.  **Post_build:** Run `release_account.py` to clean up and unlock the account.

## Troubleshooting

*   **Timeout (No accounts available):**
    *   The pool may be exhausted. Wait for a test to finish or increase the number of accounts.
    *   The script prints a list of `IN_USE` accounts to stderr when it times out.
*   **"Account not found" during Release:**
    *   Ensure you are releasing the correct Account ID.
*   **Dirty Accounts:**
    *   If `cloud-nuke` fails during lease or release, the account is marked `DIRTY`.
    *   Check `stderr` output for the specific error.
    *   Manual intervention (fixing the resource, manually nuking, and setting status back to `AVAILABLE` in DynamoDB) is required.
