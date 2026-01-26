# Maestro Manual Certificate Transfer Guide

## Overview

Maestro agent MQTT certificates are minted by the **Regional Cluster Terraform** but stored in the **Management Cluster's AWS Secrets Manager**. This requires a manual transfer process between regional and management cluster operators.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Regional AWS Account (123456789012)                         │
│                                                              │
│ Regional Terraform:                                         │
│  1. Creates IoT Certificate via AWS IoT Core               │
│  2. Outputs certificate as SENSITIVE Terraform output       │
│                                                              │
│ Regional Operator:                                          │
│  3. Runs: terraform output -json maestro_agent_certificates│
│  4. Securely transfers certificate data to MC operator     │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ Secure Transfer (manually)
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Management AWS Account (987654321098)                       │
│                                                              │
│ Management Operator:                                        │
│  5. Receives certificate data securely                      │
│  6. Stores in Terraform variables (terraform.tfvars)       │
│                                                              │
│ Management Terraform:                                       │
│  7. Creates secret in LOCAL Secrets Manager                 │
│  8. Creates IAM role for agent                             │
│  9. Creates Pod Identity association                        │
│                                                              │
│ Maestro Agent:                                              │
│  10. Uses ASCP to mount secret from LOCAL Secrets Manager  │
│  11. Connects to regional IoT Core with certificate        │
└─────────────────────────────────────────────────────────────┘
```

## Why Manual Transfer?

**Alternative approaches and why we chose manual transfer:**

1. ❌ **Cross-Account Secret Access** - Requires complex IAM trust policies and resource policies
2. ❌ **Terraform Remote State** - Creates tight coupling and S3 access dependencies
3. ✅ **Manual Transfer** - Simple, secure, explicit, no cross-account complexity

## Step-by-Step Process

### Step 1: Regional Operator - Apply Terraform

```bash
cd terraform/config/regional-cluster
terraform apply

# Verify infrastructure created
terraform output maestro_configuration_summary
```

### Step 2: Regional Operator - Extract Certificate Data

```bash
# Get certificate for specific management cluster
terraform output -json maestro_agent_certificates | jq '.["management-01"]'
```

**Example output:**
```json
{
  "certificate": "-----BEGIN CERTIFICATE-----\nMIIDWTC...truncated...\n-----END CERTIFICATE-----\n",
  "privateKey": "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIB...truncated...\n-----END RSA PRIVATE KEY-----\n",
  "caCert": "-----BEGIN CERTIFICATE-----\nMIIDQTC...AmazonRootCA1...\n-----END CERTIFICATE-----\n",
  "endpoint": "a1b2c3d4e5f6g7-ats.iot.us-east-1.amazonaws.com",
  "port": "8883",
  "clientId": "management-01-maestro-agent",
  "consumerName": "management-01"
}
```

### Step 3: Regional Operator - Save Certificate to File

```bash
# Save to a secure file (this file should NOT be committed to Git)
terraform output -json maestro_agent_certificates | jq '.["management-01"]' > management-01-maestro-cert.json

# Verify the file
cat management-01-maestro-cert.json
```

### Step 4: Regional Operator - Securely Transfer to Management Operator

**Options for secure transfer:**

**Option A: AWS Secrets Manager (Recommended)**
```bash
# Upload to temporary secret in MANAGEMENT account
# (Regional operator needs temporary write access to MC account)
aws secretsmanager create-secret \
  --profile management-cluster \
  --name "temp/maestro-agent-cert-transfer" \
  --secret-string file://management-01-maestro-cert.json \
  --tags Key=Purpose,Value=TempTransfer Key=DeleteAfter,Value=$(date -d "+7 days" +%Y-%m-%d)

# Tell management operator the secret name
echo "Certificate uploaded to: temp/maestro-agent-cert-transfer"
echo "Please retrieve it and delete the secret after"
```

**Option B: Encrypted File Transfer**
```bash
# Encrypt with management operator's GPG public key
gpg --encrypt --recipient management-operator@example.com management-01-maestro-cert.json

# Send encrypted file via secure channel (email, S3, etc.)
# Management operator decrypts with their private key
```

**Option C: Secure Communication Platform**
- Use 1Password/Vault for secret sharing
- Use secure enterprise messaging (Slack encrypted DM, MS Teams private chat)
- **Never use plain email or unencrypted chat**

### Step 5: Management Operator - Receive Certificate Data

**If using Secrets Manager:**
```bash
# Retrieve from temporary secret
aws secretsmanager get-secret-value \
  --secret-id "temp/maestro-agent-cert-transfer" \
  --query SecretString \
  --output text > maestro-agent-cert.json

