# Complete Guide: Provision a New Region

This comprehensive guide walks through all steps to provision a new region in the ROSA Regional Platform. Follow these steps in order to set up both Regional and Management Clusters with full ArgoCD configuration and Maestro connectivity.

---

## 1. Pre-Flight Checklist

Before starting, ensure your environment is properly configured.

### Required Tools
Verify all tools are installed and accessible:

```bash
# Check tool versions
aws --version
terraform --version
python --version  # or python3 --version
```

### Required AWS accounts

To provision a regional and management cluster, you require two AWS accounts. Ensure you have access to both via environment variables or ideally AWS profiles. 

## 2. ArgoCD Configuration Shard Creation (optional)

<details>
<summary>🔧 Configure New Region Shard (skip if reusing existing environment/region configuration pair)</summary>

**Note:** In case you are deploying clusters based on existing argocd configuration, you can skip this step.
Example: you want to spin up a development cluster and re-use the existing configuration for `env = integration` and `region = us-east-1`.

### Add Region to Configuration

Edit `argocd/config.yaml` and add your new region following this pattern:

```yaml
shards:
  # ... existing entries ...
  - region: "us-west-2"              # ← Your target region
    environment: "integration"       # ← Your environment (integration/staging/etc)
    values:
      management-cluster:
        hypershift:
          oidcStorageS3Bucket:
            name: "hypershift-mc-us-west-2"    # ← Region-specific bucket name
            region: "us-west-2"                # ← Your target region
          externalDns:
            domain: "dev.us-west-2.rosa.example.com"  # ← Region-specific domain
```

### Generate Rendered Configurations

Run the rendering script to generate the required files:

```bash
./argocd/scripts/render.py
```

**Verify rendered files were created:**

```bash
ls -la argocd/rendered/integration/us-west-2/  # Replace with your environment/region
```

You should see directories like `management-cluster-manifests/` and files like `management-cluster-values.yaml`.

### Commit and Push Changes

```bash
git add argocd/config.yaml argocd/rendered/
git commit -m "Add us-west-2 region configuration

- Add us-west-2/integration to argocd/config.yaml
- Generate rendered ArgoCD manifests and values
- Prepare for regional cluster provisioning"
git push origin <your-branch>
```

</details>

---

## 3. Regional Cluster Provisioning

Switch to your **regional account** AWS profile and provision the Regional Cluster.

### Configure Regional Cluster Parameters

In `terraform/config/regional-cluster/terraform.tfvars`, configure:

```bash
# One-time setup: Copy and edit configurations
cp terraform/config/regional-cluster/terraform.tfvars.example \
   terraform/config/regional-cluster/terraform.tfvars
```

### Execute Regional Cluster Provisioning

```bash
# Authenticate with regional account (choose your preferred method)
export AWS_PROFILE=<regional-profile>
# OR: aws configure set profile <regional-profile>
# OR: use your SSO/assume role method

# Provision Regional Environment
make provision-regional
```

<details>
<summary>🔍 Verify Regional Cluster Deployment (optional)</summary>

```bash
# Check ArgoCD applications are synced
./scripts/dev/bastion-connect.sh regional
kubectl get applications -n argocd
```

Expected: ArgoCD applications "Synced" and "Healthy".

</details>

---

## 4. Maestro Connectivity Setup

Maestro uses AWS IoT Core for secure MQTT communication between Regional and Management Clusters. This requires a two-account certificate exchange process.

### Step 4a: Regional Account IoT Setup

**Ensure you're authenticated with the regional account:**

```bash
# Choose your preferred authentication method
export AWS_PROFILE=<regional-profile>
# OR: use --profile flag, SSO, assume role, etc.
```

**Provision IoT resources in regional account:**

```bash
MGMT_TFVARS=terraform/config/management-cluster/terraform.tfvars make provision-maestro-agent-iot-regional
```

### Step 4b: Management Account Secret Setup

**Switch to management account authentication:**

