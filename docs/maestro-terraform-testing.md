# Maestro Terraform Infrastructure Testing Guide

## Overview

This guide walks through testing the Maestro infrastructure Terraform module that has been integrated into the regional cluster configuration.

## What's Been Integrated

The maestro-infrastructure module is now called from `terraform/config/regional-cluster/main.tf` and will provision:

- **AWS IoT Core**: MQTT broker, Things, certificates, and policies
- **RDS PostgreSQL**: Database for Maestro Server state
- **AWS Secrets Manager**: MQTT certificates, DB credentials, consumer registrations
- **IAM Roles**: Pod Identity roles for Maestro Server and Agents (ASCP CSI Driver uses Pod Identity automatically)

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.9.0 installed
3. Existing regional cluster configuration in `terraform.tfvars`

## Testing Steps

### Step 1: Review Configuration

Check the current terraform.tfvars or update from the example:

```bash
cd terraform/config/regional-cluster

# If you don't have terraform.tfvars, copy from example
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and update Maestro section:
# management_cluster_ids = ["management-01"]  # Your management cluster IDs
# maestro_db_instance_class = "db.t4g.micro"
# maestro_db_multi_az = false
# maestro_db_deletion_protection = false
```

### Step 2: Initialize Terraform

```bash
cd terraform/config/regional-cluster
terraform init
```

This will download the required providers (AWS, Random, HTTP).

### Step 3: Plan Infrastructure

```bash
terraform plan -out=tfplan
```

**Review the plan output carefully.** You should see resources being created for:

- `module.maestro_infrastructure.aws_iot_thing.maestro_server`
- `module.maestro_infrastructure.aws_iot_certificate.maestro_server`
- `module.maestro_infrastructure.aws_iot_thing.maestro_agent[0]` (one per management cluster)
- `module.maestro_infrastructure.aws_db_instance.maestro`
- `module.maestro_infrastructure.aws_secretsmanager_secret.*` (multiple secrets)
- `module.maestro_infrastructure.aws_iam_role.*` (multiple roles)
- `module.maestro_infrastructure.aws_eks_pod_identity_association.*`

**Expected resource count**: ~30-40 new resources depending on the number of management clusters.

### Step 4: Apply Infrastructure (Optional)

**WARNING**: This will provision real AWS resources and incur costs (~$20-25/month).

```bash
terraform apply tfplan
```

Wait for completion (typically 5-10 minutes due to RDS provisioning).

### Step 5: Verify Resources

After apply completes, verify the resources were created:

#### Check AWS IoT Core

```bash
# Get the cluster name from outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)

# List IoT Things
aws iot list-things | grep maestro

# Describe server thing
aws iot describe-thing --thing-name ${CLUSTER_NAME}-maestro-server

# Describe agent thing(s)
aws iot describe-thing --thing-name management-01-maestro-agent
```

#### Check RDS Database

```bash
# List RDS instances
aws rds describe-db-instances \
  --db-instance-identifier ${CLUSTER_NAME}-maestro \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address,Endpoint.Port]' \
  --output table
```

#### Check Secrets Manager

```bash
# List secrets
aws secretsmanager list-secrets \
  --filters Key=name,Values=${CLUSTER_NAME}/maestro \
  --query 'SecretList[*].[Name,ARN]' \
  --output table
```

#### Check IAM Roles

```bash
# List IAM roles
aws iam list-roles \
  --query "Roles[?contains(RoleName, '${CLUSTER_NAME}-maestro')].[RoleName,Arn]" \
  --output table
```

### Step 6: Review Terraform Outputs

Terraform outputs contain all configuration needed for Helm charts:

```bash
# View all Maestro outputs
terraform output maestro_configuration_summary

# View specific outputs
terraform output maestro_iot_mqtt_endpoint
terraform output maestro_rds_address
terraform output maestro_server_role_arn
```

**Save these outputs** - you'll need them when creating Helm values files.

### Step 7: Verify Secret Contents

Check that secrets contain the expected data:

```bash
# Get server MQTT certificate secret
SECRET_NAME=$(terraform output -raw maestro_server_mqtt_cert_secret_name)
aws secretsmanager get-secret-value \
  --secret-id ${SECRET_NAME} \
  --query 'SecretString' \
  --output text | jq

# Expected keys: certificate, privateKey, caCert, endpoint, port, clientId
```

```bash
# Get database credentials secret
DB_SECRET_NAME=$(terraform output -raw maestro_db_credentials_secret_name)
aws secretsmanager get-secret-value \
  --secret-id ${DB_SECRET_NAME} \
  --query 'SecretString' \
  --output text | jq

# Expected keys: username, password, host, port, database
```

### Step 8: Test Database Connectivity (Optional)

If you want to verify the database is accessible from within the cluster:

```bash
# Get database endpoint
DB_ENDPOINT=$(terraform output -raw maestro_rds_address)

# Get database credentials from secret
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id ${DB_SECRET_NAME} \
  --query 'SecretString' \
  --output text | jq -r '.password')

# From a pod in the EKS cluster (after cluster is provisioned):
kubectl run -it --rm postgres-test \
  --image=postgres:16 \
  --restart=Never \
  -- psql -h ${DB_ENDPOINT} -U maestro_admin -d maestro -c "SELECT version();"
# Enter password when prompted
```

## Cleanup (Destroy Resources)

**WARNING**: This will delete all Maestro infrastructure including the database.

```bash
# Ensure db_skip_final_snapshot is true in terraform.tfvars
# or manually edit terraform/modules/maestro-infrastructure/rds.tf

terraform destroy
```

If you have `db_deletion_protection = true`, you'll need to:
1. Set it to `false` in terraform.tfvars
2. Run `terraform apply` to update
3. Then run `terraform destroy`

## Troubleshooting

### Issue: "Error creating DB Instance: InvalidParameterValue"

**Cause**: DB subnet group doesn't span enough AZs or invalid instance class.

**Solution**: Check that `private_subnets` covers at least 2 AZs and the instance class is available in your region.

### Issue: "Error creating IoT Certificate: ThrottlingException"

**Cause**: AWS IoT Core API rate limiting.

**Solution**: Reduce the number of management clusters or add delays between applies.

### Issue: "Error creating Secret: AccessDeniedException"

**Cause**: AWS credentials lack Secrets Manager permissions.

**Solution**: Ensure your AWS credentials have `secretsmanager:CreateSecret` and `secretsmanager:PutSecretValue` permissions.

### Issue: Pod Identity Association creation fails

**Cause**: EKS cluster doesn't have Pod Identity addon installed.

**Solution**: Verify `eks-pod-identity-agent` addon is listed in the EKS cluster module addons.

## Cost Monitoring

Track costs during testing:

```bash
# Check RDS pricing
aws pricing get-products \
  --service-code AmazonRDS \
  --filters Type=TERM_MATCH,Field=instanceType,Value=db.t4g.micro \
  --region us-east-1

# Expected monthly costs:
# - RDS db.t4g.micro: ~$15-20
# - Secrets Manager: ~$2.50 (5 secrets × $0.40 + API calls)
# - IoT Core: ~$1-2 (minimal message volume)
# - Total: ~$20-25/month
```

## Next Steps

After successful infrastructure provisioning:

1. **Verify ASCP CSI Driver** - Verify EKS addon installed automatically
2. **Create Helm Charts** - Adapt ARO-HCP templates for AWS
3. **Deploy Maestro Server** - Using Helm chart with values from Terraform outputs
4. **Deploy Maestro Agent** - To management cluster(s)
5. **Test E2E** - ManifestWork creation and propagation via MQTT

See `docs/maestro-implementation-status.md` for overall progress tracking.
