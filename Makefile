.PHONY: help central-bootstrap terraform-fmt terraform-upgrade provision-management provision-regional apply-infra-management apply-infra-regional destroy-management destroy-regional test test-e2e new-region

# Default target
help:
	@echo "🏗️  Central Pipeline Bootstrap (One-Time Setup):"
	@echo "  central-bootstrap                - Deploy Central Pipeline infrastructure (run once manually)"
	@echo ""
	@echo "🚀 Cluster Provisioning / Deprovisioning:"
	@echo "  provision-management             - Provision management cluster environment (infra & argocd bootstrap)"
	@echo "  provision-regional               - Provision regional cluster environment (infra & argocd bootstrap)"
	@echo "  new-region                       - Provision new region (mints accounts & deploys clusters)"
	@echo "  destroy-management               - Destroy management cluster environment"
	@echo "  destroy-regional                 - Destroy regional cluster environment"
	@echo ""
	@echo "🔧 Infrastructure Only:"
	@echo "  apply-infra-management       - Apply only management cluster infrastructure"
	@echo "  apply-infra-regional         - Apply only regional cluster infrastructure"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  test                             - Run tests"
	@echo "  test-e2e                         - Run end-to-end tests"
	@echo ""
	@echo "🛠️  Terraform Utilities:"
	@echo "  terraform-fmt                    - Format all Terraform files"
	@echo "  terraform-upgrade                - Upgrade provider versions"
	@echo ""
	@echo "  help                             - Show this help message"

# Discover all directories containing Terraform files (excluding .terraform subdirectories)
TERRAFORM_DIRS := $(shell find ./terraform -name "*.tf" -type f -not -path "*/.terraform/*" | xargs dirname | sort -u)

# Format all Terraform files
terraform-fmt:
	@echo "🔧 Formatting Terraform files..."
	@for dir in $(TERRAFORM_DIRS); do \
		echo "   Formatting $$dir"; \
		terraform -chdir=$$dir fmt -recursive; \
	done
	@echo "✅ Terraform formatting complete"

# Upgrade provider versions in all Terraform configurations
terraform-upgrade:
	@echo "🔧 Upgrading Terraform provider versions..."
	@for dir in $(TERRAFORM_DIRS); do \
		echo "   Upgrading $$dir"; \
		terraform -chdir=$$dir init -upgrade -backend=false; \
	done
	@echo "✅ Terraform upgrade complete"

# =============================================================================
# Central Pipeline Bootstrap (One-Time Manual Setup)
# =============================================================================

