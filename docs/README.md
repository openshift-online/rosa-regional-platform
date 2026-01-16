# ROSA Regional Platform

## Overview

The ROSA Regional Platform project is a strategic initiative to redesign the architecture of Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP). This new architecture moves away from a globally-centralized management model to a regionally-distributed approach, where each AWS region operates independently with its own control plane infrastructure.

The goal is to improve reliability, reduce dependencies on global services, and provide customers with lower-latency access to cluster management through regional API endpoints.

## Project Goals

### Independence and Resilience

- **Regional Autonomy**: Each region operates independently. If one region experiences issues, other regions continue functioning normally.
- **Reduced Global Dependencies**: The architecture minimizes reliance on global services run by Red Hat. Regional operations depend primarily on AWS infrastructure (IAM, RDS, EKS).
- **Simplified Disaster Recovery**: A clear recovery path based on declarative state management and automated backups.

### Operational Simplicity

- **GitOps-Driven Deployment**: Infrastructure and applications are managed through Git repositories using ArgoCD and Terraform pipelines.
- **Automated Provisioning**: New regions can be deployed fully automatically on demand without manual intervention.
- **Zero-Operator Access**: Default operational model with no standing operator access to production clusters, using ephemeral break-glass access for emergencies only.

### Modern Architecture

- **Cloud-Native Patterns**: Leverages AWS services (EKS, RDS, IAM) and modern tooling (ArgoCD, Tekton, MQTT-based orchestration).
- **Declarative Management**: Single source of truth for cluster state through the Cluster Lifecycle Manager (CLM).
- **Progressive Deployment**: Sector-based rollout strategy allows controlled testing and deployment of changes across regions.

## Architecture Overview

The architecture consists of three main layers within each region:

### 1. Regional Cluster (RC)

The Regional Cluster is an EKS-based cluster that runs the core regional control plane services:

- **Frontend API**: Customer-facing API with AWS IAM-based authorization
- **CLM (Cluster Lifecycle Manager)**: Replaces the legacy OCM/CS/AMS stack; provides declarative cluster lifecycle management
- **Maestro**: Distributes cluster configurations to Management Clusters using MQTT messaging
- **ArgoCD**: GitOps deployment for applications and configurations
- **Tekton**: Executes infrastructure provisioning pipelines

The Regional Cluster has a private Kubernetes API and is accessed by customers through a regional API Gateway at `api.<region>.openshift.com`.

### 2. Management Clusters (MC)

Management Clusters are EKS clusters that host customer Hosted Control Planes (HCPs). Key characteristics:

- Multiple Management Clusters can exist per region, dynamically provisioned as needed
- Each MC runs the HyperShift operator and hosts multiple customer control planes
- MCs have private Kubernetes APIs with no network path to the Regional Cluster API
- The Management Cluster Reconciler (MCR) component enables scalable, dynamic MC provisioning

### 3. Customer Hosted Clusters

These are the customer-facing ROSA HCP clusters where customer workloads run. The control plane components run in the Management Cluster while worker nodes run in the customer's AWS account.

## Key Components

### Cluster Lifecycle Manager (CLM)

CLM is the single source of truth for all cluster state and replaces the legacy OCM, Cluster Service (CS), and Account Management Service (AMS) components. It consists of:

- **hyperfleet-api**: Declarative REST API for cluster operations
- **hyperfleet-sentinel**: Orchestration and decision-making engine
- **hyperfleet-adapter**: Event-driven cluster provisioning logic

CLM state is persisted in a dedicated RDS database with cross-region backups for disaster recovery.

### Maestro

Maestro is a publish-subscribe system that distributes cluster configuration from the Regional Cluster to Management Clusters:

- Uses MQTT for reliable message delivery
- Each Management Cluster runs a Maestro agent that subscribes to its topic
- Receives and applies HostedCluster and NodePool resources to the local Kubernetes API
- Can be rebuilt from CLM in case of data loss (CLM remains authoritative)

### Regional API Gateway

