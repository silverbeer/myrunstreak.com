# GitHub Actions CI/CD Setup

This document explains how to set up and use the GitHub Actions workflows for MyRunStreak.com.

## 📚 Table of Contents

1. [Overview](#overview)
2. [Workflows](#workflows)
3. [AWS OIDC Setup](#aws-oidc-setup)
4. [GitHub Secrets Configuration](#github-secrets-configuration)
5. [First Deployment](#first-deployment)
6. [Workflow Triggers](#workflow-triggers)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Overview

We use GitHub Actions for **automated CI/CD**:

- **Terraform Plan** - Preview infrastructure changes on PRs
- **Terraform Apply** - Deploy infrastructure when merged to main
- **Lambda Deploy** - Deploy code changes independently

**Why separate Terraform and Lambda?**
- Code changes are frequent (daily/weekly)
- Infrastructure changes are rare (monthly)
- Faster deployments (no Terraform overhead)
- Can rollback code without touching infrastructure

---

## Workflows

### 1. Terraform Plan (`.github/workflows/terraform-plan.yml`)

**Triggers:**
- Pull requests that modify `terraform/**`
- Manual dispatch

**What it does:**
1. Checks out code
2. Authenticates with AWS (OIDC)
3. Runs `terraform fmt -check`
4. Runs `terraform init`
5. Runs `terraform validate`
6. Runs `terraform plan`
7. Posts plan as PR comment

**Why this matters:**
- See infrastructure changes before merging
- Catch errors early
- Review changes as a team

### 2. Terraform Apply (`.github/workflows/terraform-apply.yml`)

**Triggers:**
- Push to `main` branch (after PR merge)
- Only if `terraform/**` changed
- Manual dispatch (with confirmation)

**What it does:**
1. Runs `terraform plan` (safety check)
2. Runs `terraform apply -auto-approve`
3. Captures outputs
4. Posts deployment summary

**Safety features:**
- Auto-approve only after PR review
- Always plans before applying
- Manual dispatch requires typing "apply"
- Can enable environment protection rules

### 3. Lambda Deploy (`.github/workflows/lambda-deploy.yml`)

**Triggers:**
- Push to `main` branch
- Only if `src/**`, `pyproject.toml`, or `uv.lock` changed
- Manual dispatch

**What it does:**
1. Installs UV and dependencies
2. Creates Lambda package (code + deps)
3. Creates deployment ZIP
4. Updates Lambda function code
5. Runs smoke test
6. Posts deployment summary

---

## AWS OIDC Setup

GitHub Actions uses **OpenID Connect (OIDC)** to authenticate with AWS. This is more secure than storing AWS access keys as secrets.

### Why OIDC?

**Traditional approach (❌ Not Recommended):**
```
AWS Access Key + Secret Key → Stored as GitHub Secrets
├─ Long-lived credentials
├─ Manual rotation required
├─ Risk if compromised
└─ Audit trail is unclear
```

**OIDC approach (✅ Recommended):**
```
GitHub generates JWT token → AWS validates → Temporary credentials
├─ Short-lived credentials (1 hour)
├─ No secrets to rotate
├─ Automatic expiration
└─ Clear audit trail in CloudTrail
```

### Step 1: Create IAM OIDC Identity Provider

This tells AWS to trust GitHub as an identity provider.

```bash
# Get your GitHub repository (format: organization/repo)
GITHUB_REPO="silverbeer/myrunstreak.com"

# Create OIDC provider (only needed once per AWS account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**What this does:**
- Registers GitHub as a trusted identity provider
- AWS will accept JWTs from GitHub Actions
- `thumbprint` is GitHub's certificate fingerprint

### Step 2: Create IAM Role for Terraform

Create a role that GitHub Actions can assume for Terraform operations.

```bash
# Create trust policy
cat > terraform-role-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:*"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name GitHubActions-Terraform \
  --assume-role-policy-document file://terraform-role-trust-policy.json \
  --description "Role for GitHub Actions to manage Terraform infrastructure"

# Attach policies (adjust permissions as needed)
aws iam attach-role-policy \
  --role-name GitHubActions-Terraform \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# Note: PowerUserAccess is broad. In production, use a custom policy with least privilege.
```

**Trust Policy Explained:**
- `Federated`: The OIDC provider (GitHub)
- `Action`: AssumeRoleWithWebIdentity (OIDC-specific)
- `Condition`: Only allow tokens from your specific repository

### Step 3: Create IAM Role for Lambda Deployment

Separate role for Lambda deployments (narrower permissions).

```bash
# Create trust policy (same structure, different role name)
cat > lambda-role-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:*"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name GitHubActions-LambdaDeploy \
  --assume-role-policy-document file://lambda-role-trust-policy.json \
  --description "Role for GitHub Actions to deploy Lambda functions"

# Create inline policy for Lambda-specific permissions
cat > lambda-deploy-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaDeployment",
      "Effect": "Allow",
      "Action": [
        "lambda:UpdateFunctionCode",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:PublishVersion",
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:us-east-2:*:function:myrunstreak-*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name GitHubActions-LambdaDeploy \
  --policy-name LambdaDeployPolicy \
  --policy-document file://lambda-deploy-policy.json
```

### Step 4: Get Role ARNs

Save these ARNs - you'll need them for GitHub Secrets:

```bash
# Terraform role ARN
aws iam get-role \
  --role-name GitHubActions-Terraform \
  --query 'Role.Arn' \
  --output text

# Lambda deploy role ARN
aws iam get-role \
  --role-name GitHubActions-LambdaDeploy \
  --query 'Role.Arn' \
  --output text
```

---

## GitHub Secrets Configuration

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

### Required Secrets

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AWS_TERRAFORM_ROLE_ARN` | IAM role for Terraform | Output from Step 4 above |
| `AWS_LAMBDA_DEPLOY_ROLE_ARN` | IAM role for Lambda | Output from Step 4 above |
| `SMASHRUN_CLIENT_ID` | SmashRun OAuth client ID | https://api.smashrun.com/register |
| `SMASHRUN_CLIENT_SECRET` | SmashRun OAuth client secret | https://api.smashrun.com/register |
| `SMASHRUN_ACCESS_TOKEN` | SmashRun OAuth access token | From OAuth flow |
| `SMASHRUN_REFRESH_TOKEN` | SmashRun OAuth refresh token | From OAuth flow |
| `API_KEY_PERSONAL` | API Gateway API key | Generate: `python -c "import secrets; print(secrets.token_urlsafe(32))"` |

### Adding Secrets via GitHub CLI

```bash
# Install GitHub CLI if needed
# https://cli.github.com/

# Authenticate
gh auth login

# Add secrets
gh secret set AWS_TERRAFORM_ROLE_ARN --body "arn:aws:iam::123456789012:role/GitHubActions-Terraform"
gh secret set AWS_LAMBDA_DEPLOY_ROLE_ARN --body "arn:aws:iam::123456789012:role/GitHubActions-LambdaDeploy"
gh secret set SMASHRUN_CLIENT_ID --body "your-client-id"
gh secret set SMASHRUN_CLIENT_SECRET --body "your-client-secret"
gh secret set SMASHRUN_ACCESS_TOKEN --body "your-access-token"
gh secret set SMASHRUN_REFRESH_TOKEN --body "your-refresh-token"
gh secret set API_KEY_PERSONAL --body "$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
```

---

## First Deployment

### Prerequisites

1. ✅ AWS OIDC provider created
2. ✅ IAM roles created
3. ✅ GitHub secrets configured
4. ✅ Terraform bootstrap completed (S3 backend exists)

### Deployment Steps

#### Step 1: Create Infrastructure Branch

```bash
git checkout -b infra/initial-deployment
```

#### Step 2: Verify Terraform Configuration

```bash
cd terraform/environments/dev

# Check formatting
terraform fmt -check -recursive

# Initialize
terraform init

# Validate
terraform validate
```

#### Step 3: Create Pull Request

```bash
git add -A
git commit -m "feat: initial AWS infrastructure deployment"
git push -u origin infra/initial-deployment

# Create PR via GitHub CLI
gh pr create --title "Initial AWS Infrastructure Deployment" \
             --body "Deploy Lambda function, API Gateway, and supporting infrastructure"
```

#### Step 4: Review Terraform Plan

GitHub Actions will automatically:
1. Run `terraform plan`
2. Post plan as PR comment
3. Show what will be created

**Review the plan carefully!**
- Check resources being created
- Verify no unexpected changes
- Ensure costs are acceptable

#### Step 5: Merge and Deploy

Once approved:
```bash
gh pr merge --merge
```

GitHub Actions will automatically:
1. Run `terraform apply`
2. Deploy infrastructure
3. Post deployment summary with URLs

#### Step 6: Deploy Lambda Code

After infrastructure is deployed:

```bash
# Trigger Lambda deployment (automatically runs on main branch)
git checkout main
git pull

# Make a small change to trigger deployment (if needed)
touch src/.trigger
git add src/.trigger
git commit -m "trigger: initial Lambda deployment"
git push
```

#### Step 7: Test Deployment

```bash
# Get outputs
cd terraform/environments/dev
terraform output

# Test health endpoint
HEALTH_URL=$(terraform output -raw api_health_endpoint)
curl $HEALTH_URL

# Upload initial database
S3_BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 cp data/runs.duckdb s3://$S3_BUCKET/runs.duckdb

# Test sync endpoint
API_KEY=$(terraform output -raw api_key_value)
SYNC_URL=$(terraform output -raw api_sync_endpoint)
curl -X POST $SYNC_URL -H "x-api-key: $API_KEY"

# View Lambda logs
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_NAME --follow
```

---

## Workflow Triggers

### Terraform Plan

**Automatic triggers:**
```
Pull Request → terraform/** changes → terraform-plan.yml runs
```

**Manual trigger:**
```bash
gh workflow run terraform-plan.yml
```

### Terraform Apply

**Automatic triggers:**
```
PR Merged → main branch → terraform/** changes → terraform-apply.yml runs
```

**Manual trigger (USE WITH CAUTION):**
```bash
gh workflow run terraform-apply.yml -f confirm=apply
```

### Lambda Deploy

**Automatic triggers:**
```
PR Merged → main branch → src/** changes → lambda-deploy.yml runs
```

**Manual trigger:**
```bash
gh workflow run lambda-deploy.yml
```

---

## Troubleshooting

### Workflow Fails with "Error assuming role"

**Problem:** GitHub Actions can't assume the AWS IAM role

**Solutions:**
1. Check role ARN in GitHub Secrets is correct
2. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```
3. Check role trust policy allows your repository:
   ```bash
   aws iam get-role --role-name GitHubActions-Terraform --query 'Role.AssumeRolePolicyDocument'
   ```
4. Ensure repository name matches (case-sensitive!)

### Terraform State Lock Error

**Problem:** "Error acquiring state lock"

**Cause:** Previous workflow didn't release lock (crashed/cancelled)

**Solution:**
```bash
cd terraform/environments/dev
terraform force-unlock <LOCK_ID>
```

**Prevention:**
- Don't cancel running workflows
- Let workflows complete naturally

### Lambda Package Too Large

**Problem:** "Unzipped size must be smaller than 262144000 bytes"

**Solutions:**
1. Remove unnecessary dependencies from `pyproject.toml`
2. Use Lambda layers for large dependencies
3. Exclude test files and documentation

### Secret Not Found

**Problem:** Workflow can't read GitHub Secret

**Solutions:**
1. Verify secret exists: GitHub repo → Settings → Secrets
2. Check secret name matches exactly (case-sensitive)
3. Ensure secret is a "repository secret" not "environment secret"

---

## Best Practices

### 1. Always Review Plans

Never merge a PR without reviewing the Terraform plan:
- ✅ Read the plan comment on PR
- ✅ Understand what will change
- ✅ Verify expected resources only
- ❌ Don't blindly merge

### 2. Use Branch Protection

Configure branch protection for `main`:
```
Settings → Branches → Add rule
├─ Require pull request reviews (1+)
├─ Require status checks (terraform-plan)
├─ Require conversation resolution
└─ Include administrators
```

### 3. Test in Feature Branches

Always test in a feature branch first:
```bash
git checkout -b feature/add-monitoring
# Make changes
git push
# Create PR
# Review plan
# Merge when ready
```

### 4. Monitor Workflows

Watch workflows run:
```bash
# Via CLI
gh run watch

# Via web
https://github.com/your-org/your-repo/actions
```

### 5. Use Workflow Concurrency

Prevent concurrent deployments:
```yaml
concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false
```

This ensures only one Terraform run at a time.

### 6. Enable CODEOWNERS

Create `.github/CODEOWNERS`:
```
terraform/** @your-team
.github/workflows/** @your-team
```

Requires team approval for infrastructure changes.

### 7. Use Environment Secrets (Optional)

For production deployments, use GitHub Environments:
```yaml
environment:
  name: production
  url: https://myrunstreak.com
```

Benefits:
- Require manual approval before deploy
- Separate secrets per environment
- Deployment protection rules
- Deployment history

---

## Summary

You now have:

✅ **3 automated workflows:**
- Terraform Plan (on PRs)
- Terraform Apply (on merge)
- Lambda Deploy (on code changes)

✅ **Secure authentication:**
- AWS OIDC (no long-lived credentials)
- Temporary credentials per workflow
- Audit trail in CloudTrail

✅ **Full CI/CD pipeline:**
- Preview changes before merge
- Automatic deployments
- Smoke tests after deploy
- Deployment summaries

**Next:** Make your first deployment following the steps above! 🚀
