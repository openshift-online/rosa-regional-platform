# =============================================================================
# IAM Roles and Policies for EKS Cluster
#
# Creates IAM roles required for EKS Auto Mode operation:
# - Cluster service role with required permissions
# - Node group role for Auto Mode managed nodes
# =============================================================================

# -----------------------------------------------------------------------------
# EKS Cluster Service Role
#
# Role assumed by EKS control plane. Auto Mode requires additional permissions
# including sts:TagSession for resource tagging.
# See: https://docs.aws.amazon.com/eks/latest/userguide/automode-get-started-cli.html#auto-mode-create-roles
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_cluster" {
  name = "${local.resource_name_base}-cluster-role"

  # Auto Mode REQUIRES sts:TagSession to propagate tags to managed infra
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  ])
  policy_arn = each.value
  role       = aws_iam_role.eks_cluster.name
}

# -----------------------------------------------------------------------------
# EKS Auto Mode Node Role
#
# Role assumed by Auto Mode managed nodes. Includes all required policies
# for node operation, networking, storage, and load balancing.
# See: https://docs.aws.amazon.com/eks/latest/userguide/automode-get-started-cli.html#auto-mode-create-roles
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eks_auto_mode_node" {
  name = "${local.resource_name_base}-auto-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com", "eks.amazonaws.com"]
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "auto_node_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  ])
  policy_arn = each.value
  role       = aws_iam_role.eks_auto_mode_node.name
}