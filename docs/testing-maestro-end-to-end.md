# Testing Maestro End-to-End

This guide demonstrates how to test the complete Maestro flow from creating a ManifestWork on the regional cluster to seeing it applied on a management cluster.

## Architecture Flow

```
Regional Cluster                    AWS IoT Core                Management Cluster
┌─────────────────┐                ┌──────────┐                ┌──────────────────┐
│ Maestro Server  │───publish────▶ │   MQTT   │───subscribe──▶ │ Maestro Agent    │
│                 │                │  Broker  │                │                  │
│ - HTTP API      │                │          │                │ - Applies        │
│ - gRPC API      │◀───status──────│          │◀───status──────│   ManifestWorks  │
└─────────────────┘                └──────────┘                └──────────────────┘
         ▲                                                               │
         │                                                               │
    gRPC Client                                                    Kubernetes
    (you)                                                          Resources
```

## Prerequisites

1. **Regional cluster** with Maestro Server running
2. **Management cluster** with Maestro Agent running
3. **Both port-forwards** to regional cluster Maestro Server:
   - HTTP API on port 8080
   - gRPC API on port 8090
4. **Maestro repository** cloned locally
5. **Go installed** (for running the client tool)

## Step 1: Set Up Port-Forwards

You need **two port-forwards** running simultaneously to the regional cluster.

**Terminal 1 - HTTP API:**
```bash
# Switch to regional cluster
export AWS_PROFILE=rc

# Port-forward HTTP API
kubectl port-forward -n maestro svc/maestro-http 8080:8080
```

**Terminal 2 - gRPC API:**
```bash
# Switch to regional cluster
export AWS_PROFILE=rc

# Port-forward gRPC API
kubectl port-forward -n maestro svc/maestro-grpc 8090:8090
```

Keep both terminals running throughout the test.

## Step 2: Clone Maestro Repository

```bash
cd /tmp
git clone https://github.com/openshift-online/maestro.git
cd maestro
```

## Step 3: Create a Test ManifestWork

Create a simple ConfigMap ManifestWork to test the flow:

```bash
cat > test-configmap.json <<'EOF'
{
  "apiVersion": "work.open-cluster-management.io/v1",
  "kind": "ManifestWork",
  "metadata": {
    "name": "test-configmap"
  },
  "spec": {
    "workload": {
      "manifests": [
        {
          "apiVersion": "v1",
          "kind": "ConfigMap",
          "metadata": {
            "name": "hello-from-maestro",
            "namespace": "default"
          },
          "data": {
            "message": "Hello from Maestro Server!",
            "cluster_id": "management-01",
            "test_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          }
        }
      ]
    }
  }
}
EOF
```

## Step 4: Apply the ManifestWork

Use the Maestro client tool to create the ManifestWork via gRPC:

```bash
go run examples/manifestwork/client.go apply test-configmap.json \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

**Expected output:**
```
Apply manifestwork (opid=xxxx-xxxx-xxxx):
manifestwork.work.open-cluster-management.io/test-configmap applied
```

## Step 5: Verify on Regional Cluster (Server Side)

**Check Maestro Server logs:**
```bash
kubectl logs -n maestro -l app=maestro-server --tail=50
```

Look for messages about publishing the resource to MQTT.

**List ManifestWorks:**
```bash
go run examples/manifestwork/client.go list \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

## Step 6: Verify on Management Cluster (Agent Side)

**Switch to management cluster:**
```bash
export AWS_PROFILE=mc
```

**Check Maestro Agent logs:**
```bash
kubectl logs -n maestro -l app=maestro-agent --tail=100 --follow
```

Look for messages like:
- `"Received cloudevents message"`
- `"Applying manifest"`
- `"Resource applied successfully"`

**Verify the ConfigMap was created:**
```bash
kubectl get configmap hello-from-maestro -n default
kubectl get configmap hello-from-maestro -n default -o yaml
```

**Expected output:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-from-maestro
  namespace: default
data:
  message: Hello from Maestro Server!
  cluster_id: management-01
  test_timestamp: "2026-01-21T21:45:00Z"
```

**Check the AppliedManifestWork status:**
```bash
kubectl get appliedmanifestwork
kubectl get appliedmanifestwork test-configmap -o yaml
```

The status should show the ConfigMap was applied successfully and report back to the server.

## Step 7: Verify Status Feedback

**Back on regional cluster:**
```bash
export AWS_PROFILE=rc

# Get the ManifestWork with status
go run examples/manifestwork/client.go get test-configmap \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

