# cloud-nuke Configuration

This directory contains the configuration for cloud-nuke operations used to clean up AWS resources.

## Files

- **cloud-nuke.yaml** - Configuration file for cloud-nuke that defines:
  - Target regions
  - Resource types to exclude
  - Resource filters (by name, tag, etc.)
  - Time-based filtering options

## Usage

The cloud-nuke functionality is accessed through Make targets:

```bash
# Install cloud-nuke binary
make install-cloud-nuke

# Dry run to see what would be deleted
make cloud-nuke-dry-run

# Actually delete resources (DESTRUCTIVE!)
make cloud-nuke
```

## Configuration

Edit `cloud-nuke.yaml` to customize which resources are targeted:

### Exclude Resource Types

```yaml
exclude:
  resource-types:
    - iam
    - s3
```

### Filter by Name or Tags

```yaml
filters:
  s3:
    - property: name
      value: "do-not-delete-.*"
  ec2:
    - property: tag:Environment
      value: production
```

### Time-based Filtering

```yaml
# Only delete resources older than 24 hours
older-than: 24h
```

## Region Selection

By default, cloud-nuke targets the region specified by:
1. `AWS_REGION` environment variable
2. Falls back to `us-east-1` if not set

Override at runtime:

```bash
AWS_REGION=us-west-2 make cloud-nuke-dry-run
```

## Python Script

The `scripts/cloud-nuke.py` wrapper script:
- Automatically handles AWS credential management (supports all boto3 credential sources)
- Displays AWS caller identity for verification
- Uses the configuration file from this directory
- Streams output to stderr for better visibility
- Supports both dry-run and destructive modes

## Safety Features

1. **AWS Account Confirmation** - Requires user to confirm the AWS account number before proceeding:
   - **Dry-run mode**: Displays account number and prompts for [y/N] confirmation
   - **Destructive mode**: Requires typing the exact account number to proceed
2. **Caller identity display** - Shows AWS account, user ID, and ARN before running
3. **Dry-run first** - Recommended workflow to preview changes
4. **Configuration-based filtering** - Protect critical resources via config
5. **Skip confirmation option** - `--skip-confirmation` flag available for automation (use with caution)

## Dependencies

- Python 3 with boto3 package
- cloud-nuke binary (install via `make install-cloud-nuke`)
- AWS credentials configured (via environment, ~/.aws/credentials, IAM role, etc.)
