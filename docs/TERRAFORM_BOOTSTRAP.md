# Terraform Bootstrap Guide

## 📚 Table of Contents

1. [What is Bootstrap?](#what-is-bootstrap)
2. [Why Do We Need It?](#why-do-we-need-it)
3. [What Does Bootstrap Create?](#what-does-bootstrap-create)
4. [Prerequisites](#prerequisites)
5. [Bootstrap Process](#bootstrap-process)
6. [Verification](#verification)
7. [Using Bootstrap with Main Infrastructure](#using-bootstrap-with-main-infrastructure)
8. [Troubleshooting](#troubleshooting)
9. [Important Notes](#important-notes)

---

## What is Bootstrap?

**Bootstrap** is the foundational infrastructure setup that runs **once** before deploying your main Terraform infrastructure. It creates the resources needed for **remote state management** and **state locking**.

Think of it as "Terraform inception" - using Terraform to create the infrastructure that Terraform itself needs to work safely in a team environment.

```
┌─────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT SEQUENCE                       │
└─────────────────────────────────────────────────────────────┘

Step 1: Bootstrap (ONE TIME)
┌──────────────────────────────────┐
│  terraform/bootstrap/            │
│  ├─ Creates S3 bucket            │
│  └─ Creates DynamoDB table       │
└──────────────────────────────────┘
           ↓
Step 2: Main Infrastructure (REPEATABLE)
┌──────────────────────────────────┐
│  terraform/environments/dev/     │
│  ├─ Uses S3 for remote state     │
│  ├─ Uses DynamoDB for locking    │
│  └─ Deploys Lambda, API, etc.    │
└──────────────────────────────────┘
```

---

## Why Do We Need It?

### The Problem: Local State

By default, Terraform stores state in a local file (`terraform.tfstate`):

```
❌ Problems with Local State:
├─ Lost if computer crashes
├─ Can't share with team
├─ No locking (concurrent changes cause corruption)
├─ Sensitive data stored unencrypted
└─ CI/CD workflows can't access it
```

### The Solution: Remote State with Locking

Bootstrap creates infrastructure for **remote state backend**:

```
✅ Benefits of Remote State:
├─ Stored in S3 (durable, versioned, encrypted)
├─ Shared across team and CI/CD
├─ DynamoDB locking prevents concurrent modifications
├─ Encrypted at rest (AES-256)
└─ Version history (can rollback state)
```

---

## What Does Bootstrap Create?

### 1. S3 Bucket for State Storage

**Resource**: `aws_s3_bucket.terraform_state`

**Purpose**: Stores `terraform.tfstate` file remotely

**Configuration**:
- **Versioning**: Enabled (keeps history of state changes)
- **Encryption**: AES-256 (state files encrypted at rest)
- **Public Access**: Blocked (nobody can access state publicly)
- **Lifecycle**: `prevent_destroy = true` (can't accidentally delete)

**Bucket Name Format**: `myrunstreak-terraform-state-{AWS_ACCOUNT_ID}`

Example: `myrunstreak-terraform-state-123456789012`

**Why include account ID?**
- S3 bucket names are globally unique across ALL AWS accounts
- Including account ID prevents naming conflicts

### 2. DynamoDB Table for State Locking

**Resource**: `aws_dynamodb_table.terraform_locks`

**Purpose**: Prevents concurrent Terraform operations

**Configuration**:
- **Hash Key**: `LockID` (required by Terraform)
- **Billing**: Pay-per-request (no minimum cost)
- **Lifecycle**: `prevent_destroy = true` (can't accidentally delete)

**Table Name**: `myrunstreak-terraform-locks`

**How Locking Works**:
```
User 1: terraform apply
├─ Acquires lock in DynamoDB
├─ Runs infrastructure changes
└─ Releases lock when done

User 2: terraform apply (at same time)
├─ Tries to acquire lock
├─ Lock already held by User 1
├─ BLOCKS until User 1 finishes
└─ Prevents conflicting changes
```

**Without locking**: Two people running `terraform apply` simultaneously can corrupt state file.

**With locking**: Second operation waits for first to finish.

---

## Prerequisites

Before running bootstrap:

### 0. AWS Account Setup (If Brand New Account)

**If you have a brand new AWS account with only a root user**, complete AWS setup first:

📖 **[AWS_SETUP.md](./AWS_SETUP.md)** - Complete guide to:
- Create IAM user for daily operations (don't use root!)
- Set up AWS CLI with access keys
- Verify everything works

**Skip this if you already have**:
- ✅ IAM user created
- ✅ AWS CLI installed and configured
- ✅ Can run `aws sts get-caller-identity` successfully

### 1. AWS CLI Configured

```bash
# Verify AWS CLI is installed and configured
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-name"
# }
```

**If this fails**: See [AWS_SETUP.md](./AWS_SETUP.md) for complete setup instructions.

### 2. AWS Credentials with Required Permissions

You need permissions to:
- Create S3 buckets
- Create DynamoDB tables
- Configure S3 versioning and encryption

**Option A**: Administrator access (simplest for personal projects)

**Option B**: Custom policy with minimum permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketVersioning",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutEncryptionConfiguration"
      ],
      "Resource": "arn:aws:s3:::myrunstreak-terraform-state-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/myrunstreak-terraform-locks"
    }
  ]
}
```

### 3. Terraform Installed

```bash
terraform --version
# Terraform v1.5.0 or later
```

---

## Bootstrap Process

### Step 1: Get Your AWS Account ID

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your AWS Account ID: $AWS_ACCOUNT_ID"
```

**Example output**: `Your AWS Account ID: 123456789012`

### Step 2: Configure Bootstrap Variables

```bash
cd terraform/bootstrap

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your account ID
# Replace 123456789012 with your actual account ID from Step 1
```

**terraform/bootstrap/terraform.tfvars**:
```hcl
aws_account_id = "123456789012"  # Use YOUR account ID
aws_region     = "us-east-2"
project_name   = "myrunstreak"
```

### Step 3: Initialize Terraform

```bash
# Still in terraform/bootstrap directory
terraform init
```

**What this does**:
- Downloads AWS provider plugin (~100MB)
- Sets up local backend (bootstrap uses local state initially)
- Prepares working directory

**Expected output**:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### Step 4: Review the Plan

```bash
terraform plan
```

**What this does**:
- Shows what resources will be created
- NO changes made yet (read-only preview)

**Expected output**:
```
Terraform will perform the following actions:

  # aws_dynamodb_table.terraform_locks will be created
  + resource "aws_dynamodb_table" "terraform_locks" {
      + name         = "myrunstreak-terraform-locks"
      + billing_mode = "PAY_PER_REQUEST"
      + hash_key     = "LockID"
      ...
    }

  # aws_s3_bucket.terraform_state will be created
  + resource "aws_s3_bucket" "terraform_state" {
      + bucket = "myrunstreak-terraform-state-123456789012"
      ...
    }

  # aws_s3_bucket_versioning.terraform_state will be created
  + resource "aws_s3_bucket_versioning" "terraform_state" {
      ...
    }

Plan: 5 to add, 0 to change, 0 to destroy.
```

**Review checklist**:
- ✅ S3 bucket name includes your account ID
- ✅ DynamoDB table name is `myrunstreak-terraform-locks`
- ✅ Region is `us-east-2` (or your preferred region)
- ✅ No unexpected resources

### Step 5: Apply Bootstrap

```bash
terraform apply
```

**Confirm with**: `yes`

**What this does**:
- Creates S3 bucket with versioning and encryption
- Creates DynamoDB table for locking
- Sets up infrastructure for remote state

**Expected output**:
```
aws_s3_bucket.terraform_state: Creating...
aws_dynamodb_table.terraform_locks: Creating...
aws_s3_bucket.terraform_state: Creation complete after 2s
aws_s3_bucket_versioning.terraform_state: Creating...
aws_s3_bucket_versioning.terraform_state: Creation complete after 1s
aws_dynamodb_table.terraform_locks: Creation complete after 5s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

backend_config = <<EOT
backend "s3" {
  bucket         = "myrunstreak-terraform-state-123456789012"
  key            = "myrunstreak/terraform.tfstate"
  region         = "us-east-2"
  dynamodb_table = "myrunstreak-terraform-locks"
  encrypt        = true
}
EOT

dynamodb_table_name = "myrunstreak-terraform-locks"
state_bucket_name = "myrunstreak-terraform-state-123456789012"
```

**🎉 Bootstrap complete!** Save the `backend_config` output - you'll need it next.

### Step 6: Save Backend Configuration

```bash
# Capture the backend configuration
terraform output -raw backend_config > ../backend-config.txt

# Display it for reference
cat ../backend-config.txt
```

This is the configuration you'll use in the main Terraform infrastructure.

---

## Verification

### Verify S3 Bucket

```bash
# List S3 bucket
aws s3 ls | grep terraform-state

# Expected output:
# 2025-10-31 12:34:56 myrunstreak-terraform-state-123456789012

# Check bucket properties
aws s3api get-bucket-versioning --bucket myrunstreak-terraform-state-123456789012

# Expected output:
# {
#     "Status": "Enabled"
# }
```

### Verify DynamoDB Table

```bash
# Describe table
aws dynamodb describe-table --table-name myrunstreak-terraform-locks --query 'Table.[TableName,TableStatus,BillingModeSummary.BillingMode]' --output table

# Expected output:
# -----------------------------------------------
# |              DescribeTable                  |
# +---------------------------------------------+
# |  myrunstreak-terraform-locks                |
# |  ACTIVE                                     |
# |  PAY_PER_REQUEST                            |
# +---------------------------------------------+
```

### Check AWS Console

**S3 Bucket**:
1. Go to: https://s3.console.aws.amazon.com/s3/buckets
2. Find: `myrunstreak-terraform-state-{YOUR_ACCOUNT_ID}`
3. Verify:
   - ✅ Versioning: Enabled
   - ✅ Encryption: AES-256
   - ✅ Public access: Blocked

**DynamoDB Table**:
1. Go to: https://console.aws.amazon.com/dynamodbv2/home?region=us-east-2#tables
2. Find: `myrunstreak-terraform-locks`
3. Verify:
   - ✅ Status: Active
   - ✅ Partition key: LockID (String)
   - ✅ Billing mode: On-demand

---

## Using Bootstrap with Main Infrastructure

Now that bootstrap is complete, configure the main infrastructure to use remote state.

### Update Main Terraform Backend

The main Terraform configuration at `terraform/environments/dev/main.tf` already has the backend configured:

```hcl
terraform {
  backend "s3" {
    bucket         = "myrunstreak-terraform-state-REPLACE_WITH_ACCOUNT_ID"
    key            = "myrunstreak/dev/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "myrunstreak-terraform-locks"
    encrypt        = true
  }
}
```

**Update the backend configuration**:

```bash
cd terraform/environments/dev

# Edit main.tf and replace REPLACE_WITH_ACCOUNT_ID with your actual account ID
# Or use the backend_config output from bootstrap
```

**Updated backend block** (use YOUR account ID):
```hcl
terraform {
  backend "s3" {
    bucket         = "myrunstreak-terraform-state-123456789012"  # Your bucket
    key            = "myrunstreak/dev/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "myrunstreak-terraform-locks"
    encrypt        = true
  }
}
```

### Initialize Main Infrastructure

```bash
# In terraform/environments/dev
terraform init

# Terraform will configure the S3 backend
# Output:
# Initializing the backend...
# Successfully configured the backend "s3"!
```

**What happens**:
- Terraform connects to S3 bucket
- Creates state file at: `s3://myrunstreak-terraform-state-{ID}/myrunstreak/dev/terraform.tfstate`
- Registers DynamoDB table for locking

### Test State Locking

Open two terminal windows:

**Terminal 1**:
```bash
cd terraform/environments/dev
terraform plan -lock-timeout=10s
# Acquires lock, runs plan
```

**Terminal 2** (while Terminal 1 is running):
```bash
cd terraform/environments/dev
terraform plan -lock-timeout=10s
# Output: "Error acquiring the state lock"
# This is EXPECTED and GOOD - locking works!
```

---

## Troubleshooting

### Error: "BucketAlreadyExists"

**Problem**: S3 bucket name already taken globally

**Solution**: Bucket names include your AWS account ID, which should be unique. If you still get this error, someone else is using the same bucket name pattern.

```bash
# Use a more unique project name
# In terraform.tfvars:
project_name = "myrunstreak-yourname"  # Add your name or random string
```

### Error: "AccessDenied" when creating S3 bucket

**Problem**: AWS credentials don't have permission to create S3 buckets

**Solution**:
```bash
# Check who you're authenticated as
aws sts get-caller-identity

# Verify your IAM user/role has S3 permissions
aws iam get-user-policy --user-name YOUR_USERNAME --policy-name YOUR_POLICY
```

### Error: "ResourceInUseException" on DynamoDB

**Problem**: DynamoDB table already exists

**Solution**:
```bash
# Check if table exists
aws dynamodb describe-table --table-name myrunstreak-terraform-locks

# If it exists and you own it, import it:
cd terraform/bootstrap
terraform import aws_dynamodb_table.terraform_locks myrunstreak-terraform-locks
```

### State File Lost After Bootstrap

**Problem**: Bootstrap state file deleted or lost

**Danger**: If you lose `terraform/bootstrap/terraform.tfstate`, Terraform doesn't know bootstrap resources exist.

**Solution**: Import existing resources
```bash
cd terraform/bootstrap

# Import S3 bucket
terraform import aws_s3_bucket.terraform_state myrunstreak-terraform-state-123456789012

# Import DynamoDB table
terraform import aws_dynamodb_table.terraform_locks myrunstreak-terraform-locks

# Recreate state file
terraform plan  # Should show "No changes"
```

**Prevention**: Back up bootstrap state file
```bash
# After bootstrap completes
cp terraform/bootstrap/terraform.tfstate ~/terraform-bootstrap-state-backup.json

# Or store in a separate S3 bucket manually
aws s3 cp terraform/bootstrap/terraform.tfstate s3://my-personal-backups/myrunstreak-bootstrap-state.json
```

---

## Important Notes

### 1. Bootstrap is Stateful

Bootstrap itself uses **local state** (the chicken-and-egg problem). The bootstrap state file is stored at:

```
terraform/bootstrap/terraform.tfstate
```

**⚠️ CRITICAL**: Do NOT lose this file! If lost, Terraform won't know the bootstrap resources exist.

**Best Practice**: Back up bootstrap state file immediately after creation.

### 2. Prevent Destroy Lifecycle

Both S3 bucket and DynamoDB table have:
```hcl
lifecycle {
  prevent_destroy = true
}
```

This prevents accidental deletion. To delete:
1. Remove lifecycle block
2. Run `terraform apply`
3. Run `terraform destroy`

### 3. Cost of Bootstrap Infrastructure

**S3 Bucket**:
- Storage: ~$0.023 per GB per month
- State files are tiny (~50KB-500KB)
- Cost: **~$0.001/month** (essentially free)

**DynamoDB Table**:
- Pay-per-request billing
- Locking operations: ~$0.25 per million requests
- Typical usage: <100 requests/month
- Cost: **~$0.00/month** (free tier covers it)

**Total Bootstrap Cost**: Less than $0.01/month

### 4. One Bootstrap Per AWS Account (Usually)

You can use the same bootstrap resources for multiple environments:

```
S3 Bucket: myrunstreak-terraform-state-123456789012
├─ myrunstreak/dev/terraform.tfstate      (dev environment)
├─ myrunstreak/staging/terraform.tfstate  (staging environment)
└─ myrunstreak/prod/terraform.tfstate     (prod environment)

DynamoDB Table: myrunstreak-terraform-locks
├─ Lock ID: myrunstreak/dev/terraform.tfstate
├─ Lock ID: myrunstreak/staging/terraform.tfstate
└─ Lock ID: myrunstreak/prod/terraform.tfstate
```

Each environment uses a different `key` in the backend configuration.

### 5. Bootstrap State vs Main State

```
┌─────────────────────────────────────────┐
│       Bootstrap State (LOCAL)           │
│  terraform/bootstrap/terraform.tfstate  │
│  ├─ S3 bucket resource                  │
│  └─ DynamoDB table resource             │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│      Main State (REMOTE/S3)             │
│  s3://.../myrunstreak/dev/...tfstate    │
│  ├─ Lambda function                     │
│  ├─ API Gateway                         │
│  ├─ S3 database bucket                  │
│  └─ All other infrastructure            │
└─────────────────────────────────────────┘
```

Bootstrap state stays local. Main infrastructure state goes to S3.

---

## Summary

**Bootstrap creates**:
- ✅ S3 bucket for remote state storage
- ✅ DynamoDB table for state locking
- ✅ Versioning, encryption, security configured

**Bootstrap enables**:
- ✅ Team collaboration (shared state)
- ✅ CI/CD deployments (GitHub Actions can access state)
- ✅ Concurrent operation safety (locking prevents conflicts)
- ✅ State recovery (versioning allows rollback)

**Next steps**:
1. ✅ Bootstrap complete (you are here)
2. Update main Terraform backend configuration with your account ID
3. Initialize main infrastructure: `terraform init`
4. Deploy main infrastructure: `terraform apply`

**Related Documentation**:
- [GITHUB_ACTIONS.md](./GITHUB_ACTIONS.md) - CI/CD setup after bootstrap
- [TERRAFORM_GUIDE.md](./TERRAFORM_GUIDE.md) - Deep dive on Terraform concepts
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Infrastructure architecture overview

---

🎉 **Bootstrap Complete! You're ready to deploy the main infrastructure.**