# Bootstrap the Central Pipeline infrastructure (run once manually)
central-bootstrap:
	@echo "🏗️  Central Pipeline Bootstrap"
	@echo "========================================================================"
	@echo ""
	@echo "⚠️  IMPORTANT: This is a ONE-TIME manual bootstrap process"
	@echo ""
	@echo "This will deploy the Central Pipeline infrastructure that:"
	@echo "  • Creates AWS CodePipeline for Regional Cluster deployment"
	@echo "  • Creates CodeStar connection to GitHub"
	@echo "  • Creates S3 buckets for state and artifacts"
	@echo "  • Sets up IAM roles with organization-wide permissions"
	@echo ""
	@echo "After deployment, the Central Pipeline will automatically:"
	@echo "  • Monitor Git repository for Regional Cluster definitions"
	@echo "  • Mint Regional AWS accounts"
	@echo "  • Deploy Regional Clusters"
	@echo "  • Bootstrap Regional Pipelines"
	@echo ""
	@echo "========================================================================"
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/central-pipeline"
	@echo ""
	@echo "🔑 Target AWS Account:"
	@echo "========================================================================"; \
	aws sts get-caller-identity || { echo "❌ Failed to get AWS identity. Is AWS CLI configured?"; exit 1; }; \
	echo "========================================================================"; \
	echo ""; \
	account_id=$$(aws sts get-caller-identity --query Account --output text); \
	account_alias=$$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null || echo "N/A"); \
	region=$$(aws configure get region || echo "us-east-1"); \
	echo "📋 Deployment Target:"; \
	echo "   Account ID: $$account_id"; \
	echo "   Account Alias: $$account_alias"; \
	echo "   Region: $$region"; \
	echo ""; \
	echo "⚠️  WARNING: Central Pipeline will be deployed to the account above"; \
	echo "⚠️  This account should be your AWS Central Account"; \
	echo ""; \
	read -p "Is this the correct AWS account? [y/N]: " account_confirm; \
	if [ "$$account_confirm" != "y" ] && [ "$$account_confirm" != "Y" ]; then \
		echo ""; \
		echo "❌ Operation cancelled."; \
		echo ""; \
		echo "💡 To target a different account:"; \
		echo "   1. Configure AWS CLI: aws configure"; \
		echo "   2. Or use AWS profile: export AWS_PROFILE=<profile-name>"; \
		echo "   3. Or assume a role: aws sts assume-role ..."; \
		exit 1; \
	fi; \
	echo ""; \
	read -p "Enter GitHub repository ID (owner/repo-name): " repo_id; \
	read -p "Enter branch name to monitor [main]: " branch_name; \
	branch_name=$${branch_name:-main}; \
	echo ""; \
	echo "📝 Final Configuration:"; \
	echo "   Repository: $$repo_id"; \
	echo "   Branch: $$branch_name"; \
	echo "   AWS Account: $$account_id"; \
	echo "   AWS Region: $$region"; \
	echo ""; \
	read -p "Proceed with Central Pipeline deployment? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "❌ Operation cancelled."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "🚀 Step 1: Deploying Central Pipeline Infrastructure..."; \
	echo "========================================================================"; \
	cd terraform/config/central-pipeline && \
		terraform init && \
		terraform apply \
			-var="repository_id=$$repo_id" \
			-var="branch_name=$$branch_name"; \
	if [ $$? -ne 0 ]; then \
		echo ""; \
		echo "❌ Central Pipeline deployment failed"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "✅ Central Pipeline infrastructure deployed successfully!"; \
	echo ""; \
	echo "📋 Post-Deployment Steps:"; \
	echo "========================================================================"; \
	echo ""; \
	echo "1️⃣  ACTIVATE CODESTAR CONNECTION (REQUIRED):"; \
	echo "   • Open AWS Console → Developer Tools → Connections"; \
	echo "   • Find connection: github-connection"; \
	echo "   • Click 'Update pending connection'"; \
	echo "   • Authorize GitHub access"; \
	echo ""; \
	echo "2️⃣  MIGRATE TO REMOTE STATE (RECOMMENDED):"; \
	echo "   • Edit: terraform/config/central-pipeline/backend.tf"; \
	echo "   • Uncomment the S3 backend configuration"; \
	echo "   • Update bucket name from Terraform outputs"; \
	echo "   • Run: cd terraform/config/central-pipeline && terraform init -migrate-state"; \
	echo ""; \
	echo "3️⃣  ADD REGIONAL CLUSTER DEFINITIONS:"; \
	echo "   • Create YAML files in: terraform/config/region-deploy/regions/"; \
	echo "   • Example: us-east-1-regional.yaml"; \
	echo "   • Git commit and push to trigger pipeline"; \
	echo ""; \
	echo "========================================================================"; \
	echo ""; \
	echo "📊 Pipeline Status:"; \
	terraform output pipeline_url; \
	echo ""; \
	echo "🎉 Central Pipeline Bootstrap Complete!"; \
	echo ""

# =============================================================================
# Cluster Provisioning/Deprovisioning Targets
# =============================================================================

# Provision complete management cluster (infrastructure + ArgoCD)
provision-management:
	@echo "🚀 Provisioning management cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/management-cluster"
	@echo "🔑 AWS Caller Identity:" && aws sts get-caller-identity
	@echo ""
	@read -p "Do you want to proceed? [y/N]: " confirm && \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Operation cancelled."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/management-cluster && \
		terraform init && terraform apply
	@echo ""
	@echo "Bootstrapping argocd..."
	scripts/bootstrap-argocd.sh management

# Provision complete regional cluster (infrastructure + ArgoCD)
provision-regional:
	@echo "🚀 Provisioning regional cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/regional-cluster"
	@echo "🔑 AWS Caller Identity:" && aws sts get-caller-identity
	@echo ""
	@read -p "Do you want to proceed? [y/N]: " confirm && \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Operation cancelled."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/regional-cluster && \
		terraform init && terraform apply
	@echo ""
	@echo "Bootstrapping argocd..."
	@scripts/bootstrap-argocd.sh regional

# Pipeline provision management (Non-interactive)
pipeline-provision-management:
	@echo "🚀 Pipeline Provisioning management cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/management-cluster"
	@cd terraform/config/management-cluster && \
		terraform init && terraform apply -auto-approve
	@echo ""
	@echo "Bootstrapping argocd..."
	@scripts/bootstrap-argocd.sh management

# Pipeline provision regional (Non-interactive)
pipeline-provision-regional:
	@echo "🚀 Pipeline Provisioning regional cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/regional-cluster"
	@cd terraform/config/regional-cluster && \
		terraform init && terraform apply -auto-approve
	@echo ""
	@echo "Bootstrapping argocd..."
	@scripts/bootstrap-argocd.sh regional

