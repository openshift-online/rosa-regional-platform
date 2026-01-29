provider "aws" {
  region = var.region
}

# -----------------------------------------------------------------------------
# IAM Role for CodeBuild Service
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codebuild_role" {
  name = "cross-account-test-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policies
# -----------------------------------------------------------------------------

# Policy to allow Assuming Roles in the specified Target Accounts
resource "aws_iam_role_policy" "cross_account_policy" {
  name = "allow-assume-cross-account"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        # Scopes permission to assume the specific role in the specific accounts
        Resource = [for account_id in var.target_account_ids : "arn:aws:iam::${account_id}:role/OrganizationAccountAccessRole"]
      }
    ]
  })
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "logging_policy" {
  name = "allow-logging"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodeBuild Project
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "cross_account_test" {
  name          = "cross-account-test"
  description   = "Test cross-account access to target accounts via sts:AssumeRole"
  build_timeout = "10"
  service_role  = aws_iam_role.codebuild_role.arn

  source {
    type = "NO_SOURCE"

    # Inline buildspec to ensure exact logic execution
    buildspec = <<-EOF
version: 0.2

phases:
  install:
    commands:
      - echo "Installing dependencies..."
      - yum install -y jq
  build:
    commands:
      - echo "Starting cross-account test..."
      - 'echo "Role to assume: $ROLE_NAME"'
      
      # Write the test logic to a script file to ensure function scope is preserved
      - |
        cat << 'SCRIPT' > cross_account_test.sh
        #!/bin/bash
        set -e

        TARGET_ACCOUNT_1=$1
        TARGET_ACCOUNT_2=$2
        ROLE_NAME=$3

        # Validate inputs
        if [ -z "$TARGET_ACCOUNT_1" ]; then
          echo "ERROR: TARGET_ACCOUNT_1 is not set."
          exit 1
        fi
        if [ -z "$TARGET_ACCOUNT_2" ]; then
          echo "ERROR: TARGET_ACCOUNT_2 is not set."
          exit 1
        fi
        if [ -z "$ROLE_NAME" ]; then
            echo "ERROR: ROLE_NAME is not set."
            exit 1
        fi

        assume_role() {
          local account_id=$1
          local role_name=$2
          local role_arn="arn:aws:iam::$${account_id}:role/$${role_name}"
          
          echo "Attempting to assume role: $role_arn"
          
          # Use a subshell to isolate credentials
          (
            creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "CodeBuildTest" --output json)
            
            if [ $? -eq 0 ]; then
              export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r '.Credentials.AccessKeyId')
              export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r '.Credentials.SecretAccessKey')
              export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r '.Credentials.SessionToken')
              
              echo "Successfully assumed role. Verifying identity..."
              if aws sts get-caller-identity; then
                echo "SUCCESS: STS GetCallerIdentity passed for account $account_id"
              else
                echo "FAILURE: STS GetCallerIdentity failed for account $account_id"
                exit 1
              fi
            else
              echo "Failed to assume role $role_arn"
              exit 1
            fi
          )
        }

        echo "--------------------------------------------------"
        echo "Target Account 1: $TARGET_ACCOUNT_1"
        assume_role "$TARGET_ACCOUNT_1" "$ROLE_NAME"
        
        echo "--------------------------------------------------"
        echo "Target Account 2: $TARGET_ACCOUNT_2"
        assume_role "$TARGET_ACCOUNT_2" "$ROLE_NAME"
        SCRIPT

      - chmod +x cross_account_test.sh
      - ./cross_account_test.sh "$TARGET_ACCOUNT_1" "$TARGET_ACCOUNT_2" "$ROLE_NAME"
EOF
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    # Environment variables to be overridden at runtime
    environment_variable {
      name  = "TARGET_ACCOUNT_1"
      value = ""
    }
    environment_variable {
      name  = "TARGET_ACCOUNT_2"
      value = ""
    }
    environment_variable {
      name  = "ROLE_NAME"
      value = "OrganizationAccountAccessRole"
    }
  }
}

# -----------------------------------------------------------------------------
# EventBridge (CloudWatch Events) Rule for Scheduled Trigger
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "hourly_trigger" {
  name                = "cross-account-test-schedule"
  description         = "Trigger the cross-account test CodeBuild project on schedule"
  schedule_expression = var.schedule_expression
}

# IAM Role for EventBridge to invoke CodeBuild
resource "aws_iam_role" "eventbridge_role" {
  name = "cross-account-test-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "allow-start-build"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.cross_account_test.arn
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "codebuild_target" {
  rule      = aws_cloudwatch_event_rule.hourly_trigger.name
  target_id = "TriggerCodeBuild"
  arn       = aws_codebuild_project.cross_account_test.arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input = jsonencode({
    environmentVariablesOverride = [
      {
        name  = "TARGET_ACCOUNT_1"
        value = var.target_account_ids[0]
        type  = "PLAINTEXT"
      },
      {
        name  = "TARGET_ACCOUNT_2"
        value = var.target_account_ids[1]
        type  = "PLAINTEXT"
      },
      {
        name  = "ROLE_NAME"
        value = var.target_role_name
        type  = "PLAINTEXT"
      }
    ]
  })
}
