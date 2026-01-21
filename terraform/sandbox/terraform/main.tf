provider "aws" {
  region  = "us-east-2"
  profile = "automation-rc"
}

resource "aws_dynamodb_table" "account_pool" {
  name         = "AccountPool"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "account_id"

  attribute {
    name = "account_id"
    type = "S"
  }

  tags = {
    Project     = "EKS-Testing"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table_item" "account" {
  for_each   = toset(var.account_ids)
  table_name = aws_dynamodb_table.account_pool.name
  hash_key   = aws_dynamodb_table.account_pool.hash_key

  item = jsonencode({
    account_id = { S = each.value }
    status     = { S = "AVAILABLE" }
  })

  lifecycle {
    ignore_changes = [item]
  }
}

data "aws_iam_user" "automation" {
  user_name = "automation"
}

resource "aws_iam_policy" "assume_role_policy" {
  name        = "AssumeRolePolicy"
  description = "Allow assuming OrganizationAccountAccessRole in sandbox accounts"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sts:AssumeRole"
        Effect   = "Allow"
        Resource = [for id in var.account_ids : "arn:aws:iam::${id}:role/OrganizationAccountAccessRole"]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "automation_assume_role" {
  user       = data.aws_iam_user.automation.user_name
  policy_arn = aws_iam_policy.assume_role_policy.arn
}