```bash
# Choose your preferred authentication method
export AWS_PROFILE=<management-profile>
# OR: use --profile flag, SSO, assume role, etc.
```

**Create IoT secret in management account:**

```bash
MGMT_TFVARS=terraform/config/management-cluster/terraform.tfvars make provision-maestro-agent-iot-management
```

**What this creates:**
- Kubernetes secret containing IoT certificate and endpoint
- Configuration for Maestro agent to connect to regional IoT endpoint

<details>
<summary>🔍 Verify IoT Resources (optional)</summary>

```bash
# In regional account - verify IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS

# Check certificate is active
aws iot list-certificates
```

Expected: IoT endpoint URL should be returned and certificate should show "ACTIVE" status.

</details>

---

## 5. Management Cluster Provisioning

Switch to your **management account** AWS profile and provision the Management Cluster.

### Configure Management Cluster Parameters

In `terraform/config/management-cluster/terraform.tfvars`, configure:

```bash
# One-time setup: Copy and edit configurations
cp terraform/config/management-cluster/terraform.tfvars.example \
   terraform/config/management-cluster/terraform.tfvars
```

### Execute Management Cluster Provisioning

```bash
# Authenticate with management account (choose your preferred method)
export AWS_PROFILE=<management-profile>
# OR: aws configure set profile <management-profile>
# OR: use your SSO/assume role method

# Provision Management Environment
make provision-management
```
<details>
<summary>🔍 Verify Management Cluster Deployment (optional)</summary>

```bash
# Check cluster is provisioned
./scripts/dev/bastion-connect.sh management

# Verify ArgoCD applications
kubectl get applications -n argocd
```

Expected: ArgoCD applications "Synced" and "Healthy".

</details>

---

## 6. Consumer Registration & Verification

Register the Management Cluster as a consumer with the Regional Cluster's Maestro server.

### Connect to Regional Cluster

```bash
./scripts/dev/bastion-connect.sh regional
```

### Register Management Cluster

```bash
# Set MC cluster name (use your actual management cluster ID)
MC_CLUSTER_NAME="management-01"

# Create consumer registration
kubectl port-forward -n maestro-server svc/maestro-http 8080:8080 --address 0.0.0.0 & \
PF_PID=$!; \
sleep 5; \
curl -X POST http://localhost:8080/api/maestro/v1/consumers \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${MC_CLUSTER_NAME}\",
    \"labels\": {
      \"cluster_type\": \"${MC_CLUSTER_NAME}\",
      \"cluster_id\": \"${MC_CLUSTER_NAME}\"
    }
  }"; \
kill $PF_PID
```


---

## 7. End-to-End Verification

This section provides comprehensive validation that both Regional and Management clusters are running and can communicate properly via Maestro.

<details>
<summary>🔍 Consumer Registration Verification</summary>

```bash
# Verify the Management Cluster is properly registered
./scripts/dev/bastion-connect.sh regional

kubectl port-forward -n maestro-server svc/maestro-http 8080:8080 --address 0.0.0.0 & \
PF_PID=$!; \
sleep 5; \
echo "Registered consumers:"; \
curl -s http://localhost:8080/api/maestro/v1/consumers | jq -r '.items[] | "- \(.name) (labels: \(.labels))"'; \
kill $PF_PID
```

**Expected Results:**
- Your Management Cluster name appears in the consumer list
- Consumer has appropriate labels (cluster_type, cluster_id)
- No connection errors when accessing Maestro API

</details>

<details>
<summary>🔍 Complete Maestro Payload Distribution Test</summary>

This comprehensive test validates end-to-end Maestro payload distribution from Regional to Management Cluster via AWS IoT Core MQTT using the proper gRPC client interface:

**Step 1: Setup Test Environment in Bastion**

