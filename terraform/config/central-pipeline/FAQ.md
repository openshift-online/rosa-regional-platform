# Frequently Asked Questions (FAQ)

## Account Management & Security

### How are AWS accounts created for the Regional (RC) and Management (MC) clusters?

Accounts are "minted" automatically through the Central Pipeline using Infrastructure as Code.

1.  **Configuration:** You define a new account by creating a simple YAML file in the `terraform/region-deploy/regions/` directory (e.g., `us-east-1.yaml`). This file specifies the account name, root email, target region, and the cluster type (`regional` or `management`).
2.  **AWS Organizations:** When the pipeline runs, the `terraform/region-deploy` module reads these YAML files and uses the `aws_organizations_account` Terraform resource to call the AWS Organizations API.
3.  **Creation:** AWS provisions a completely new, isolated AWS Account within your Organization.

This process ensures that every cluster lives in its own clean, isolated boundary, reducing the blast radius of any potential issues.

### How does the Central Account access the Regional and Management accounts?

We use **Cross-Account Role Assumption** (`sts:AssumeRole`), which is the standard and secure way to manage multi-account AWS environments. We do **not** use long-lived IAM User credentials (Access Keys/Secret Keys) for this connection.

Here is the flow:

1.  **Automatic Role Creation:** When AWS Organizations creates a new member account (as described above), it automatically creates a specific IAM Role inside that new account named `OrganizationAccountAccessRole`. This role has administrative permissions by default.
2.  **Trust Relationship:** This role is configured to trust the **Management (Central) Account**. This means entities in the Central Account can ask to "become" this role.
3.  **Pipeline Access:**
    *   The Central Pipeline runs on AWS CodeBuild, using a service role (`central-pipeline-codebuild-role`).
    *   This CodeBuild role has a policy allowing it to call `sts:AssumeRole` on `arn:aws:iam::*:role/OrganizationAccountAccessRole`.
4.  **Runtime:** When the orchestration script needs to deploy to a child account:
    *   It calls the AWS STS API to assume the `OrganizationAccountAccessRole` in the target child account.
    *   STS returns a set of **temporary, short-lived credentials** (Access Key, Secret Key, and Session Token).
    *   The script injects these temporary credentials into the environment for that specific deployment step.