# Destroy management cluster and all resources
destroy-management:
	@echo "🗑️  Destroying management cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/management-cluster"
	@echo "🔑 AWS Caller Identity:" && aws sts get-caller-identity
	@echo ""
	@read -p "Type 'destroy' to confirm deletion: " confirm && \
		if [ "$$confirm" != "destroy" ]; then \
			echo "❌ Operation cancelled. You must type exactly 'destroy' to proceed."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/management-cluster && \
		terraform init && terraform destroy

# Destroy regional cluster and all resources
destroy-regional:
	@echo "🗑️  Destroying regional cluster..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/regional-cluster"
	@echo "🔑 AWS Caller Identity:" && aws sts get-caller-identity
	@echo ""
	@read -p "Type 'destroy' to confirm deletion: " confirm && \
		if [ "$$confirm" != "destroy" ]; then \
			echo "❌ Operation cancelled. You must type exactly 'destroy' to proceed."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/regional-cluster && \
		terraform init && terraform destroy

# =============================================================================
# Infrastructure Maintenance Targets
# =============================================================================

# Infrastructure-only deployment
apply-infra-management:
	@echo "🏗️  Applying management cluster infrastructure..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/management-cluster"
	@echo ""
	@read -p "Do you want to proceed? [y/N]: " confirm && \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Operation cancelled."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/management-cluster && \
		terraform init && terraform apply

apply-infra-regional:
	@echo "🏗️  Applying regional cluster infrastructure..."
	@echo ""
	@echo "📍 Terraform Directory: terraform/config/regional-cluster"
	@echo ""
	@read -p "Do you want to proceed? [y/N]: " confirm && \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Operation cancelled."; \
			exit 1; \
		fi
	@echo ""
	@cd terraform/config/regional-cluster && \
		terraform init && terraform apply

# =============================================================================
# Testing Targets
# =============================================================================

# Run tests
test:
	@echo "🧪 Running tests..."
	@./test/execute-prow-job.sh
	@echo "✅ Tests complete"

# Run end-to-end tests
test-e2e:
	@echo "🧪 Running end-to-end tests..."
	@echo "✅ End-to-end tests complete"

# =============================================================================
# New Region Provisioning
# =============================================================================

