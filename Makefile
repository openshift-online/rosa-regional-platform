.PHONY: help terraform-fmt terraform-upgrade

# Default target
help:
	@echo "Available targets:"
	@echo "  terraform-fmt          - Format all Terraform files"
	@echo "  terraform-upgrade      - Upgrade provider versions in all Terraform configurations"
	@echo "  help                   - Show this help message"

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

