### What cluster types does the regional architecture support?

- The regional architecture is designed exclusively for **ROSA HCP** (Hosted Control Planes)
- This architecture does not support ROSA Classic or OSD
- All ROSA HCP clusters will be migrated to this new architecture
- Existing ROSA Classic and OSD clusters remain globally managed and are not migrated to this architecture

### What is the Regional Cluster and what services run on it?

- The Regional Cluster (RC) is a new EKS-based cluster type, one per region
- It runs the core regional services:
  - **Frontend API** (authorization-aware customer-facing API)
  - **CLM** (Cluster Lifecycle Manager - replaces OCM/CS/AMS)
  - **Maestro** (applies resources to Management Clusters via MQTT)
  - **ArgoCD** (GitOps deployment)
  - **Tekton** (pipeline execution for MC provisioning)
- The Kubernetes API is private
- Provisioned by the Regional Provisioning Pipelines

### What is the difference between the Regional Cluster and the Regional-Access Cluster?

In this implementation we will **not** use Regional-Access Clusters. Instead, we will use zero-operator access as the default model, with ephemeral boundary containers for break-glass scenarios

### What is the Management Cluster Reconciler (MCR)?

- MCR is a component within CLM that orchestrates Management Cluster lifecycle
- It enables scalable management of multiple Management Clusters (MCs) per region, as opposed to having a statically defined list of MCs per region.
- This component will be developed by the Hyperfleet team.

### Where is the global control plane located?

- The purpose of the Central Control Plane is to run the Regional Provisioning Pipelines.
- As of this writing, the decision has not been made about the technology stack and  location of the Central Control Plane.

### Where does the AuthZ service run?

- The decision about the AuthZ service is currently pending.
- The current design envisions AuthZ will be provided by AWS IAM, through Roles/Permissions created by the Customer in their own AWS accounts, therefore no separate AuthZ service might be needed.
- Alternatives such as Kessel are being considered, in which case they would run in the Regional Cluster, and there will be no global AuthZ service.

### Is the Central Data Plane in the regional accounts or the global account?

- The Central Data Plane (IAM, identity, global access control) is **global** and is provided by AWS IAM
- This architecture does not depend on Red Hat SSO to operate the clusters
- However Red Hat SSO is needed once (and only once) in order to link Red Hat identities to AWS IAM identities
- After that linkage, all access control is performed via AWS IAM
- Billing will take place through the AWS Marketplace

### How long can a region operate if Global Services go down?

- The service will depend on AWS IAM, and will be impacted if IAM is unavailable
- However, each region is independent and will continue operating even if any other regions are unavailable
- As of this writing, there are no global services run by Red Hat that are critical for regional operation


### Is there a requirement to bring up a consoledot equivalent in another region within a set timeframe?

- The console is web application that will be served via a CDN (CloudFront). The ConsoleDot team is working on removing any dependencies on Red Hat operated clusters (such as crc).
- The console experience will be similar to that of the AWS Management Console, which is globally available, and connects to regional endpoints. There will be no global ROSA API endpoints.

### What is the path to recovery after a disaster?

- **Source of truth**: CLM is the single declarative source of truth for cluster state. Its data is persisted in a dedicated RDS database, with regular cross-region backups.
- **etcd state of MCs**: Critical for hosted cluster data; etcd snapshots will be continuously backed up to a dedicated DR AWS account (per region)
- **Maestro cache**: Can be rebuilt from CLM; Maestro caches state for performance but CLM is authoritative. Loss of Maestro cache does not impact recovery.
- **Recovery path**:
  - Management Cluster recovery: Restore from etcd backups in the DR account
  - Hosted Cluster recovery: etcd snapshots allow restoration of customer control planes
  - CLM state: Persisted in a dedicated RDS database
- **Break-glass access**: On-demand break-glass access for emergency access when normal management flows are unavailable

### What are the key SLOs to maintain during an outage?

This list is not complete, but some key ones are:

- Customer cluster API access (HCP control planes) and CUJs
- CLM for cluster lifecycle operations
- MC Reconciler for dynamic scaling of MCs
- Management Cluster availability (hosting control planes)

