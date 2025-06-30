data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  bucket_name   = "lucy-infra-tf-state"
  lock_table    = "lucy-tf-lock"
  oidc_provider = "token.actions.githubusercontent.com"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning { enabled = true }
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = {
    Name        = "Terraform state bucket"
    Environment = "bootstrap"
  }
}

resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table
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

resource "aws_iam_openid_connect_provider" "github" {
  url                    = "https://${local.oidc_provider}"
  client_id_list         = ["sts.amazonaws.com"]
  thumbprint_list        = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "gha_role" {
  name = "terraform-backend-gha"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

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
        Action   = ["s3:GetObject","s3:PutObject","s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.state.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:PutItem","dynamodb:GetItem","dynamodb:DeleteItem",
          "dynamodb:DescribeTable","dynamodb:Query","dynamodb:Scan"
        ]
        Resource = [aws_dynamodb_table.lock.arn]
      }
    ]
  })
}