# Delete the temporary secret
aws secretsmanager delete-secret \
  --secret-id "temp/maestro-agent-cert-transfer" \
  --force-delete-without-recovery
```

**If using encrypted file:**
```bash
# Decrypt received file
gpg --decrypt management-01-maestro-cert.json.gpg > maestro-agent-cert.json
```

### Step 6: Management Operator - Create Secret with AWS CLI

**Use AWS CLI to create the secret directly (NO Terraform):**

```bash
# Create secret in management account Secrets Manager
aws secretsmanager create-secret \
  --name "management-01/maestro/agent-mqtt-cert" \
  --description "MQTT certificate for Maestro Agent" \
  --secret-string file://maestro-agent-cert.json

# Verify secret was created
aws secretsmanager describe-secret \
  --secret-id "management-01/maestro/agent-mqtt-cert"

# Delete the local certificate file securely
shred -u maestro-agent-cert.json
```

**Why AWS CLI instead of Terraform?**
- ✅ **No sensitive data in Terraform state**
- ✅ **No sensitive Terraform variables needed**
- ✅ **Simpler** - Terraform only manages IAM roles
- ✅ **More secure** - Certificate stays out of version control and state files

**Create minimal terraform.tfvars:**

```bash
cd terraform/config/management-cluster

cat > terraform.tfvars <<EOF
# Regional AWS account ID (where IoT Core is hosted)
regional_aws_account_id = "123456789012"

# Management cluster EKS name
eks_cluster_name = "management-01"

# Secret name (already created via AWS CLI above)
maestro_agent_mqtt_cert_secret_name = "management-01/maestro/agent-mqtt-cert"
EOF
```

### Step 7: Management Operator - Apply Terraform

**Terraform only manages IAM roles and Pod Identity (NOT the secret):**

```bash
# Copy example file
cp maestro-agent.tf.example maestro-agent.tf

# Review the configuration
terraform init
terraform plan

# Apply to create IAM role and Pod Identity
terraform apply
```

**Expected resources created:**
- `data.aws_secretsmanager_secret.maestro_agent_mqtt_cert` - **Reference** to existing secret
- `aws_iam_role.maestro_agent` - IAM role for agent
- `aws_iam_role_policy.maestro_agent_secrets` - Secrets Manager read policy
- `aws_iam_role_policy.maestro_agent_iot` - IoT Core access policy
- `aws_eks_pod_identity_association.maestro_agent` - Pod Identity binding

**Note:** Terraform does NOT create the secret - it only references the secret you created with AWS CLI.

### Step 8: Management Operator - Verify Secret Created

```bash
# Verify secret exists
aws secretsmanager describe-secret \
  --secret-id management-01/maestro/agent-mqtt-cert

# Verify secret content (optional)
aws secretsmanager get-secret-value \
  --secret-id management-01/maestro/agent-mqtt-cert \
  --query SecretString \
  --output text | jq .
```

### Step 9: Management Operator - Deploy Maestro Agent

```bash
# Get Terraform outputs for Helm values
terraform output maestro_agent_configuration_summary

# Deploy Maestro Agent with Helm
helm upgrade --install maestro-agent ./charts/maestro-agent \
  -n maestro --create-namespace \
  -f charts/maestro-agent/values.yaml \
  -f charts/maestro-agent/values-override.yaml
```

### Step 10: Verify End-to-End

**On Regional Cluster:**
```bash
# Create a test ManifestWork
kubectl apply -f - <<EOF
apiVersion: work.open-cluster-management.io/v1
kind: ManifestWork
metadata:
  name: test-from-regional
  namespace: maestro
  labels:
    cluster: management-01
spec:
  workload:
    manifests:
      - apiVersion: v1
        kind: ConfigMap
        metadata:
          name: hello-from-regional
          namespace: default
        data:
          message: "Hello from Regional Cluster!"
EOF

# Watch for status update
kubectl get manifestwork -n maestro test-from-regional -w
```

**On Management Cluster:**
```bash
# Verify ConfigMap was created
kubectl get configmap hello-from-regional -n default