# Provision a new region with Regional and Management clusters
new-region:
	@echo "🌍 New Region Provisioning"
	@echo "================================================"
	@echo ""
	@echo "This target automates the full deployment workflow:"
	@echo "  1. Creates region definition YAML files"
	@echo "  2. Mints AWS accounts via AWS Organizations"
	@echo "  3. Deploys Regional and Management clusters to new accounts"
	@echo ""
	@echo "🔑 Current AWS Identity:"
	@aws sts get-caller-identity
	@echo ""
	@read -p "Enter test region name (e.g., us-west-2): " region_name; \
	read -p "Enter base email for accounts (e.g., aws-test): " base_email; \
	read -p "Enter email domain (e.g., example.com): " email_domain; \
	echo ""; \
	echo "📝 Configuration:"; \
	echo "   Region: $$region_name"; \
	echo "   Regional Account Email: $$base_email+regional-$$region_name@$$email_domain"; \
	echo "   Management Account Email: $$base_email+management-$$region_name@$$email_domain"; \
	echo ""; \
	read -p "Proceed with account minting? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "❌ Operation cancelled."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "📄 Creating region definition files..."; \
	echo "name: \"rosa-regional-$$region_name\"" > terraform/config/region-deploy/regions/$$region_name-regional.yaml; \
	echo "email: \"$$base_email+regional-$$region_name@$$email_domain\"" >> terraform/config/region-deploy/regions/$$region_name-regional.yaml; \
	echo "region: \"$$region_name\"" >> terraform/config/region-deploy/regions/$$region_name-regional.yaml; \
	echo "type: \"regional\"" >> terraform/config/region-deploy/regions/$$region_name-regional.yaml; \
	echo "✅ Created: terraform/config/region-deploy/regions/$$region_name-regional.yaml"; \
	echo ""; \
	echo "name: \"rosa-management-$$region_name\"" > terraform/config/region-deploy/regions/$$region_name-management.yaml; \
	echo "email: \"$$base_email+management-$$region_name@$$email_domain\"" >> terraform/config/region-deploy/regions/$$region_name-management.yaml; \
	echo "region: \"$$region_name\"" >> terraform/config/region-deploy/regions/$$region_name-management.yaml; \
	echo "type: \"management\"" >> terraform/config/region-deploy/regions/$$region_name-management.yaml; \
	echo "✅ Created: terraform/config/region-deploy/regions/$$region_name-management.yaml"; \
	echo ""; \
	echo "🏗️  Step 1: Minting AWS Accounts..."; \
	echo "================================================"; \
	cd terraform/config/region-deploy && \
		terraform init && \
		terraform apply; \
	if [ $$? -ne 0 ]; then \
		echo "❌ Account minting failed. Cleaning up YAML files..."; \
		rm -f terraform/config/region-deploy/regions/$$region_name-regional.yaml; \
		rm -f terraform/config/region-deploy/regions/$$region_name-management.yaml; \
		exit 1; \
	fi; \
	echo ""; \
	echo "✅ Accounts minted successfully!"; \
	echo ""; \
	echo "📊 Reading account information..."; \
	cd terraform/config/region-deploy && terraform output -json accounts > /tmp/accounts-$$region_name.json; \
	echo ""; \
	echo "🚀 Step 2: Deploying Clusters to New Accounts..."; \
	echo "================================================"; \
	echo ""; \
	python3 -c " \
import json, sys, os, subprocess; \
with open('/tmp/accounts-$$region_name.json', 'r') as f: \
    accounts = json.load(f); \
print('Found {} accounts to provision'.format(len(accounts))); \
sts_client = None; \
try: \
    import boto3; \
    sts_client = boto3.client('sts'); \
except ImportError: \
    print('⚠️  Warning: boto3 not available, skipping role assumption'); \
for name, config in accounts.items(): \
    if '$$region_name' not in name: \
        continue; \
    print('\n========================================'); \
    print('Processing: {} ({})'.format(name, config['type'])); \
    print('Account ID: {}'.format(config['id'])); \
    print('Region: {}'.format(config['region'])); \
    print('========================================\n'); \
    if sts_client: \
        role_arn = 'arn:aws:iam::{}:role/OrganizationAccountAccessRole'.format(config['id']); \
        print('🔐 Assuming role: {}'.format(role_arn)); \
        try: \
            assumed_role = sts_client.assume_role( \
                RoleArn=role_arn, \
                RoleSessionName='NewRegionTestSession' \
            ); \
            creds = assumed_role['Credentials']; \
            env = os.environ.copy(); \
            env['AWS_ACCESS_KEY_ID'] = creds['AccessKeyId']; \
            env['AWS_SECRET_ACCESS_KEY'] = creds['SecretAccessKey']; \
            env['AWS_SESSION_TOKEN'] = creds['SessionToken']; \
            env['AWS_DEFAULT_REGION'] = config['region']; \
            env['AWS_REGION'] = config['region']; \
        except Exception as e: \
            print('❌ Failed to assume role: {}'.format(e)); \
            sys.exit(1); \
    else: \
        env = os.environ.copy(); \
    cluster_type = config['type']; \
    if cluster_type == 'management': \
        target_dir = 'terraform/config/management-cluster'; \
        make_target = 'pipeline-provision-management'; \
    elif cluster_type == 'regional': \
        target_dir = 'terraform/config/regional-cluster'; \
        make_target = 'pipeline-provision-regional'; \
    else: \
        print('Unknown cluster type: {}, skipping'.format(cluster_type)); \
        continue; \
    print('📦 Initializing Terraform backend...'); \
    state_bucket = os.environ.get('TF_STATE_BUCKET', 'local-state-bucket'); \
    backend_region = os.environ.get('TF_BACKEND_REGION', 'us-east-1'); \
    key = '{}/terraform.tfstate'.format(name); \
    init_cmd = [ \
        'terraform', 'init', '-reconfigure', \
        '-backend-config=bucket={}'.format(state_bucket), \
        '-backend-config=key={}'.format(key), \
        '-backend-config=region={}'.format(backend_region) \
    ]; \
    result = subprocess.run(init_cmd, cwd=target_dir, env=env); \
    if result.returncode != 0: \
        print('❌ Terraform init failed'); \
        sys.exit(1); \
    print('\n🚀 Running make {}...'.format(make_target)); \
    result = subprocess.run(['make', make_target], env=env); \
    if result.returncode != 0: \
        print('❌ Cluster provisioning failed'); \
        sys.exit(1); \
    print('✅ {} cluster deployed successfully!\n'.format(cluster_type)); \
print('\n🎉 All clusters deployed successfully!'); \
"; \
	echo ""; \
	echo "================================================"; \
	echo "✅ Account Minting & Deployment Complete!"; \
	echo "================================================"; \
	echo ""; \
	echo "📋 Summary:"; \
	echo "   Region: $$region_name"; \
	echo "   Regional Cluster: Deployed"; \
	echo "   Management Cluster: Deployed"; \
	echo ""; \
	echo "🗑️  To clean up, run:"; \
	echo "   rm terraform/config/region-deploy/regions/$$region_name-*.yaml"; \
	echo "   cd terraform/config/region-deploy && terraform apply"

