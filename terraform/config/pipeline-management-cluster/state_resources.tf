# Shared S3 Bucket for Management Cluster State
resource "aws_s3_bucket" "management_state" {
  bucket = "terraform-state-management-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "management_state" {
  bucket = aws_s3_bucket.management_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "management_state" {
  bucket = aws_s3_bucket.management_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Shared DynamoDB Table for Locking
resource "aws_dynamodb_table" "management_locks" {
  name         = "terraform-locks-management"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
