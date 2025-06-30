# AWS Locksmith Ops 

This repository demonstrates a secure Terraform bootstrap for remote state management using AWS S3 + DynamoDB locks, and GitHub Actions with OIDC authentication. It’s meant as a quick way to setup tf gitops and let CI/CD manage your infrastructure state.

## 🔍 Overview

* **Local Bootstrap**: Perform a one-time setup locally (or in any interactive environment) to create:

  * An S3 bucket for remote state
  * A DynamoDB table for state locks
  * An OIDC provider registration
  * An IAM role for GitHub Actions to assume

* **CI/CD Execution**: Push changes to `main` (or trigger manually) and let GitHub Actions:

  1. Obtain temporary AWS credentials via OIDC
  2. Initialize Terraform against the existing remote state
  3. Apply any updates to the infrastructure

## Prerequisites

* [Terraform v1.5.6+](https://www.terraform.io/downloads.html)
* An AWS account with administrative access (for the one-time bootstrap)
* AWS SSO or AWS CLI credentials configured locally
* A public GitHub repository to host this code
* GitHub Actions enabled for your repo

## Local Bootstrap

1. **Clone this repo**

   ```bash
   git clone https://github.com/<YOUR_USER>/<YOUR_REPO>.git
   cd <YOUR_REPO>
   ```

2. **Authenticate to AWS**

   * **SSO**:

     ```bash
     aws configure sso --profile terraform-admin
     aws sso login --profile terraform-admin
     export AWS_PROFILE=terraform-admin
     ```
   * **Or** export static keys:

     ```bash
     export AWS_ACCESS_KEY_ID=AKIA...
     export AWS_SECRET_ACCESS_KEY=...
     export AWS_DEFAULT_REGION=us-east-1
     ```

3. **Initialize Terraform with backend config**

   ```bash
   terraform init \
     -backend-config="bucket=<YOUR_BUCKET_NAME>" \
     -backend-config="key=bootstrap/terraform.tfstate" \
     -backend-config="region=us-east-1" \
     -backend-config="encrypt=true" \
     -backend-config="dynamodb_table=<YOUR_LOCK_TABLE>"
   ```

4. **Provide required variables**

   ```bash
   export TF_VAR_bucket_name=<YOUR_BUCKET_NAME>
   export TF_VAR_lock_table=<YOUR_LOCK_TABLE>
   export TF_VAR_github_owner=<YOUR_GITHUB_USER_OR_ORG>
   export TF_VAR_github_repo=<REPO_NAME>
   ```

5. **Apply**

   ```bash
   terraform apply
   ```

6. **Migrate state** to remote backend:

   ```bash
   terraform init
   terraform apply
   ```

## CI/CD Setup

1. **Push** your code (including `backend.tf`) to GitHub.
2. **Add repository secrets** (in Settings → Secrets → Actions):

   * `GH_TERRAFORM_ROLE_ARN`: ARN of the IAM role created in bootstrap.
   * `STATE_BUCKET_NAME`: your S3 bucket name.
   * `LOCK_TABLE_NAME`: your DynamoDB table name.
3. **Review** `.github/workflows/bootstrap.yml` – no hard-coded creds, uses OIDC.
4. **Enable** Actions if needed. Push or manually trigger the workflow.

## 🔑 Variables & Defaults

| Variable                      | Description                          | Default                               |
| ----------------------------- | ------------------------------------ | ------------------------------------- |
| `aws_region`                  | AWS region                           | `us-east-1`                           |
| `oidc_provider`               | GitHub OIDC host                     | `token.actions.githubusercontent.com` |
| `github_branch_pattern`       | Branch pattern for OIDC trust        | `*`                                   |
| **Required**                  |                                      |                                       |
| `bucket_name`                 | S3 bucket for Terraform state        | *no default*                          |
| `lock_table`                  | DynamoDB table for state locks       | *no default*                          |
| `github_owner`, `github_repo` | GitHub owner and repo for OIDC trust | *no default*                          |

