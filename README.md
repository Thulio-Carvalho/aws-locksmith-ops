
[![Terraform](https://img.shields.io/badge/Terraform-1.5.6+-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-OIDC-blue?logo=githubactions)](./.github/workflows/bootstrap.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-000000.svg)](LICENSE)

# AWS Locksmith Ops

A secure, reusable Terraform “bootstrap” for remote state management using:

- **AWS S3** for state storage  
- **DynamoDB** for state locking  
- **GitHub Actions** with **OIDC** (no long-lived AWS keys)

---

## Table of Contents

1. [Introduction](#introduction)  
2. [Architecture](#architecture)  
3. [Prerequisites](#prerequisites)  
4. [Directory Layout](#directory-layout)  
5. [Local Bootstrap](#local-bootstrap)  
6. [CI/CD Integration](#cicd-integration)  
7. [Variables & Defaults](#variables--defaults)  
8. [Secrets](#secrets)  
9. [Contributing](#contributing)  
10. [License](#license)  

---

## Introduction

This repo shows how to get your Terraform remote-state environment up and running with a single local command, then hand over control to GitHub Actions using AWS OIDC. It’s ideal for:

- Kickstarting GitOps (but adding some drift remediation later would be cool!)  
- Labs and proofs of concept  
- Teams that want zero-secret CI/CD  

---

## Architecture

```text
+---------------------------+
| GitHub Actions (CI)       |
| • OIDC JWT                |
| • Checkout & Setup        |
+-------------+-------------+
              |
              | sts:AssumeRoleWithWebIdentity
              v
+-------------+-------------+
| IAM Role: terraform-      |
|       backend-gha         |
+-------------+-------------+
              |
      +-------+-------+
      |               |
      v               v
+-------------+  +-------------+
|   S3        |  |  DynamoDB   |
|   Backend   |  |  Locking    |
| (state file)|  | (lock table)|
+-------------+  +-------------+
```

---

## Prerequisites

- Terraform v1.5.6 or later  
- AWS account with administrative access (for initial bootstrap)  
- AWS CLI or SSO configured locally  
- A GitHub repo
- GitHub Actions enabled  

---

## Directory Layout

```text
.
├── main.tf                  # resource definitions
├── provider.tf              # AWS provider & required version
├── variables.tf             # all inputs declared
├── outputs.tf               # useful resource ARNs/URLs
├── README.md                # this file
└── .github/
    └── workflows/
        └── bootstrap.yml    # GitHub Actions bootstrap pipeline
```

---

## Local Bootstrap

1. **Clone and enter** your repo:
   ```bash
   git clone https://github.com/<YOU>/<REPO>.git
   cd <REPO>
   ```
2. **Authenticate** to AWS:
   - **SSO**  
     ```bash
     aws configure sso --profile terraform-admin
     aws sso login --profile terraform-admin
     export AWS_PROFILE=terraform-admin
     ```
   - **Or** environment variables:
     ```bash
     export AWS_ACCESS_KEY_ID=AKIA…
     export AWS_SECRET_ACCESS_KEY=…
     export AWS_DEFAULT_REGION=us-east-1
     ```
3. **Initialize** Terraform with your backend settings:
   ```bash
   terraform init \
     -backend-config="bucket=<YOUR_BUCKET>" \
     -backend-config="key=bootstrap/terraform.tfstate" \
     -backend-config="region=us-east-1" \
     -backend-config="encrypt=true" \
     -backend-config="dynamodb_table=<YOUR_LOCK_TABLE>"
   ```
4. **Set required vars**:
   ```bash
   export TF_VAR_bucket_name=<YOUR_BUCKET>
   export TF_VAR_lock_table=<YOUR_TABLE>
   export TF_VAR_github_owner=<YOUR_ORG_OR_USER>
   export TF_VAR_github_repo=<REPO_NAME>
   ```
5. **Apply** to create all resources and migrate state:
   ```bash
   terraform apply -auto-approve
   ```

---

## CI/CD Integration

1. **Push** your code (including an empty `backend "s3" {}` stub).  
2. **Add** these repository secrets under **Settings → Secrets → Actions**:  
   - `GH_TERRAFORM_ROLE_ARN` = IAM Role ARN from local bootstrap  
   - `STATE_BUCKET_NAME` = your S3 bucket name  
   - `LOCK_TABLE_NAME` = your DynamoDB table name  
3. **Inspect** `.github/workflows/bootstrap.yml` to confirm it:  
   - Uses `aws-actions/configure-aws-credentials` with OIDC  
   - Runs `terraform init -reconfigure -backend-config=…`  
   - Runs `terraform validate` and `apply`  
4. **Trigger** on push to `main` or via the “Run workflow” button.  

---

## Variables & Defaults

| Variable                | Description                                  | Default                            |
|-------------------------|----------------------------------------------|------------------------------------|
| `aws_region`            | AWS region                                   | `us-east-1`                        |
| `oidc_provider`         | GitHub OIDC issuer                           | `token.actions.githubusercontent.com` |
| `github_branch_pattern` | Branch patterns for OIDC trust policy        | `*`                                |
| **Required**            |                                              |                                    |
| `bucket_name`           | S3 bucket for Terraform state                | *no default*                       |
| `lock_table`            | DynamoDB table for state locking             | *no default*                       |
| `github_owner`          | GitHub org or user owning this repo          | *no default*                       |
| `github_repo`           | GitHub repository name                       | *no default*                       |

---

## Secrets

| Name                      | Purpose                                         |
|---------------------------|-------------------------------------------------|
| `GH_TERRAFORM_ROLE_ARN`   | ARN of the OIDC-assumed IAM role                |
| `STATE_BUCKET_NAME`       | S3 bucket name for remote state                 |
| `LOCK_TABLE_NAME`         | DynamoDB table name for state locking           |

---

## Contributing

1. Fork the repo  
2. Create a feature branch (`git checkout -b feature/…`)  
3. Make your changes & `terraform fmt`  
4. Submit a pull request  

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