The output should show the status conditions indicating the work was applied successfully.

## Step 8: Clean Up

**Delete the ManifestWork:**
```bash
go run examples/manifestwork/client.go delete test-configmap \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

**Verify deletion on management cluster:**
```bash
export AWS_PROFILE=mc
kubectl get configmap hello-from-maestro -n default
# Should return: Error from server (NotFound): configmaps "hello-from-maestro" not found
```

## Troubleshooting

### Port-forward connection refused
**Problem:** `dial tcp 127.0.0.1:8080: connect: connection refused`

**Solution:** Ensure both port-forwards are running:
```bash
# Check if port-forwards are active
ps aux | grep "kubectl port-forward"

# Restart them if needed (in separate terminals)
kubectl port-forward -n maestro svc/maestro-http 8080:8080
kubectl port-forward -n maestro svc/maestro-grpc 8090:8090
```

### Consumer not found
**Problem:** `consumer "management-01" not found`

**Solution:** Create the consumer first:
```bash
curl -X POST http://localhost:8080/api/maestro/v1/consumers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "management-01",
    "labels": {
      "cluster_type": "management",
      "cluster_id": "management-01"
    }
  }'
```

### Agent not receiving messages
**Problem:** ConfigMap doesn't appear on management cluster

**Solution:** Check agent logs for errors:
```bash
export AWS_PROFILE=mc
kubectl logs -n maestro -l app=maestro-agent --tail=100
```

Common issues:
- **MQTT disconnected**: Check AWS IoT Core connectivity and certificate
- **Permission denied**: Ensure agent has cluster-admin ClusterRoleBinding
- **Topic mismatch**: Verify agent is subscribed to correct topic

### Resources not applying
**Problem:** Agent receives messages but resources don't get created

**Solution:** Check AppliedManifestWork status:
```bash
kubectl get appliedmanifestwork test-configmap -o yaml
```

Look at the `conditions` section for specific errors. Common issues:
- Missing RBAC permissions (agent needs cluster-admin)
- Invalid manifest format
- Resource conflicts (resource already exists)

## Advanced Testing

### Test with a Deployment

Create a more complex ManifestWork with a Deployment:

```bash
cat > test-deployment.json <<'EOF'
{
  "apiVersion": "work.open-cluster-management.io/v1",
  "kind": "ManifestWork",
  "metadata": {
    "name": "nginx-deployment"
  },
  "spec": {
    "workload": {
      "manifests": [
        {
          "apiVersion": "apps/v1",
          "kind": "Deployment",
          "metadata": {
            "name": "nginx-from-maestro",
            "namespace": "default"
          },
          "spec": {
            "replicas": 2,
            "selector": {
              "matchLabels": {
                "app": "nginx-maestro"
              }
            },
            "template": {
              "metadata": {
                "labels": {
                  "app": "nginx-maestro"
                }
              },
              "spec": {
                "containers": [
                  {
                    "name": "nginx",
                    "image": "nginx:latest",
                    "ports": [
                      {
                        "containerPort": 80
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
}
EOF

go run examples/manifestwork/client.go apply test-deployment.json \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify
```

Verify on management cluster:
```bash
export AWS_PROFILE=mc
kubectl get deployment nginx-from-maestro -n default
kubectl get pods -l app=nginx-maestro -n default
```

### Watch for Changes

Monitor ManifestWorks in real-time:

```bash
go run examples/manifestwork/client.go watch \
  --consumer-name=management-01 \
  --maestro-server=http://localhost:8080 \
  --grpc-server=localhost:8090 \
  --insecure-skip-verify \
  --print-work-details
```

## Success Criteria

Your Maestro setup is working correctly when:

1. ✅ ManifestWork created via gRPC client on regional cluster
2. ✅ Maestro Server publishes to AWS IoT Core MQTT broker
3. ✅ Maestro Agent receives message on management cluster
4. ✅ Agent applies Kubernetes resource to management cluster
5. ✅ AppliedManifestWork status created on management cluster
6. ✅ Status reported back to regional cluster via MQTT
7. ✅ ManifestWork status updated on regional cluster

**Congratulations!** 🎉 You have a fully functional cross-account, cross-cluster Maestro deployment using AWS IoT Core as the message broker!

## Next Steps

- Deploy multiple management clusters and test distribution to each
- Test update scenarios (modify a ManifestWork and see it propagate)
- Test deletion propagation
- Monitor MQTT message throughput in AWS IoT Core
- Set up CloudWatch metrics for Maestro components
