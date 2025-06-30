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
      # S3 bucket-level actions (list & create)
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:CreateBucket"]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      },
      # S3 object & bucket config actions
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration", "s3:PutBucketVersioning"
        ]
        Resource = ["arn:aws:s3:::${var.bucket_name}/*"]
      },
      # Read bucket‐level settings for refresh
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      },

      # DynamoDB table creation & describing
      {
        Effect   = "Allow"
        Action   = ["dynamodb:CreateTable", "dynamodb:DescribeTable"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table}"
      },
      # DynamoDB item & query actions (once it exists)
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:Query"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table}"
      },
      # Read backup & TTL settings
      {
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeContinuousBackups", "dynamodb:DescribeTimeToLive"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table}"
      },
      # OIDC provider creation & listing
      {
        Effect   = "Allow"
        Action   = ["iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.oidc_provider}"
      },
      # Read IAM role details
      {
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = aws_iam_role.gha_role.arn
      }
    ]
  })
}
