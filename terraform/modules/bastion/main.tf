# ECS Fargate Bastion Module
# Provides ephemeral break-glass access to private EKS clusters via ECS Exec (SSM)

locals {
  container_name = "bastion"
}

data "aws_region" "current" {}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "bastion" {
  name              = "/ecs/${var.resource_name_base}/bastion"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# =============================================================================
# Security Group
# =============================================================================

resource "aws_security_group" "bastion" {
  name        = "${var.resource_name_base}-bastion"
  description = "Security group for bastion ECS tasks"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic (needed for tool downloads, EKS API, SSM endpoints)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.resource_name_base}-bastion"
  })
}

# Allow bastion to access EKS control plane
resource "aws_security_group_rule" "eks_ingress_from_bastion" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.bastion.id
  description              = "Allow bastion tasks to access EKS API"
}

# =============================================================================
# ECS Cluster (dedicated for bastion tasks)
# =============================================================================

resource "aws_ecs_cluster" "bastion" {
  name = "${var.resource_name_base}-bastion"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # Enable ECS Exec logging
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.bastion.name
      }
    }
  }

  tags = var.tags
}

# =============================================================================
# Cleanup Running Tasks on Destroy
# =============================================================================
# This ensures any running bastion tasks are stopped before the cluster is destroyed.
# Without this, terraform destroy would fail if a task was left running.

resource "null_resource" "stop_bastion_tasks" {
  depends_on = [aws_ecs_cluster.bastion]

  triggers = {
    cluster_name = aws_ecs_cluster.bastion.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      echo "Stopping any running tasks in ECS cluster ${self.triggers.cluster_name}..."
      TASKS=$(aws ecs list-tasks --cluster ${self.triggers.cluster_name} --query 'taskArns[]' --output text 2>/dev/null || true)
      if [ -n "$TASKS" ] && [ "$TASKS" != "None" ]; then
        for TASK in $TASKS; do
          echo "Stopping task: $TASK"
          aws ecs stop-task --cluster ${self.triggers.cluster_name} --task $TASK --reason "Terraform destroy" || true
        done
        echo "Waiting for tasks to stop..."
        sleep 5
      else
        echo "No running tasks found"
      fi
    EOF
  }
}

# =============================================================================
# ECS Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "bastion" {
  family                   = "${var.resource_name_base}-bastion"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "public.ecr.aws/amazonlinux/amazonlinux:2023"
      essential = true

      # Entrypoint script that installs SRE tools and waits for connections
      entryPoint = ["/bin/bash", "-c"]
      command = [
        <<-EOF
          set -euo pipefail

          echo "=== ROSA Regional Platform Bastion ==="
          echo "Starting at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

          # Install base dependencies
          echo "Installing base packages..."
          dnf install -y --quiet \
            tar \
            gzip \
            unzip \
            jq \
            git \
            less \
            vim \
            which \
            procps-ng \
            bind-utils \
            postgresql15 \
            2>/dev/null

          # Install AWS CLI v2
          echo "Installing AWS CLI..."
          curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
          unzip -q /tmp/awscliv2.zip -d /tmp
          /tmp/aws/install --update
          rm -rf /tmp/aws /tmp/awscliv2.zip

          # Install kubectl
          echo "Installing kubectl..."
          KUBECTL_VERSION="v1.31.0"
          curl -sL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
          chmod +x /usr/local/bin/kubectl

          # Install helm
          echo "Installing helm..."
          HELM_VERSION="v3.16.0"
          curl -sL "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz" | tar -xz -C /tmp
          mv /tmp/linux-amd64/helm /usr/local/bin/helm
          chmod +x /usr/local/bin/helm
          rm -rf /tmp/linux-amd64

          # Install k9s
          echo "Installing k9s..."
          K9S_VERSION="v0.32.5"
          curl -sL "https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_amd64.tar.gz" | tar -xz -C /tmp
          mv /tmp/k9s /usr/local/bin/k9s
          chmod +x /usr/local/bin/k9s

          # Install stern (log tailing)
          echo "Installing stern..."
          STERN_VERSION="1.30.0"
          curl -sL "https://github.com/stern/stern/releases/download/v$STERN_VERSION/stern_$${STERN_VERSION}_linux_amd64.tar.gz" | tar -xz -C /tmp
          mv /tmp/stern /usr/local/bin/stern
          chmod +x /usr/local/bin/stern

          # Install yq
          echo "Installing yq..."
          YQ_VERSION="v4.44.3"
          curl -sL "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64" -o /usr/local/bin/yq
          chmod +x /usr/local/bin/yq

          # Install OpenShift CLI (oc)
          echo "Installing OpenShift CLI..."
          OC_VERSION="4.16.0"
          curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OC_VERSION/openshift-client-linux.tar.gz" | tar -xz -C /tmp
          mv /tmp/oc /usr/local/bin/oc
          chmod +x /usr/local/bin/oc
          rm -f /tmp/kubectl /tmp/README.md

          echo "=== Tool installation complete ==="
          echo ""
          echo "Installed tools:"
          echo "  - aws: $(aws --version 2>&1 | head -1)"
          echo "  - kubectl: $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion')"
          echo "  - helm: $(helm version --short)"
          echo "  - k9s: $(k9s version -s | head -1)"
          echo "  - stern: $(stern --version)"
          echo "  - yq: $(yq --version)"
          echo "  - oc: $(oc version --client -o json 2>/dev/null | jq -r '.releaseClientVersion')"
          echo "  - jq: $(jq --version)"
          echo ""

          # Configure kubectl for EKS
          echo "Configuring kubectl for cluster: $CLUSTER_NAME"
          aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

          # Verify connectivity
          echo ""
          echo "Testing cluster connectivity..."
          if kubectl cluster-info 2>/dev/null; then
            echo ""
            echo "=== Bastion ready for connections ==="
            echo ""
            echo "Connect using:"
            echo "  aws ecs execute-command \\"
            echo "    --cluster ${var.resource_name_base}-bastion \\"
            echo "    --task <TASK_ID> \\"
            echo "    --container bastion \\"
            echo "    --interactive \\"
            echo "    --command '/bin/bash'"
            echo ""
          else
            echo "WARNING: Could not connect to cluster API"
          fi

          # Keep container running for ECS Exec sessions
          echo "Bastion is ready. Waiting for ECS Exec connections..."
          echo "Container will stay running until the task is stopped."
          echo ""

          # Infinite wait - container stays alive for exec sessions
          while true; do
            sleep 3600
          done
        EOF
      ]

      environment = [
        {
          name  = "CLUSTER_NAME"
          value = var.cluster_name
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.id
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.bastion.name
          awslogs-region        = data.aws_region.current.id
          awslogs-stream-prefix = "bastion"
        }
      }

      # Required for ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = var.tags
}
