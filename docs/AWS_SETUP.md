# AWS Account Setup Guide

## 📚 Table of Contents

1. [Overview](#overview)
2. [Current State: Root User Only](#current-state-root-user-only)
3. [Why Not Use Root User?](#why-not-use-root-user)
4. [Step-by-Step AWS Setup](#step-by-step-aws-setup)
5. [Install and Configure AWS CLI](#install-and-configure-aws-cli)
6. [Verify Setup](#verify-setup)
7. [Optional: Enable MFA](#optional-enable-mfa)
8. [Cost Control](#cost-control)
9. [Ready for Bootstrap](#ready-for-bootstrap)

---

## Overview

You have a brand new AWS account with only a **root user**. Before deploying infrastructure with Terraform, you need to:

1. ✅ Create an IAM user for daily operations (don't use root!)
2. ✅ Give that IAM user administrator access
3. ✅ Create access keys for programmatic access
4. ✅ Install and configure AWS CLI locally
5. ✅ Test that everything works

**Time required**: ~15 minutes

**Cost**: $0 (all free tier eligible)

---

## Current State: Root User Only

```
Your AWS Account
└─ Root User (you@email.com)
   ├─ Full access to everything
   ├─ Can't be restricted
   └─ ⚠️ Should NOT be used for daily work
```

**Problem**: Root user has unrestricted access to everything, including billing. If credentials leak, attacker can:
- Delete all resources
- Rack up huge bills
- Access billing information
- Change account settings

---

## Why Not Use Root User?

AWS best practices say **NEVER use root user for daily operations**:

```
❌ Root User:
├─ Unrestricted access (can't limit permissions)
├─ Can access billing and account settings
├─ If compromised = total account takeover
├─ Can't audit specific actions easily
└─ No way to restrict what it can do

✅ IAM User:
├─ Can grant specific permissions only
├─ Can revoke access without closing account
├─ Can enable MFA (multi-factor auth)
├─ Each person/service gets their own credentials
└─ Clear audit trail of who did what
```

**Analogy**: Root user is like having master keys to a building. IAM users are like giving out keycards with specific access levels.

---

## Step-by-Step AWS Setup

### Step 1: Secure Your Root User

Before creating IAM user, secure the root account:

1. **Enable MFA on root user** (HIGHLY RECOMMENDED)
   - Log into AWS Console as root: https://console.aws.amazon.com/
   - Click your account name (top right) → "Security credentials"
   - Under "Multi-factor authentication (MFA)" → "Assign MFA device"
   - Choose "Virtual MFA device" (use Google Authenticator, Authy, etc.)
   - Follow the wizard to scan QR code

2. **Save root user credentials in password manager**
   - You'll rarely need root access
   - But when you do, you NEED these credentials
   - Store securely (1Password, LastPass, Bitwarden, etc.)

### Step 2: Create IAM User for Daily Operations

Log into AWS Console as root user, then:

1. **Navigate to IAM**
   - Go to: https://console.aws.amazon.com/iam/
   - Or search "IAM" in AWS Console search bar

2. **Create IAM User**
   - Click "Users" (left sidebar)
   - Click "Create user" button
   - User name: `terraform-admin` (or your name, like `john-admin`)
   - ✅ Check "Provide user access to the AWS Management Console"
   - Select "I want to create an IAM user"
   - Custom password: Create a strong password (save in password manager!)
   - ❌ Uncheck "Users must create a new password at next sign-in"
   - Click "Next"

3. **Set Permissions**
   - Select "Attach policies directly"
   - Search for: `AdministratorAccess`
   - ✅ Check the box next to "AdministratorAccess"
   - Click "Next"
   - Click "Create user"

**What is AdministratorAccess?**
- Full access to all AWS services (except billing by default)
- Can create/delete any resource
- Needed for Terraform to provision infrastructure
- Can be restricted later for production

4. **Save IAM User Sign-In URL**
   - After creating user, AWS shows a sign-in URL like:
     ```
     https://123456789012.signin.aws.amazon.com/console
     ```
   - **SAVE THIS URL** in your password manager
   - This is how you'll log in as IAM user (not root)

### Step 3: Create Access Keys for AWS CLI

Now create programmatic access credentials:

1. **Navigate to IAM User**
   - Still in IAM console: https://console.aws.amazon.com/iam/
   - Click "Users" → Click on `terraform-admin` (the user you just created)

2. **Create Access Key**
   - Click "Security credentials" tab
   - Scroll down to "Access keys" section
   - Click "Create access key"

3. **Select Use Case**
   - Choose "Command Line Interface (CLI)"
   - ✅ Check "I understand the above recommendation"
   - Click "Next"

4. **Add Description (Optional)**
   - Description tag: "Local development - MyRunStreak project"
   - Click "Create access key"

5. **SAVE CREDENTIALS IMMEDIATELY**
   - AWS shows:
     - Access key ID: `AKIAIOSFODNN7EXAMPLE`
     - Secret access key: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`

   **⚠️ CRITICAL**: You can ONLY see the secret access key ONCE!

   - Click "Download .csv file" (saves credentials locally)
   - **OR** copy both values to password manager
   - Store these like passwords - anyone with these can control your AWS account!

6. **Click "Done"**

### Step 4: Log Out of Root User

1. Click your account name (top right) → "Sign out"
2. **From now on, use your IAM user for everything**
3. Bookmark your IAM sign-in URL: `https://123456789012.signin.aws.amazon.com/console`

---

## Install and Configure AWS CLI

Now set up AWS CLI on your local machine to use these credentials.

### Step 1: Install AWS CLI

**macOS** (using Homebrew):
```bash
brew install awscli
```

**macOS** (official installer):
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

**Linux**:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows**:
- Download: https://awscli.amazonaws.com/AWSCLIV2.msi
- Run installer

**Verify installation**:
```bash
aws --version
# Expected output: aws-cli/2.x.x Python/3.x.x Darwin/25.x.x botocore/2.x.x
```

### Step 2: Configure AWS CLI

Run the configuration wizard:

```bash
aws configure
```

**You'll be prompted for**:

1. **AWS Access Key ID**: `AKIAIOSFODNN7EXAMPLE` (from Step 3 above)
2. **AWS Secret Access Key**: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` (from Step 3 above)
3. **Default region name**: `us-east-2` (Ohio - matches our Terraform config)
4. **Default output format**: `json` (or press Enter for default)

**Example session**:
```bash
$ aws configure
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-2
Default output format [None]: json
```

**What this does**:
- Creates `~/.aws/credentials` file with your access keys
- Creates `~/.aws/config` file with region and output settings
- These files are used by AWS CLI and Terraform

**View configuration**:
```bash
# View credentials (sensitive!)
cat ~/.aws/credentials
# Output:
# [default]
# aws_access_key_id = AKIAIOSFODNN7EXAMPLE
# aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# View config
cat ~/.aws/config
# Output:
# [default]
# region = us-east-2
# output = json
```

---

## Verify Setup

Test that everything works:

### Test 1: Get Caller Identity

```bash
aws sts get-caller-identity
```

**Expected output**:
```json
{
    "UserId": "AIDAI7X5HAMPLE47B2QXO",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/terraform-admin"
}
```

**What to check**:
- ✅ `Account`: Your 12-digit AWS account ID
- ✅ `Arn`: Shows `user/terraform-admin` (your IAM user, NOT root)
- ✅ No errors

**If you see an error**:
- Check access keys are correct: `cat ~/.aws/credentials`
- Verify region is set: `cat ~/.aws/config`

### Test 2: List S3 Buckets

```bash
aws s3 ls
```

**Expected output**:
- Empty (no buckets yet) - this is fine!
- Or lists any existing buckets

**If you see "Access Denied"**:
- IAM user doesn't have AdministratorAccess policy
- Go back to IAM Console → Users → terraform-admin → Permissions
- Attach "AdministratorAccess" policy

### Test 3: Get Account ID (for Bootstrap)

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your AWS Account ID: $AWS_ACCOUNT_ID"
```

**Expected output**:
```
Your AWS Account ID: 123456789012
```

**Save this number** - you'll need it for Terraform bootstrap!

---

## Optional: Enable MFA (Highly Recommended)

Multi-factor authentication adds extra security layer.

### Enable MFA for IAM User

1. **Log into AWS Console** as IAM user (not root)
   - URL: `https://123456789012.signin.aws.amazon.com/console`
   - Username: `terraform-admin`
   - Password: (the one you set)

2. **Navigate to Security Credentials**
   - Click your username (top right) → "Security credentials"
   - Or go to: https://console.aws.amazon.com/iam/home#/security_credentials

3. **Assign MFA Device**
   - Under "Multi-factor authentication (MFA)" → "Assign MFA device"
   - Device name: `my-phone` (or any name)
   - MFA device: "Authenticator app"
   - Scan QR code with Google Authenticator, Authy, or similar
   - Enter two consecutive MFA codes
   - Click "Add MFA"

**Benefits**:
- Even if access keys leak, attacker can't use AWS Console
- Required for some sensitive operations
- Best practice for production

**Note**: MFA is NOT required for AWS CLI/Terraform by default, but adds Console protection.

---

## Cost Control

Set up billing alerts to avoid surprises:

### Enable Billing Alerts

1. **Log into AWS Console** as IAM user

2. **Navigate to Billing**
   - Click your account name (top right) → "Billing and Cost Management"
   - Or go to: https://console.aws.amazon.com/billing/

3. **Create Budget**
   - Left sidebar → "Budgets" → "Create budget"
   - Choose "Use a template"
   - Select "Zero spend budget" (alerts on ANY charge)
   - Budget name: "MyRunStreak-Alert"
   - Email: your-email@example.com
   - Click "Create budget"

**What this does**:
- Sends email if monthly charges exceed $0.01
- Forecasts if you'll exceed budget
- Helps catch unexpected charges early

### Expected Monthly Costs

For this project:
```
Bootstrap Infrastructure:
├─ S3 bucket: ~$0.001/month
└─ DynamoDB table: ~$0.00/month (free tier)

Main Infrastructure (after deployment):
├─ Lambda: ~$0.00/month (free tier: 1M requests)
├─ API Gateway: ~$0.35/month (10K requests)
├─ S3 database: ~$0.02/month (100MB storage)
├─ EventBridge: ~$0.00/month (1 daily trigger)
├─ Secrets Manager: ~$0.40/month (2 secrets)
└─ CloudWatch: ~$0.08/month (logs, alarms)

Total: ~$0.85/month
```

**Free tier eligible** (first 12 months):
- Lambda: 1M requests/month free
- S3: 5GB storage free
- DynamoDB: 25GB storage free

---

## Ready for Bootstrap!

You're now ready to run Terraform bootstrap! Here's what you have:

✅ **IAM user created** (`terraform-admin`)
✅ **AdministratorAccess policy** attached
✅ **Access keys created** and saved
✅ **AWS CLI installed** and configured
✅ **Credentials verified** with `aws sts get-caller-identity`
✅ **Account ID captured** for bootstrap
✅ **Billing alerts set up** (optional but recommended)

---

## What's Next?

### 1. Run Bootstrap (Create Remote State Backend)

```bash
cd terraform/bootstrap

# Use the account ID from earlier
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your account ID

terraform init
terraform plan
terraform apply
```

📖 **Detailed guide**: [TERRAFORM_BOOTSTRAP.md](./TERRAFORM_BOOTSTRAP.md)

### 2. Set Up GitHub Actions (CI/CD)

After bootstrap, configure GitHub Actions for automated deployments:

📖 **Complete guide**: [GITHUB_ACTIONS.md](./GITHUB_ACTIONS.md)

### 3. Deploy Infrastructure

Deploy Lambda, API Gateway, and all AWS resources:

📖 **Architecture overview**: [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## Quick Reference Commands

```bash
# Verify AWS CLI access
aws sts get-caller-identity

# Get your account ID
aws sts get-caller-identity --query Account --output text

# List S3 buckets
aws s3 ls

# Check current region
aws configure get region

# View all AWS CLI configuration
aws configure list

# Test IAM permissions
aws iam list-users
```

---

## Troubleshooting

### "Unable to locate credentials"

**Problem**: AWS CLI can't find credentials

**Solution**:
```bash
# Check credentials file exists
cat ~/.aws/credentials

# If missing, run configuration again
aws configure
```

### "Access Denied" errors

**Problem**: IAM user doesn't have required permissions

**Solution**:
1. Log into AWS Console as IAM user
2. Navigate to IAM → Users → terraform-admin
3. Click "Permissions" tab
4. Verify "AdministratorAccess" policy is attached
5. If not, click "Add permissions" → "Attach policies directly" → Select "AdministratorAccess"

### Wrong region

**Problem**: Resources created in wrong AWS region

**Solution**:
```bash
# Check current region
aws configure get region

# Change region
aws configure set region us-east-2

# Verify
cat ~/.aws/config
```

### Can't remember IAM sign-in URL

**Problem**: Lost the IAM user sign-in URL

**Solution**:
Your sign-in URL is always: `https://ACCOUNT_ID.signin.aws.amazon.com/console`

```bash
# Get your account ID
aws sts get-caller-identity --query Account --output text
# Output: 123456789012

# Your sign-in URL
# https://123456789012.signin.aws.amazon.com/console
```

Or set an account alias:
1. Log in as root user
2. IAM Dashboard → "Create account alias"
3. Alias: `myrunstreak-aws`
4. Sign-in URL becomes: `https://myrunstreak-aws.signin.aws.amazon.com/console`

---

## Security Best Practices Summary

✅ **DO**:
- Use IAM users for daily operations
- Enable MFA on root user
- Enable MFA on IAM admin users
- Store credentials in password manager
- Rotate access keys regularly (every 90 days)
- Use billing alerts
- Review CloudTrail logs periodically

❌ **DON'T**:
- Use root user for daily work
- Share IAM user credentials
- Commit AWS credentials to git
- Create access keys without MFA
- Use same credentials across multiple people
- Ignore billing alerts

---

## Summary

You've completed AWS account setup! You now have:

1. ✅ Secured root user (MFA recommended)
2. ✅ Created IAM user for Terraform operations
3. ✅ Generated access keys for programmatic access
4. ✅ Installed and configured AWS CLI
5. ✅ Verified everything works
6. ✅ Set up billing alerts (optional)

**Your AWS setup**:
```
Your AWS Account (123456789012)
├─ Root User (secured, rarely used)
│  └─ MFA enabled ✅
│
└─ IAM User: terraform-admin
   ├─ Console access ✅
   ├─ Programmatic access (access keys) ✅
   ├─ AdministratorAccess policy ✅
   └─ MFA enabled (recommended) ✅
```

**Next step**: Run Terraform bootstrap to create remote state backend!

📖 [TERRAFORM_BOOTSTRAP.md](./TERRAFORM_BOOTSTRAP.md)
