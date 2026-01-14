# =============================================================================
# IAM Role and Pod Identity association for EBS CSI Driver
# This allows the EBS CSI driver to create, attach, and manage EBS volumes for pods
# =============================================================================
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  # Trust policy allows the Pod Identity service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = merge(
    var.tags,
    {
      "Purpose"        = "EBS-CSI-Driver-Pod-Identity"
      "Security-Scope" = "persistent-volume-management"
    }
  )
}

# Attach AWS managed policy for EBS CSI driver permissions
# This policy includes permissions to create, attach, detach, and manage EBS volumes
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Pod Identity Association - Links the IAM role to the EBS CSI service account
# This tells EKS that when the ebs-csi-controller-sa service account makes AWS API calls,
# it should use the permissions from the IAM role above
resource "aws_eks_pod_identity_association" "ebs_csi_driver" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_driver.arn

  tags = merge(
    var.tags,
    {
      "Association-Purpose" = "EBS-CSI-Driver"
      "ServiceAccount"      = "ebs-csi-controller-sa"
    }
  )
}