### What happens when the Kubernetes API on a Management Cluster goes down?

- Management Clusters are EKS clusters managed. We would open a support case with AWS to restore the API.
- If the Management Cluster is unrecoverable, we will have to provision a new MC, and restore all the HCPs from etcd backups, as well as update the single source of truth (CLM).

### Where does the Maestro client run and how does it handle API unavailability?

An agent runs on each Management Cluster that:

- Subscribes to MQTT topics for that MC
- Receives resource manifests (HostedCluster, NodePool CRs)
- Applies them to the local Kubernetes API

If the MC API is non-responsive, we will have observability alerts to notify SREs to investigate and remediate.

### How are new regions deployed?

- Regions are deployed on demand (gitops) via pipelines **fully automatically**
- Process:
  1. Add region configuration YAML to `terraform/config/region-deploy/regions/`
  2. Central Pipeline triggers on Git push
  3. Central Pipeline mints Regional AWS account via Organizations API
  4. Central Pipeline deploys Regional Cluster (EKS) with core services
  5. Central Pipeline bootstraps Regional Pipeline in the Regional account
  6. Regional Pipeline is ready to provision Management Clusters as capacity is needed

### What is the difference between Central Pipeline and Regional Pipeline?

The architecture uses a **two-tier pipeline system** for security isolation and operational autonomy:

**Central Pipeline** (runs in Management/Central Account):
- **Scope**: Organization-wide, cross-regional
- **Triggers**: Infrastructure-as-Code changes (rare)
- **Responsibilities**:
  - Mint Regional AWS accounts via Organizations API
  - Deploy Regional Clusters (EKS with CLM, Maestro, API)
  - Bootstrap Regional Pipelines
- **Permissions**: High-risk org-wide permissions (CreateAccount, MoveAccount)
- **Location**: Central/Management AWS account
- **Blast Radius**: High (entire organization)

**Regional Pipeline** (runs in each Regional Account):
- **Scope**: Single-region, Management cluster provisioning
- **Triggers**: Capacity scaling, Git changes (frequent)
- **Responsibilities**:
  - Mint Management AWS accounts (same region only)
  - Deploy Management Clusters (EKS with HyperShift)
  - Scale Management cluster capacity independently
- **Permissions**: Region-scoped, more restrictive
- **Location**: Each Regional AWS Account
- **Blast Radius**: Low (single region only)

**Why Separate?**
1. **Blast Radius Isolation**: Regional Pipeline failure only affects one region
2. **Regional Autonomy**: Each region can scale Management clusters independently
3. **Security Separation**: Central Pipeline has dangerous org-wide permissions, Regional Pipeline does not
4. **Operational Flexibility**: Different cadences for Regional vs Management deployments

### How does Management Cluster provisioning work?

When the Regional Pipeline runs:

1. **Reads Management cluster definitions** from `terraform/config/management-deploy/clusters/*.yaml`
2. **Filters for current region** (e.g., only `us-east-1` Management clusters)
3. **Mints Management AWS accounts** via Organizations API
4. **Assumes ManagementClusterDeployRole** in each Management account (with External ID)
5. **Deploys Management Cluster** via `make pipeline-provision-management`
6. **Registers with CLM** for capacity tracking

Each Regional Pipeline operates independently and only provisions Management clusters in its own region.

### What security controls prevent Regional Pipeline from affecting other regions?

Regional Pipeline has several layers of security controls:

1. **Region-Scoped Permissions**: IAM conditions enforce `aws:RequestedRegion = <region>`
2. **Restricted AssumeRole**: Uses ManagementClusterDeployRole (NOT OrganizationAccountAccessRole)
3. **External ID Requirement**: Cross-account assumption requires `sts:ExternalId = "regional-pipeline-{region}"`
4. **Limited IAM Permissions**: Can only create EKS/EC2 service roles, not arbitrary IAM
5. **Read-Only Central Access**: Can read management-deploy state, cannot write to Central bucket
6. **S3 Bucket Isolation**: Management state bucket only accessible from Regional Account

