# ECS Bootstrap Module for ArgoCD
# Provides ECS Fargate infrastructure for external bootstrap execution

locals {
  bootstrap_container_name = "bootstrap"
}

# Current AWS region information
data "aws_region" "current" {}

# ECS Cluster for bootstrap tasks
resource "aws_ecs_cluster" "bootstrap" {
  name = "${var.resource_name_base}-bootstrap"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# CloudWatch Log Group for bootstrap tasks
resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/ecs/${var.resource_name_base}/bootstrap"
  retention_in_days = 30
}

# ECS Task Definition for bootstrap execution
resource "aws_ecs_task_definition" "bootstrap" {
  family                   = "${var.resource_name_base}-bootstrap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = local.bootstrap_container_name
      image = "public.ecr.aws/aws-cli/aws-cli:latest"

      # Override default entrypoint to install tools and run bootstrap
      entryPoint = ["/bin/bash", "-c"]
      command = [
        <<-EOF
          set -euo pipefail

          echo "=== Installing bootstrap tools ==="
          yum update -y
          yum install -y tar gzip jq

          # Install kubectl
          KUBECTL_VERSION="v1.34.0"
          curl -L "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
          chmod +x /usr/local/bin/kubectl

          # Install helm
          HELM_VERSION="v3.12.0"
          curl -L "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz" -o helm.tar.gz
          tar -zxvf helm.tar.gz
          mv linux-amd64/helm /usr/local/bin/helm
          chmod +x /usr/local/bin/helm

          echo "=== Tool installation complete ==="
          kubectl version --client
          helm version

          # Configure kubectl for EKS
          aws eks update-kubeconfig --name $CLUSTER_NAME

          # Check if ArgoCD already exists
          if ! kubectl get deployment argocd-server -n argocd 2>/dev/null; then
            echo "Installing ArgoCD via Helm..."

            # Add ArgoCD Helm repository
            helm repo add argo https://argoproj.github.io/argo-helm
            helm repo update

            # Create argocd namespace
            kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

            ARGOCD_VERSION="9.3.4"
            # Install ArgoCD with adoption annotations for self-management handoff
            helm upgrade --install argocd argo/argo-cd \
              --namespace argocd \
              --version $ARGOCD_VERSION \
              --set-string 'controller.annotations.argocd\.argoproj\.io/tracking-id=argocd-self-management:argoproj.io/Application:argocd/argocd-self-management' \
              --set-string 'server.annotations.argocd\.argoproj\.io/tracking-id=argocd-self-management:argoproj.io/Application:argocd/argocd-self-management' \
              --set-string 'repoServer.annotations.argocd\.argoproj\.io/tracking-id=argocd-self-management:argoproj.io/Application:argocd/argocd-self-management' \
              --wait --timeout=5m

            echo "✓ ArgoCD installation complete"

            # Wait for ArgoCD to be ready
            kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
            kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
            kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

            echo "✓ ArgoCD is running and ready"
          else
            echo "✓ ArgoCD is already installed and running, skipping installation"
          fi

          echo "Creating/updating cluster identity secret with values:"
          echo "  ENVIRONMENT: $ENVIRONMENT"
          echo "  REGION: $REGION"
          echo "  CLUSTER_TYPE: $CLUSTER_TYPE"
          echo "  REPOSITORY_URL: $REPOSITORY_URL"
          echo "  REPOSITORY_BRANCH: $REPOSITORY_BRANCH"
          
          cat <<-SECRET_EOF | kubectl apply -f -
          apiVersion: v1
          kind: Secret
          metadata:
            name: local-cluster-identity
            namespace: argocd
            labels:
              argocd.argoproj.io/secret-type: cluster
              environment: "$ENVIRONMENT"
              region: "$REGION"
              cluster_type: "$CLUSTER_TYPE"
            annotations:
              git_repo: "$REPOSITORY_URL"
              git_revision: "$REPOSITORY_BRANCH"
              api_target_group_arn: "$API_TARGET_GROUP_ARN"
              api_allowed_accounts: "$API_ALLOWED_ACCOUNTS"
          type: Opaque
          stringData:
            name: in-cluster
            server: https://kubernetes.default.svc
            config: |
              {
                "tlsClientConfig": { "insecure": false }
              }
          SECRET_EOF

          echo "Creating/updating ArgoCD Root Application..."
          echo "  Repository URL: $REPOSITORY_URL"
          echo "  Target Revision: $REPOSITORY_BRANCH"
          echo "  Target Path: $REPOSITORY_PATH"
          
          cat <<-APP_EOF | kubectl apply -f -
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: root
            namespace: argocd
          spec:
            destination:
              namespace: argocd
              server: https://kubernetes.default.svc
            project: default
            source:
              repoURL: $REPOSITORY_URL
              targetRevision: $REPOSITORY_BRANCH
              path: $REPOSITORY_PATH
            syncPolicy:
              automated:
                prune: false
                selfHeal: true
              syncOptions:
                - CreateNamespace=true
          APP_EOF

          echo "=== Bootstrap completed successfully ==="
        EOF
      ]

      essential = true

      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.id
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.bootstrap.name
          awslogs-region        = data.aws_region.current.id
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}