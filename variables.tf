variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
  default     = "lucy-infra-tf-state"
}

variable "lock_table" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "lucy-tf-lock"
}

variable "oidc_provider" {
  description = "OIDC host for GitHub Actions"
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "github_owner" {
  description = "GitHub owner (user or org) for OIDC trust"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for OIDC trust"
  type        = string
}

variable "github_branch_pattern" {
  description = "Branch ref pattern for OIDC trust (e.g. refs/heads/main or refs/heads/*)"
  type        = string
  default     = "*"
}