# Check Maestro Agent logs
kubectl logs -n maestro -l app=maestro-agent --tail=50
```

## Security Best Practices

### 1. Certificate Storage
- ✅ **Store ONLY in AWS Secrets Manager** (created via AWS CLI)
- ✅ **Keep certificate data OUT of Terraform** (no variables, no state)
- ✅ **Delete local certificate files immediately** after upload (`shred -u`)
- ❌ Never commit certificates to Git
- ❌ Never put certificates in Terraform variables or state

### 2. Transfer Security
- ✅ Use encrypted channels (GPG, Secrets Manager, Vault)
- ✅ Verify recipient before transferring
- ✅ Delete temporary transfer artifacts
- ❌ Never use plain email or chat
- ❌ Never use public file sharing

### 3. Access Control
- ✅ Limit who can run `terraform output` on regional cluster
- ✅ Limit who can create secrets in management account
- ✅ Use temporary credentials with expiration
- ✅ Audit all certificate transfers

### 4. Cleanup
```bash
# Regional operator: Delete local certificate file
shred -u management-01-maestro-cert.json

# Management operator: Certificate file already deleted in Step 6
# Just clear shell history
history -c

# Verify no certificate data in Terraform state
cd terraform/config/management-cluster
terraform show | grep -i certificate
# Should only show secret NAME, not certificate data
```

## Certificate Rotation

When rotating certificates (e.g., annual renewal):

1. **Regional Operator**: Run `terraform apply` to create new certificate
2. **Extract new certificate** using same process as initial setup
3. **Transfer to management operator**
4. **Management Operator**: Update secret with AWS CLI:
   ```bash
   aws secretsmanager update-secret \
     --secret-id "management-01/maestro/agent-mqtt-cert" \
     --secret-string file://new-cert.json
   ```
5. **ASCP automatically detects secret change** and remounts within ~30 seconds
6. **Maestro Agent automatically reconnects** with new certificate

**No Terraform apply needed! No pod restart required!**

## Troubleshooting

### Regional Operator: Certificate not in outputs

**Problem:**
```bash
terraform output maestro_agent_certificates
# Error: Output not found
```

**Solution:**
```bash
# Ensure management_cluster_ids is set
grep management_cluster_ids terraform.tfvars

# Re-apply to create IoT certificates
terraform apply -target=module.maestro_infrastructure.aws_iot_certificate.maestro_agent
```

### Management Operator: Secret not found during Terraform plan

**Problem:**
```
Error: reading Secrets Manager Secret: ResourceNotFoundException
```

**Solution:**
```bash
# Create the secret FIRST with AWS CLI before running Terraform
aws secretsmanager create-secret \
  --name "management-01/maestro/agent-mqtt-cert" \
  --secret-string file://cert.json

# Then run Terraform
terraform plan
```

### Agent Pod: Cannot mount secret

**Problem:**
```
Failed to mount secret: secret not found
```

**Solution:**
```bash
# Verify secret exists
aws secretsmanager describe-secret --secret-id management-01/maestro/agent-mqtt-cert

# Verify IAM role has permissions
aws iam get-role-policy --role-name management-01-maestro-agent --policy-name management-01-maestro-agent-secrets

# Verify Pod Identity association
aws eks list-pod-identity-associations --cluster-name management-01
```

### Agent: Cannot connect to IoT Core

**Problem:**
```
Failed to connect to MQTT broker: connection refused
```

**Solution:**
```bash
# Verify IoT endpoint is correct
aws secretsmanager get-secret-value \
  --secret-id management-01/maestro/agent-mqtt-cert \
  --query SecretString --output text | jq -r '.endpoint'

# Verify certificate is valid
aws iot describe-certificate --certificate-id <cert-id>

# Check IoT policy attached
aws iot list-principal-policies --principal <certificate-arn>
```

## Quick Reference

**Regional Operator Commands:**
```bash
# Extract certificate for management-01
terraform output -json maestro_agent_certificates | jq '.["management-01"]' > cert.json

# Upload to temp secret in MC account
aws secretsmanager create-secret --profile mc --name temp/cert --secret-string file://cert.json

# Clean up
shred -u cert.json
```

**Management Operator Commands:**
```bash
# Download from temp secret
aws secretsmanager get-secret-value --secret-id temp/cert --query SecretString --output text > cert.json

# Create secret with AWS CLI (NOT Terraform!)
aws secretsmanager create-secret \
  --name "management-01/maestro/agent-mqtt-cert" \
  --secret-string file://cert.json

# Delete local cert file
shred -u cert.json

# Create minimal terraform.tfvars
cat > terraform.tfvars <<EOF
regional_aws_account_id = "123456789012"
eks_cluster_name = "management-01"
maestro_agent_mqtt_cert_secret_name = "management-01/maestro/agent-mqtt-cert"
EOF

# Apply Terraform (only IAM roles, no secret data)
terraform apply

# Deploy Agent
helm upgrade --install maestro-agent ./charts/maestro-agent \
  -f charts/maestro-agent/values.yaml \
  -f charts/maestro-agent/values-override.yaml
```
