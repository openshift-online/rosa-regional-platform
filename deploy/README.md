# Deploy Configuration

This directory contains deployment configurations for regional and management clusters. The **Pipeline Provisioner** automatically creates CodePipelines based on the directory structure and YAML files you commit here.

## Directory Structure

```
deploy/
└── <region-name>/                    # Region identifier (e.g., fedramp-us-east-1)
    ├── regional.yaml                 # Regional cluster config (1 per region)
    └── management/                   # Management clusters directory
        ├── <cluster-name>.yaml       # Management cluster config (many per region)
        └── <cluster-name>.yaml       # Another management cluster
```

## How It Works

1. **Bootstrap creates the Pipeline Provisioner** - A single meta-pipeline that watches the `deploy/` directory
2. **You create configuration files** - Add YAML files following the structure above
3. **Provisioner creates pipelines** - When you commit changes, the provisioner automatically creates:
   - **Regional Cluster Pipeline** - One per region (from `regional.yaml`)
   - **Management Cluster Pipelines** - Many per region (from `management/*.yaml`)
4. **Pipelines deploy clusters** - Each pipeline deploys its respective infrastructure

## Regional Cluster Configuration

**Location:** `deploy/<region-name>/regional.yaml`

**Purpose:** Creates a Regional Cluster pipeline for the specified region. Each region should have exactly ONE `regional.yaml` file.

**Example:**

```yaml
# deploy/fedramp-us-east-1/regional.yaml
account_id: "018092638725"        # AWS Account ID for deployment
region: "us-east-1"               # Target AWS region
alias: "regional-us-east-1"       # Unique alias for this environment
```

**What Gets Created:**
- CodePipeline named `regional-cluster-<region-name>`
- Regional infrastructure in the specified region
- EKS cluster running core services (CLM, Maestro, ArgoCD, etc.)

## Management Cluster Configuration

**Location:** `deploy/<region-name>/management/<cluster-name>.yaml`

**Purpose:** Creates a Management Cluster pipeline. Each region can have MANY management clusters, with one YAML file per cluster.

**Example:**

```yaml
# deploy/fedramp-us-east-1/management/mc01-us-east-1.yaml
account_id: "633630779107"         # AWS Account ID for deployment
region: "us-east-1"                # Target AWS region
alias: "management01-us-east-1"    # Unique alias for this cluster
```

**What Gets Created:**
- CodePipeline named `management-cluster-<region-name>-<cluster-name>`
- EKS cluster for hosting customer control planes
- Integration with the regional cluster

## Creating a New Region

To deploy to a new region (e.g., `fedramp-us-west-2`):

1. **Create the region directory:**
   ```bash
   mkdir -p deploy/fedramp-us-west-2/management
   ```

2. **Create regional.yaml:**
   ```bash
   cat > deploy/fedramp-us-west-2/regional.yaml <<EOF
   account_id: "YOUR_ACCOUNT_ID"
   region: "us-west-2"
   alias: "regional-us-west-2"
   EOF
   ```

3. **Create management cluster configs (optional):**
   ```bash
   cat > deploy/fedramp-us-west-2/management/mc01-us-west-2.yaml <<EOF
   account_id: "YOUR_MC_ACCOUNT_ID"
   region: "us-west-2"
   alias: "management01-us-west-2"
   EOF
   ```

4. **Commit and push:**
   ```bash
   git add deploy/fedramp-us-west-2/
   git commit -m "Add FedRAMP US West 2 region configuration"
   git push
   ```

5. **Monitor the provisioner:**
   - Navigate to AWS Console > CodePipeline
   - Find the `pipeline-provisioner` pipeline
   - It will detect your changes and create the new pipelines

## Adding a Management Cluster to an Existing Region

To add a new management cluster to an existing region:

1. **Create the YAML file:**
   ```bash
   cat > deploy/fedramp-us-east-1/management/mc02-us-east-1.yaml <<EOF
   account_id: "YOUR_MC_ACCOUNT_ID"
   region: "us-east-1"
   alias: "management02-us-east-1"
   EOF
   ```

