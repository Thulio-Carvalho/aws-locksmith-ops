data "aws_caller_identity" "current" {}

# S3 bucket for remote state
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform state bucket"
    Environment = "bootstrap"
  }
}

# Versioning (standalone resource)
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access block
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for locking
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform lock table"
    Environment = "bootstrap"
  }
}

# GitHub OIDC provider registration
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://${var.oidc_provider}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role for GitHub Actions (OIDC assume)
resource "aws_iam_role" "gha_role" {
  name = "terraform-backend-gha"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "${var.oidc_provider}:sub" = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch_pattern}"
        }
      }
    }]
  })
}

# Policy: least-privilege to S3 + DynamoDB
resource "aws_iam_role_policy" "gha_policy" {
  role = aws_iam_role.gha_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.state.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.state.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem",
          "dynamodb:DescribeTable", "dynamodb:Query", "dynamodb:Scan"
        ]
        Resource = [aws_dynamodb_table.lock.arn]
      }
    ]
  })
}