The customer-facing API is exposed through AWS infrastructure:

- AWS API Gateway (regional endpoint) at `api.<region>.openshift.com`
- VPC Link v2 for private connectivity to internal services
- Internal Application Load Balancer distributing traffic to Frontend API pods
- Authorization handled through AWS IAM roles and permissions

### Central Control Plane

The Central Control Plane runs the Regional Provisioning Pipelines that deploy new Regional Clusters. The specific technology stack and location are still under consideration, but the function is to trigger and monitor the automated deployment of regions.

## How It Works

### Deploying a New Region

1. Add region configuration to the Git repository
2. Regional Cluster Provisioning pipeline automatically provisions the Regional Cluster
3. ArgoCD is installed on the new Regional Cluster
4. Core services (Frontend API, CLM, Maestro, Tekton) are deployed via ArgoCD
5. The Regional Cluster provisions initial Management Clusters as needed

### Customer Cluster Lifecycle

1. Customer requests a cluster through the regional API endpoint
2. Frontend API authenticates and authorizes the request using AWS IAM
3. CLM creates the declarative cluster specification
4. Maestro publishes the cluster configuration to the appropriate Management Cluster
5. The Management Cluster's Maestro agent applies the HostedCluster resources
6. HyperShift operator provisions the control plane in the Management Cluster
7. Worker nodes are provisioned in the customer's AWS account

### Progressive Deployment

The architecture uses a sector-based deployment model:

- Regions are organized into sectors (e.g., "stage", "sector 1", "sector 2")
- Configuration follows an inheritance model: Global defaults → Sector overrides → Region-specific overrides
- Changes are rolled out progressively across sectors to minimize risk
- Aligns with existing HyperShift change management strategy

## Disaster Recovery

### State Preservation

- **CLM state**: Stored in RDS with automated cross-region backups
- **etcd snapshots**: Continuous backups of Management Cluster etcd to dedicated DR AWS account
- **Maestro cache**: Can be rebuilt from CLM; not critical for recovery

### Recovery Process

- **Management Cluster recovery**: Restore from etcd backups in the DR account
- **Hosted Cluster recovery**: etcd snapshots enable restoration of customer control planes
- **Break-glass access**: Ephemeral boundary containers for emergency access when normal flows are unavailable

## Technology Stack

- **Compute**: Amazon EKS for Regional and Management Clusters
- **Networking**: VPC, Private Subnets, VPC Link v2, API Gateway, Application Load Balancers
- **Storage**: Amazon RDS (CLM state), EBS (persistent volumes)
- **Identity & Access**: AWS IAM (authentication and authorization)
- **Infrastructure as Code**: Terraform
- **Continuous Deployment**: ArgoCD (applications), Tekton (infrastructure pipelines)
- **Orchestration**: Maestro (MQTT-based resource distribution)
- **Source Control**: Git repositories as source of truth

## Scope and Limitations

### Supported Cluster Types

- This architecture is designed exclusively for ROSA HCP (Hosted Control Planes)
- ROSA Classic and OpenShift Dedicated (OSD) clusters are not migrated to this architecture
- All ROSA HCP clusters will eventually migrate to this regional architecture

### Current Status

This is an active development project. Some design decisions are still pending:

- Central Control Plane technology stack and location
- Authorization service implementation details (AWS IAM vs. Kessel)
- Intrusion Detection System (IDS) strategy
- Observability infrastructure (Splunk deployment model)

## Source Documents

This overview was synthesized from the following source materials:

1. **FAQ.md** - Comprehensive architectural questions and answers
2. **terraform/modules/eks-cluster/README.md** - EKS cluster module documentation
3. **.local/ROSA HCP Regionality - Project Plan.pdf** - Project planning documentation
4. **.local/Configuration paths _ Data flows - Sheet1.pdf** - Configuration and data flow diagrams
5. **design-decisions/TEMPLATE.md** - Design decision documentation template

For detailed technical specifications, implementation details, and answers to specific questions, please refer to the FAQ.md file in the repository root.
