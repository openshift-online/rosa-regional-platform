---
theme: default
title: ROSA Regional Platform - Full Region Provisioning
info: |
  ## Milestone 1 Deliverable
  Provisioning a complete region with Regional and Management clusters
class: text-center
highlighter: shiki
drawings:
  persist: false
transition: slide-left
mdc: true
---

# ROSA Regional Platform

✅ [ROSA-666 - Milestone 1 - Deploy a Regional Cluster + Management Cluster](https://issues.redhat.com/browse/ROSA-666) (part of [ROSA-659](https://issues.redhat.com/browse/ROSA-659)).

_A platform engineer can deploy a new region manually, composed of an EKS Regional Cluster (RC) and EKS Management Cluster (MC). They can submit a resource via the Frontend API, and see it applied in the MC via Maestro, and receive status feedback._

---
layout: default
---

# What We've Built

<img src="./diagrams/01-architecture-overview.png" alt="Architecture overview diagram showing the three-layer regional design with Regional Cluster, Management Clusters, and Customer Hosted Clusters" class="h-100 mx-auto" />

---

# Complete Guide: Provision a New Region

<div></div>

[docs / full-region-provisioning.md](https://github.com/openshift-online/rosa-regional-platform/blob/main/docs/full-region-provisioning.md)

<img src="./images/full-region-provisioning.png" alt="Full region provisioning diagram showing the end-to-end steps and components for deploying a new region" class="h-100 mx-auto" />


---

# Declare a New Region

<div></div>

Define your region in Git, render the ArgoCD manifests, commit.

<div class="grid grid-cols-2 gap-4">
<div>

### 1. Edit [argocd/config.yaml](https://github.com/openshift-online/rosa-regional-platform/blob/main/argocd/config.yaml)

```yaml
shards:
  - region: "us-west-2"
    environment: "integration"
    values:
      management-cluster:
        hypershift:
          oidcStorageS3Bucket:
            name: "hypershift-mc-us-west-2"
            region: "us-west-2"
```

</div>
<div>

### 2. Render & Commit

```bash
# Generate all the argocd/rendered
# manifests for the new region based
# on the config.yaml values /argocd/scripts/render.py

git add argocd/config.yaml argocd/rendered/
git commit -m "Add us-west-2 region"
git push
```

</div>
</div>

---

# Regional Cluster Provisioning

<div></div>

Provision the Regional Cluster infrastructure with Terraform.

<div class="grid grid-cols-2 gap-4">
<div>

### Commands

```bash
# Configure terraform variables
cp terraform/.../terraform.tfvars.example \
   terraform/.../terraform.tfvars

# Provision Regional Cluster
make provision-regional
```
This runs a terraform that provisions all the Regional Cluster infrastructure.

</div>
<div>

### What Gets Created

![Regional Infrastructure](./diagrams/02-regional-infra.png)

</div>
</div>

---

# ArgoCD Bootstrap & Workloads

<div></div>

As part of `make provision-regional`, an **ECS Fargate task** runs to **install ArgoCD**, then GitOps takes over. **ArgoCD** automatically **deploys all Regional Cluster workloads** from Git.

<img src="./diagrams/03-argocd-bootstrap.png" alt="ArgoCD bootstrap diagram showing ECS Fargate installing ArgoCD and GitOps deploying Regional Cluster workloads" class="h-80 mx-auto" />


---

# Maestro IoT Setup

<div></div>

All the clusters (Regional and Management Cluster) communicate using Maestro over MQTT. This requires:

```bash
# In the Regional Account - Provision IoT resources
make provision-maestro-agent-iot-regional
```

This creates:

- Certificate + Private Key (download files)
- Set up IoT Policy for that certificate

<br/>

```bash
# Then, in the Management Account
make provision-maestro-agent-iot-management
```

This uploads the certificate to AWS Secrets Manager and will be referenced by the Maestro Agent deployment.

---

# Management Cluster Provisioning

<div></div>

Provision the MC and configure Maestro Agent with IoT credentials.

<div class="grid grid-cols-2 gap-4">
<div>

### Commands

```bash
# Provision Management Cluster
make provision-management
```

This runs a terraform that provisions the Management Cluster.

</div>
<div>

### What Gets Created

- Private EKS Cluster
- ArgoCD (self-managing)
- HyperShift Operator (deployed by ArgoCD)
- Maestro Agent (deployed by ArgoCD) configured with IoT credentials

</div>
</div>

---

# Consumer Registration

<div></div>

Register the MC with the Regional Cluster's Maestro Server.

<div class="grid grid-cols-2 gap-4">
<div>


```bash
awscurl -X POST \
  https://$API_GATEWAY_URL/prod/api/v0/management_clusters \
  --service execute-api \
  --region us-west-2 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "management-01",
    "labels": {
      "cluster_type": "management",
      "cluster_id": "management-01"
    }
  }'
```

The `API_GATEWAY_URL` can be found in the Regional Cluster terraform output.

</div>
<div>

### What This Does

Registers MC as a consumer in Maestro.

</div>
</div>

---

# End-to-End Verification

<div></div>

Apply a workload through the API and verify it reaches the MC.

<div class="grid grid-cols-2 gap-4">
<div>

### Apply Workload

```bash
# Post a ManifestWork
awscurl -X POST \
  https://$API_GATEWAY_URL/prod/api/v0/work \
  --service execute-api \
  --region us-west-2 \
  -d @payload.json

# Check status
awscurl \
  https://$API_GATEWAY_URL/prod/api/v0/resource_bundles \
  --service execute-api \
  --region us-west-2 | jq '.items[].status'
```

The `payload.json` is a ManifestWork resource documented in the [End-to-End Verification guide](https://github.com/openshift-online/rosa-regional-platform/blob/main/docs/full-region-provisioning.md#7-end-to-end-verification).

</div>
<div>

### Expected Result

```json
{
  "resourceStatus": {
    "conditions": [{
      "type": "Applied",
      "status": "True"
    }]
  }
}
```

✅ Workload successfully distributed via Maestro

</div>
</div>

---

# Request Flow

<div></div>

<img src="./images/request-flow.png" alt="Request flow diagram showing a client request through API Gateway to the Regional Cluster and Maestro distribution to the Management Cluster" class="h-100 mx-auto" />

---
layout: center
class: text-center
---

# Milestone 1 Complete ✅

Regional Cluster and Management Cluster provisioned on EKS.

What's next?

[ROSA-667 -  Milestone 2 - Continuous Validation](https://issues.redhat.com/browse/ROSA-667)

[ROSA-668 -  Milestone 3 - HCPs run on EKS MCs](https://issues.redhat.com/browse/ROSA-668)