```bash
# Connect to Regional Cluster bastion
./scripts/dev/bastion-connect.sh regional

# Install Go in the bastion to run the maestro-cli
echo "Installing Go in bastion..."
curl -L https://go.dev/dl/go1.21.6.linux-amd64.tar.gz | tar -xzf - -C /tmp
export PATH=/tmp/go/bin:$PATH
export GOPATH=/tmp/gopath
export GOCACHE=/tmp/gocache

# Clone Maestro repository in bastion
git clone https://github.com/openshift-online/maestro.git /tmp/maestro
cd /tmp/maestro

# Replace with your actual MC cluster name
MC_CLUSTER_NAME="management-01"

# Set up port forwarding for gRPC and HTTP
kubectl port-forward -n maestro-server svc/maestro-grpc 8090:8090 --address 0.0.0.0 &
kubectl port-forward -n maestro-server svc/maestro-http 8080:8080 --address 0.0.0.0 &
sleep 5

echo "Go installed and port forwarding established in bastion"
```

**Step 2: Create Test ManifestWork File**

```bash
# Create a test ManifestWork JSON file
TIMESTAMP=$(date +%s)
cat > /tmp/maestro-test-manifestwork.json << EOF
{
  "apiVersion": "work.open-cluster-management.io/v1",
  "kind": "ManifestWork",
  "metadata": {
    "name": "maestro-payload-test-${TIMESTAMP}"
  },
  "spec": {
    "workload": {
      "manifests": [
        {
          "apiVersion": "v1",
          "kind": "ConfigMap",
          "metadata": {
            "name": "maestro-payload-test",
            "namespace": "default",
            "labels": {
              "test": "maestro-distribution",
              "timestamp": "${TIMESTAMP}"
            }
          },
          "data": {
            "message": "Hello from Regional Cluster via Maestro MQTT",
            "cluster_source": "regional-cluster",
            "cluster_destination": "${MC_CLUSTER_NAME}",
            "transport": "aws-iot-core-mqtt",
            "test_id": "${TIMESTAMP}",
            "payload_size": "This tests MQTT payload distribution through AWS IoT Core"
          }
        }
      ]
    },
    "deleteOption": {
      "propagationPolicy": "Foreground"
    },
    "manifestConfigs": [
      {
        "resourceIdentifier": {
          "group": "",
          "resource": "configmaps",
          "namespace": "default",
          "name": "maestro-payload-test"
        },
        "feedbackRules": [
          {
            "type": "JSONPaths",
            "jsonPaths": [
              {
                "name": "status",
                "path": ".metadata"
              }
            ]
          }
        ],
        "updateStrategy": {
          "type": "ServerSideApply"
        }
      }
    ]
  }
}
EOF

echo "Created ManifestWork file: maestro-payload-test-${TIMESTAMP}"
```

**Step 3: Apply ManifestWork via Maestro Client (in bastion)**

```bash
# Still in Regional Cluster bastion - apply the ManifestWork using Maestro client
echo "Applying ManifestWork via Maestro gRPC client from bastion..."
cd /tmp/maestro

go run examples/manifestwork/client.go apply /tmp/maestro-test-manifestwork.json \
  --consumer-name=${MC_CLUSTER_NAME} \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

**Step 4: Monitor Distribution Status**

```bash
# List all ManifestWorks for the consumer
echo ""
echo "Listing ManifestWorks for consumer ${MC_CLUSTER_NAME}:"
go run examples/manifestwork/client.go list \
  --consumer-name=${MC_CLUSTER_NAME} \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify

# Get specific ManifestWork details
echo ""
echo "Getting details for maestro-payload-test-${TIMESTAMP}:"
go run examples/manifestwork/client.go get maestro-payload-test-${TIMESTAMP} \
  --consumer-name=${MC_CLUSTER_NAME} \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

**Step 5: Verify Payload on Management Cluster**

```bash
# Switch to Management Cluster
./scripts/dev/bastion-connect.sh management

echo "Verifying ConfigMap was created via Maestro MQTT distribution:"
kubectl get configmap maestro-payload-test -n default -o yaml

echo ""
echo "Checking payload data integrity:"
kubectl get configmap maestro-payload-test -n default -o jsonpath='{.data}' | jq .
```
</details>