2. **Commit and push:**
   ```bash
   git add deploy/fedramp-us-east-1/management/mc02-us-east-1.yaml
   git commit -m "Add MC02 management cluster to US East 1"
   git push
   ```

3. **The provisioner will create the new pipeline automatically**

## Configuration Reference

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| `account_id` | AWS Account ID for deployment | `"018092638725"` |
| `region` | Target AWS region | `"us-east-1"` |
| `alias` | Unique alias for this environment | `"regional-us-east-1"` |

### Region Naming Convention

The directory name under `deploy/` serves as the region identifier:
- **Format:** `<environment>-<region>`
- **Examples:**
  - `fedramp-us-east-1` - FedRAMP US East 1
  - `fedramp-us-west-2` - FedRAMP US West 2
  - `production-eu-west-1` - Production EU West 1

### Cluster Naming Convention

Management cluster filenames should follow:
- **Format:** `<cluster-id>-<short-region>.yaml`
- **Examples:**
  - `mc01-us-east-1.yaml` - Management Cluster 01 in US East 1
  - `mc02-us-west-2.yaml` - Management Cluster 02 in US West 2

## Pipeline Lifecycle

### Creation

When you commit a new YAML file:
1. Pipeline Provisioner detects the change
2. Runs Terraform to create the CodePipeline
3. New pipeline appears in AWS CodePipeline console
4. Pipeline automatically starts deploying infrastructure

### Updates

When you modify an existing YAML file:
1. Pipeline Provisioner detects the change
2. Updates the pipeline configuration
3. Pipeline re-deploys with new parameters

### Deletion

To remove a pipeline:
1. Delete the YAML file
2. Commit and push
3. Pipeline Provisioner will destroy the pipeline infrastructure

**Warning:** This only removes the pipeline, not the deployed clusters. You must manually destroy cluster resources before deleting the configuration.

## Troubleshooting

### Pipeline not created

1. **Check Pipeline Provisioner status:**
   - AWS Console > CodePipeline > `pipeline-provisioner`
   - Look for failed executions

2. **Review CodeBuild logs:**
   - Click on the failed execution
   - Check the "ProvisionPipelines" action logs

3. **Validate YAML syntax:**
   ```bash
   yamllint deploy/**/*.yaml
   ```

### Common Issues

**Missing required fields:**
```
Error: account_id is required
```
Solution: Add `account_id: "YOUR_ACCOUNT_ID"` to the YAML file

**Invalid region format:**
```
Error: region must be a valid AWS region
```
Solution: Use standard AWS region names (e.g., `us-east-1`, not `use1`)

**Duplicate pipeline names:**
```
Error: Pipeline with this name already exists
```
Solution: Ensure each region directory has a unique name

### GitHub Connection Pending

If this is your first pipeline:

1. Navigate to AWS Console > Developer Tools > Connections
2. Find the connection in PENDING state
3. Click "Update pending connection"
4. Authorize with your GitHub account

This authorization is shared across all pipelines.

## Example: Complete Multi-Region Setup

```
deploy/
├── fedramp-us-east-1/
│   ├── regional.yaml
│   └── management/
│       ├── mc01-us-east-1.yaml
│       ├── mc02-us-east-1.yaml
│       └── mc03-us-east-1.yaml
├── fedramp-us-west-2/
│   ├── regional.yaml
│   └── management/
│       ├── mc01-us-west-2.yaml
│       └── mc02-us-west-2.yaml
└── production-eu-west-1/
    ├── regional.yaml
    └── management/
        └── mc01-eu-west-1.yaml
```

This structure creates:
- **3 Regional Cluster pipelines** (one per region)
- **6 Management Cluster pipelines** (3 + 2 + 1 across regions)

## Additional Resources

- [Bootstrap Documentation](../scripts/bootstrap-central-account.sh) - Initial setup
- [Pipeline Provisioner Code](../terraform/config/pipeline-provisioner/) - Provisioner implementation
- [Architecture Documentation](../docs/) - Overall architecture
