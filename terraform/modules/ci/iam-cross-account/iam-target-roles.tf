# IAM Target Roles for Regional and Management Accounts
#
# These roles are created in the regional and management accounts and assumed by CodeBuild

# Regional account role with broad permissions (TODO: restrict to least privilege)
resource "aws_iam_role_policy_attachment" "regional_admin" {
  count      = local.create_regional_role ? 1 : 0
  role       = aws_iam_role.regional_access[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Management account role with broad permissions (TODO: restrict to least privilege)
resource "aws_iam_role_policy_attachment" "management_admin" {
  count      = local.create_management_role ? 1 : 0
  role       = aws_iam_role.management_access[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# TODO: Replace AdministratorAccess with least privilege policies
# Regional account should have permissions for:
# - EKS cluster management
# - VPC and networking resources
# - IoT Core for Maestro
# - RDS for CLM state
# - IAM roles for EKS service accounts
# - S3 for bootstrap artifacts
# - KMS for encryption
# - CloudWatch for logging and monitoring

# Management account should have permissions for:
# - EKS cluster management
# - VPC and networking resources
# - Secrets Manager for IoT certificates
# - IAM roles for EKS service accounts
# - S3 for bootstrap artifacts
# - KMS for encryption
# - CloudWatch for logging and monitoring

# Maximum session duration is now configured directly in the main role definitions (main.tf)
# to avoid duplicate resource conflicts.