These controls ensure a compromised Regional Pipeline cannot:
- ❌ Affect resources in other regions
- ❌ Create accounts outside its region
- ❌ Access other Regional Pipeline states
- ❌ Modify Central Pipeline infrastructure
- ❌ Assume roles in Regional Clusters

### Should we use AWS Landing Zone for region setup?

- This is a valid consideration for the AWS Account Minting Service
- The architecture supports substituting infrastructure provisioning methods
- Current approach: Terraform + Tekton pipelines
- AWS Landing Zone could potentially:
  - Simplify multi-account setup
  - Provide standardized AWS account configurations
  - Reduce custom Terraform maintenance
- Decision is TBD - the pipeline-based approach allows for either implementation

### Is there a canary region for testing new releases?

- Yes, the architecture uses a **sector-based progressive deployment** model aligned with [ADR-0032](https://github.com/openshift-online/architecture/blob/main/hcm/decisions/archives/SD-ADR-0032_HyperShift_Change_Management_Strategy.md)
- The Git repository has one overlay that enables configuration following an inheritance model of defaults: Global defaults → Sector overrides → Region-specific overrides → Cluster-specific overrides
- Sectors will be predefined: e.g. `stage`, `sector 1`, `sector 2`, etc.
- Each region is assigned to a sector during provisioning

### Is the Regional API Gateway Red Hat managed?

- Yes, the Regional API Gateway is Red Hat managed infrastructure
- It consists of:
  - AWS API Gateway (regional endpoint)
  - VPC Link v2 (private connectivity)
  - Internal ALB (load balancing to Frontend API)
- Deployed and configured via the Central Control Plane's Terraform pipelines
- Exposed at `api.<region>.openshift.com`

### What is VPC Link v2?

- VPC Link v2 is an AWS feature that enables private connectivity between API Gateway and VPC resources
- Used to connect the public API Gateway to the private Frontend API in the Regional Cluster
- Benefits:
  - Traffic stays within AWS network (no public internet transit)
  - Enables private ALB targets
  - Lower latency than VPC Link v1
- Part of the request flow: API Gateway → VPC Link v2 → Internal ALB → Frontend API

### How is PrivateLink used in this architecture?

- Regional Cluster and Management Clusters are in separate VPCs, and their Kube APIs are private
- Regional Cluster MUST have **no** network path to the Management Cluster Kube API
- Management Clusters MUST have **no** network path to the Regional Cluster Kube API
- We might need a PrivateLink to expose services running in the Regional Cluster to be accessible from Management Clusters, we are specifically considering this for observability and for ArgoCD, however we are trying to avoid that. This design is TBD.

### Is OCM/CS deployed to each region?

- **No** - OCM, including CS and AMS, are replaced by **CLM** (Cluster Lifecycle Manager)
- CS and AMS will not be used in this architecture
- CLM will be used instead, which is a new component developed as part of Hyperfleet:
  - `hyperfleet-api`: Declarative REST API
  - `hyperfleet-sentinel`: Orchestration decisions
  - `hyperfleet-adapter`: Event-driven cluster provisioning
- One CLM instance runs in each Regional Cluster (in each region)
- CLM is the single source of truth for cluster state (replacing CS, Fleet Manager, and AMS)

### Is this design without App-Interface in favor of ArgoCD?

- **Yes** - the architecture does not depend on App-Interface for CD purposes
- We might still use App-Interface to run and the Central Control Plane, however this decision is pending
- Our approach is to use GitOps (ArgoCD) for application deployment
- We will use pipelines for infrastructure provisioning (Terraform)
- The Git repository is the source of truth for:
  - Terraform configurations
  - ArgoCD applications
  - Kubernetes manifests
- This provides independence from legacy systems as stated in project goals

### Is Backplane part of the Regional Cluster or its own cluster?

- Backplane will not be used in this architecture, at least not as it is currently designed
- We will favor instead a zero-operator access model, with ephemeral boundary containers for break-glass scenarios

### What is used for IDS?

We have not explored this decision yet.

### Is Splunk cloud or local to each region?

We have not explored this decision yet.
