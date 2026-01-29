.PHONY: help terraform-fmt terraform-upgrade provision-management provision-regional apply-infra-management apply-infra-regional destroy-management destroy-regional test test-e2e cloud-nuke cloud-nuke-dry-run install-cloud-nuke

# Default target
help:
	@echo "🚀 Cluster Provisioning / Deprovisioning:"
	@echo "  provision-management             - Provision management cluster environment (infra & argocd bootstrap)"
	@echo "  provision-regional               - Provision regional cluster environment (infra & argocd bootstrap)"
	@echo "  destroy-management               - Destroy management cluster environment"
	@echo "  destroy-regional                 - Destroy regional cluster environment"
	@echo ""
	@echo "🔧 Infrastructure Only:"
	@echo "  apply-infra-management       - Apply only management cluster infrastructure"
	@echo "  apply-infra-regional         - Apply only regional cluster infrastructure"
	@echo ""
	@echo "🛠️  Terraform Utilities:"
	@echo "  terraform-fmt                    - Format all Terraform files"
	@echo "  terraform-upgrade                - Upgrade provider versions"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  test                             - Run tests"
	@echo "  test-e2e                         - Run end-to-end tests"
	@echo ""
	@echo "☢️  AWS Account Cleanup:"
	@echo "  install-cloud-nuke               - Install cloud-nuke binary"
	@echo "  cloud-nuke-dry-run               - Dry run cloud-nuke (shows what would be deleted)"
	@echo "  cloud-nuke                       - Run cloud-nuke to delete AWS resources"
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
# Cluster Provisioning/Deprovisioning Targets
# =============================================================================

# Provision complete management cluster (infrastructure + ArgoCD)
provision-management:
	@echo "🚀 Provisioning management cluster..."
	@echo ""
	@scripts/validate-argocd-config.sh management-cluster
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
	scripts/bootstrap-argocd.sh management-cluster

# Provision complete regional cluster (infrastructure + ArgoCD)
provision-regional:
	@echo "🚀 Provisioning regional cluster..."
	@echo ""
	@scripts/validate-argocd-config.sh regional-cluster
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
	@scripts/bootstrap-argocd.sh regional-cluster

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
# AWS Account Cleanup Targets
# =============================================================================

# Install cloud-nuke binary
install-cloud-nuke:
	@echo "🔧 Installing cloud-nuke..."
	@if command -v cloud-nuke > /dev/null 2>&1; then \
		echo "✅ cloud-nuke is already installed at $$(which cloud-nuke)"; \
		cloud-nuke --version; \
		exit 0; \
	fi
	@echo "📥 Downloading cloud-nuke..."
	@CLOUD_NUKE_VERSION="v0.37.1" && \
	TEMP_DIR=$$(mktemp -d) && \
	trap "rm -rf $$TEMP_DIR" EXIT && \
	wget -q -P "$$TEMP_DIR" "https://github.com/gruntwork-io/cloud-nuke/releases/download/$${CLOUD_NUKE_VERSION}/cloud-nuke_linux_amd64" && \
	mv "$$TEMP_DIR/cloud-nuke_linux_amd64" "$$TEMP_DIR/cloud-nuke" && \
	chmod +x "$$TEMP_DIR/cloud-nuke" && \
	sudo mv "$$TEMP_DIR/cloud-nuke" /usr/local/bin/ && \
	echo "✅ cloud-nuke installed successfully at /usr/local/bin/cloud-nuke" && \
	cloud-nuke --version

# Dry run cloud-nuke to see what resources would be deleted
cloud-nuke-dry-run:
	@DISABLE_TELEMETRY=true ./scripts/cloud-nuke.py --dry-run --region $${AWS_REGION:-us-east-1}

# Run cloud-nuke to delete AWS resources
cloud-nuke:
	@DISABLE_TELEMETRY=true ./scripts/cloud-nuke.py --region $${AWS_REGION:-us-east-1}

