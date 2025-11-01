# Terraform Deep Dive - MyRunStreak.com

This guide explains **every Terraform concept** used in this project so you can understand exactly what's happening.

## 🎓 Table of Contents

1. [Terraform Basics](#terraform-basics)
2. [Module Architecture](#module-architecture)
3. [S3 Module Explained](#s3-module-explained)
4. [IAM Roles & Policies](#iam-roles--policies)
5. [Lambda Module Explained](#lambda-module-explained)
6. [API Gateway Module Explained](#api-gateway-module-explained)
7. [Secrets Manager](#secrets-manager)
8. [EventBridge (CloudWatch Events)](#eventbridge)
9. [Remote State Management](#remote-state-management)
10. [Best Practices](#best-practices)

---

## Terraform Basics

### What is Terraform?

Terraform is **Infrastructure as Code** (IaC). Instead of clicking in the AWS console, you write code that defines your infrastructure. Benefits:

- **Version Control** - Track changes in git
- **Reproducible** - Same code = same infrastructure
- **Documentation** - Code documents what exists
- **Automation** - CI/CD pipelines can deploy
- **Preview Changes** - See what will change before applying

### Core Concepts

#### 1. **Resources** - Things you create
```hcl
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-bucket-name"
}
```
- `aws_s3_bucket` - Resource type (from AWS provider)
- `my_bucket` - Local name (how you reference it in Terraform)
- `bucket` - Argument (configuration for the resource)

#### 2. **Data Sources** - Things that already exist
```hcl
data "aws_caller_identity" "current" {}

# Use it:
# data.aws_caller_identity.current.account_id
```
- Read-only
- Query AWS for existing information
- Don't create anything

#### 3. **Variables** - Inputs to your configuration
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Use it: var.environment
```

#### 4. **Outputs** - Values to expose
```hcl
output "bucket_name" {
  value = aws_s3_bucket.my_bucket.id
}
```
- Can be used by other modules
- Displayed after `terraform apply`
- Stored in state file

#### 5. **Locals** - Computed values
```hcl
locals {
  bucket_name = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

# Use it: local.bucket_name
```

---

## Module Architecture

### Why Modules?

Modules are **reusable Terraform code**. Instead of duplicating code, you create a module once and use it multiple times with different inputs.

**Without Modules:**
```
dev/main.tf      - 500 lines (S3, Lambda, API Gateway, etc.)
prod/main.tf     - 500 lines (duplicate code, hard to maintain)
```

**With Modules:**
```
modules/s3/main.tf         - 100 lines (reusable)
modules/lambda/main.tf     - 150 lines (reusable)
dev/main.tf                - 50 lines (just calls modules)
prod/main.tf               - 50 lines (calls same modules)
```

### Module Structure

Each module has 3 files:

1. **`main.tf`** - Resource definitions
2. **`variables.tf`** - Inputs (what you can configure)
3. **`outputs.tf`** - Outputs (what it returns)

### Using a Module

```hcl
module "database_bucket" {
  source = "../../modules/s3"

  # Input variables
  project_name              = "myrunstreak"
  environment               = "dev"
  account_id                = "123456789012"
  lambda_execution_role_arn = module.lambda.execution_role_arn

  # Optional variables
  enable_cors = true
}

# Access outputs
# module.database_bucket.bucket_id
# module.database_bucket.bucket_arn
```

---

## S3 Module Explained

### Purpose
Store the `runs.duckdb` file so Lambda can:
1. Download it before sync
2. Update it with new runs
3. Upload it back to S3

### Key Resources

#### 1. **S3 Bucket**
```hcl
resource "aws_s3_bucket" "database" {
  bucket = "${var.project_name}-data-${var.environment}-${var.account_id}"
  force_destroy = var.environment == "dev" ? true : false
}
```

**Why `force_destroy`?**
- `true` in dev: Allows `terraform destroy` to delete bucket even if it has files
- `false` in prod: Prevents accidental data loss

**Why include account_id in name?**
- S3 bucket names are **globally unique** across all AWS accounts
- Adding account ID prevents naming conflicts

#### 2. **Versioning**
```hcl
resource "aws_s3_bucket_versioning" "database" {
  bucket = aws_s3_bucket.database.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

**What does this do?**
- Every time Lambda uploads `runs.duckdb`, S3 keeps the old version
- If sync corrupts data, you can roll back to a previous version
- Versions are automatically managed by S3

**Example:**
```
Upload #1: runs.duckdb (version-id: abc123)
Upload #2: runs.duckdb (version-id: def456)  <- Current version
Upload #3: runs.duckdb (version-id: ghi789)  <- Current version

You can retrieve abc123 or def456 if needed
```

#### 3. **Encryption**
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "database" {
  bucket = aws_s3_bucket.database.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

**What does this do?**
- Encrypts all objects at rest using AES-256
- Free and automatic - no keys to manage
- S3 handles encryption/decryption transparently

**Two types of S3 encryption:**
1. **SSE-S3** (AES256) - AWS-managed keys (what we use - free!)
2. **SSE-KMS** - Customer-managed keys (costs $1/month per key)

#### 4. **Block Public Access**
```hcl
resource "aws_s3_bucket_public_access_block" "database" {
  bucket = aws_s3_bucket.database.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**What does each setting mean?**
- `block_public_acls` - Prevents public ACLs (Access Control Lists)
- `block_public_policy` - Prevents public bucket policies
- `ignore_public_acls` - Ignores any existing public ACLs
- `restrict_public_buckets` - Prevents cross-account access

**Result:** The bucket is completely private. Only the Lambda function (via IAM role) can access it.

#### 5. **Lifecycle Policy**
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "database" {
  bucket = aws_s3_bucket.database.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "GLACIER_IR"
    }
  }
}
```

**What does this do?**

**Day 0:** Upload runs.duckdb (version 1) - $0.023/GB/month (S3 Standard)
**Day 1:** Upload runs.duckdb (version 2 current, version 1 noncurrent)
**Day 7:** Version 1 → Glacier Instant Retrieval ($0.004/GB/month - 83% cheaper!)
**Day 30:** Version 1 deleted automatically

**Why?**
- Keeps recent versions for quick rollback
- Moves old versions to cheaper storage
- Deletes ancient versions to save money
- All automatic - no manual cleanup needed

#### 6. **Bucket Policy**
```hcl
resource "aws_s3_bucket_policy" "database" {
  bucket = aws_s3_bucket.database.id

  policy = jsonencode({
    Statement = [
      {
        Sid = "AllowLambdaAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.lambda_execution_role_arn
        }
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.database.arn}/*"
      }
    ]
  })
}
```

**What's the difference between IAM Role and Bucket Policy?**

**IAM Role (attached to Lambda):**
- "This Lambda can access S3"
- Defines what the Lambda can do

**Bucket Policy (attached to S3):**
- "This bucket allows Lambda to access it"
- Defines who can access the bucket

**Both are needed!** Think of it like:
- IAM Role = Your ID badge
- Bucket Policy = Building access control

You need both your badge AND the building must allow your badge.

---

## IAM Roles & Policies

### What is IAM?

**IAM (Identity and Access Management)** controls who can do what in AWS.

**Three key concepts:**
1. **Identities** - Users, roles, groups
2. **Policies** - JSON documents that define permissions
3. **Trust Relationships** - Who can assume a role

### Lambda Execution Role

Every Lambda function needs an execution role. It's like giving the Lambda an "identity" that AWS checks when it tries to access other services.

```hcl
resource "aws_iam_role" "lambda_execution" {
  name = "myrunstreak-lambda-execution"

  # Trust Policy - Who can assume this role?
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
```

**Trust Policy Explained:**
- `sts:AssumeRole` - The action of taking on this role
- `Principal = lambda.amazonaws.com` - Only Lambda service can use this role
- This answers: "Who is allowed to use this role?"

### IAM Policy - Permissions

After defining the role, attach policies that define what it can do:

```hcl
resource "aws_iam_role_policy" "lambda_permissions" {
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AccessSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:myrunstreak/*"
      },
      {
        Sid = "AccessS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::myrunstreak-data-*/*"
      }
    ]
  })
}
```

**Policy Anatomy:**
- `Effect` - Allow or Deny
- `Action` - What operations (s3:GetObject, etc.)
- `Resource` - Which resources (specific ARNs or wildcards)
- `Sid` - Statement ID (just a label for humans)

**Principle of Least Privilege:**
Only grant the minimum permissions needed. Our Lambda can:
- ✅ Read secrets from `myrunstreak/*` (not all secrets)
- ✅ Read/write S3 objects in `myrunstreak-data-*` (not all buckets)
- ❌ Cannot delete S3 buckets
- ❌ Cannot create new Lambda functions
- ❌ Cannot access other AWS services

---

## Lambda Module Explained

### Purpose
Run the Python sync code in the cloud without managing servers.

### Lambda Fundamentals

**Key Concepts:**
- **Handler** - The function AWS calls (e.g., `lambda_function.handler`)
- **Runtime** - Python version (python3.12)
- **Memory** - 128 MB to 10 GB (affects CPU allocation)
- **Timeout** - Max execution time (15 minutes max)
- **Package** - ZIP file with your code + dependencies

### Lambda Resource

```hcl
resource "aws_lambda_function" "sync_runner" {
  function_name = "${var.project_name}-sync-runner"
  role          = aws_iam_role.lambda_execution.arn

  # Code package
  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)

  # Runtime configuration
  runtime = "python3.12"
  handler = "lambda_function.handler"

  # Performance tuning
  memory_size = 512  # MB
  timeout     = 300  # 5 minutes

  # Environment variables
  environment {
    variables = {
      S3_BUCKET_NAME    = var.s3_bucket_name
      ENVIRONMENT       = var.environment
      LOG_LEVEL         = "INFO"
    }
  }
}
```

**Important Fields:**

**`source_code_hash`** - Why is this needed?
```hcl
source_code_hash = filebase64sha256(var.lambda_package_path)
```
- Terraform computes a hash of the ZIP file
- If code changes, hash changes
- Terraform knows to update the Lambda function
- Without this, Terraform wouldn't detect code changes!

**`memory_size`** - How does Lambda pricing work?
- Charged per GB-second
- More memory = faster CPU + more cost
- 512 MB is a good balance for our use case
- Duration matters more than memory for cost

**Example calculation:**
```
Memory: 512 MB = 0.5 GB
Duration: 30 seconds per sync
Invocations: 31 per month (daily)

GB-seconds = 0.5 GB × 30 sec × 31 = 465 GB-seconds
Cost = 465 × $0.0000166667 = $0.0077 = less than 1 cent/month!
```

**`timeout`** - Why 5 minutes?
- Fetching 31 activities + 118 splits takes ~30 seconds
- Extra buffer for network delays
- Prevents runaway Lambda (costs)
- Max Lambda timeout is 15 minutes

### Lambda Environment Variables

```hcl
environment {
  variables = {
    S3_BUCKET_NAME = var.s3_bucket_name
    ENVIRONMENT    = var.environment
  }
}
```

**Why use environment variables?**
- ✅ No hardcoded values in code
- ✅ Different values per environment (dev/prod)
- ✅ Easy to change without redeploying code
- ✅ Visible in AWS console for debugging

**In Python:**
```python
import os

bucket_name = os.environ['S3_BUCKET_NAME']  # Gets value from Terraform
```

---

## API Gateway Module Explained

### Purpose
Create HTTP endpoints that trigger Lambda functions.

### REST API vs HTTP API

AWS offers two types:

| Feature | REST API | HTTP API |
|---------|----------|----------|
| Price | $3.50/million | $1.00/million |
| Features | More features | Simpler |
| API Keys | ✅ Yes | ❌ No |
| Usage Plans | ✅ Yes | ❌ No |
| WebSocket | ❌ No | ✅ Yes |

**We use REST API because:**
- API Keys for security
- Usage Plans for rate limiting
- More battle-tested

### API Gateway Structure

```
API Gateway REST API
├── Resources (URL paths)
│   ├── /sync (POST)
│   ├── /stats (GET)
│   └── /health (GET)
├── Methods (HTTP verbs)
│   └── POST /sync
│       ├── Method Request (validation)
│       ├── Integration Request (to Lambda)
│       ├── Integration Response (from Lambda)
│       └── Method Response (to client)
├── Stages (environments)
│   ├── dev
│   └── prod
└── Deployment
    └── Publishes changes
```

### Creating the API

```hcl
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "MyRunStreak.com API for syncing running data"

  endpoint_configuration {
    types = ["EDGE"]  # CloudFront distribution (global, fast)
  }
}
```

**Endpoint Types:**
- **EDGE** - CloudFront CDN (best for global users) - *We use this*
- **REGIONAL** - Single region only (cheaper, less latency control)
- **PRIVATE** - VPC only (internal APIs)

### Creating a Resource (URL Path)

```hcl
resource "aws_api_gateway_resource" "sync" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "sync"
}

# This creates: https://api-id.execute-api.us-east-2.amazonaws.com/dev/sync
```

### Creating a Method

```hcl
resource "aws_api_gateway_method" "sync_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.sync.id
  http_method   = "POST"
  authorization = "NONE"  # We'll use API keys instead
  api_key_required = true
}
```

**`api_key_required = true`** means:
- Requests must include `x-api-key` header
- API Gateway checks key before invoking Lambda
- Invalid key = 403 Forbidden (Lambda never runs)

### Lambda Integration

```hcl
resource "aws_api_gateway_integration" "sync_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.sync.id
  http_method = aws_api_gateway_method.sync_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}
```

**`type = "AWS_PROXY"`** means:
- API Gateway passes the entire HTTP request to Lambda
- Lambda gets: headers, body, query params, everything
- Lambda must return properly formatted HTTP response

**Alternative: `type = "AWS"`**
- You can transform request/response
- More complex but more control
- We use PROXY for simplicity

### API Key & Usage Plan

```hcl
# Create an API key
resource "aws_api_gateway_api_key" "personal" {
  name = "${var.project_name}-personal-key"
}

# Create a usage plan (rate limits)
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  throttle_settings {
    burst_limit = 10   # Max concurrent requests
    rate_limit  = 5    # Requests per second (sustained)
  }

  quota_settings {
    limit  = 1000      # Total requests
    period = "DAY"     # Per day
  }
}

# Associate key with usage plan
resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.personal.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
}
```

**Throttle Settings Explained:**
- **Burst limit (10)** - Can handle 10 simultaneous requests
- **Rate limit (5/sec)** - Average 5 requests per second
- Exceeding limits = 429 Too Many Requests

**Quota Settings:**
- 1000 requests/day max
- Resets at midnight UTC
- Exceeding quota = 429 Too Many Requests

**Why these limits?**
- Prevents accidental runaway scripts
- Protects against abuse
- Controls Lambda costs
- For personal use, very generous

---

## Secrets Manager

### Purpose
Store sensitive data securely (SmashRun OAuth tokens, API keys).

### Why Not Environment Variables?

**Environment Variables:**
- ❌ Visible in AWS console
- ❌ Visible in CloudFormation/Terraform state
- ❌ Hard to rotate
- ❌ Not encrypted separately

**Secrets Manager:**
- ✅ Encrypted at rest (KMS)
- ✅ Access controlled by IAM
- ✅ Automatic rotation
- ✅ Version history
- ✅ Audit trail (CloudTrail)

### Creating a Secret

```hcl
resource "aws_secretsmanager_secret" "smashrun" {
  name = "myrunstreak/smashrun/oauth"
  description = "SmashRun OAuth credentials for API access"

  recovery_window_in_days = 7  # Can restore if deleted accidentally
}

resource "aws_secretsmanager_secret_version" "smashrun" {
  secret_id     = aws_secretsmanager_secret.smashrun.id
  secret_string = jsonencode({
    client_id     = var.smashrun_client_id
    client_secret = var.smashrun_client_secret
    access_token  = var.smashrun_access_token
    refresh_token = var.smashrun_refresh_token
  })
}
```

**In Lambda (Python):**
```python
import boto3
import json

def get_smashrun_credentials():
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='myrunstreak/smashrun/oauth')
    return json.loads(response['SecretString'])

creds = get_smashrun_credentials()
access_token = creds['access_token']
```

### Cost

**Secrets Manager Pricing:**
- $0.40 per secret per month
- $0.05 per 10,000 API calls

**Our cost:**
- 2 secrets (SmashRun, API keys) = $0.80/month
- ~31 API calls/month (daily sync) = $0.00
- **Total: $0.80/month**

---

## EventBridge

### Purpose
Trigger Lambda on a schedule (daily at 6am EST).

### Cron Expressions

EventBridge uses cron expressions, but with **6 fields** (not 5):

```
cron(Minutes Hours Day Month DayOfWeek Year)
     0       11   *    *      ?         *
```

**Our schedule: `cron(0 11 * * ? *)`**
- `0` - 0 minutes past the hour
- `11` - 11:00 UTC = 6:00am EST (winter) / 7:00am EDT (summer)
- `*` - Every day
- `*` - Every month
- `?` - Any day of week (? required when using *)
- `*` - Every year

**Why UTC time?**
- AWS always uses UTC
- EST = UTC-5, EDT = UTC-4
- 11:00 UTC = 6:00am EST (winter) or 7:00am EDT (summer)

### Creating the Rule

```hcl
resource "aws_cloudwatch_event_rule" "daily_sync" {
  name                = "${var.project_name}-daily-sync"
  description         = "Trigger Lambda to sync running data daily at 6am EST"
  schedule_expression = "cron(0 11 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.daily_sync.name
  target_id = "lambda"
  arn       = var.lambda_function_arn
}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_sync.arn
}
```

**Lambda Permission Explained:**
- EventBridge needs permission to invoke your Lambda
- This is a **resource-based policy** (attached to Lambda)
- Without this, EventBridge gets "Access Denied"

---

## Remote State Management

### The Problem

Terraform stores the current state of your infrastructure in a **state file** (`terraform.tfstate`).

**Local state (default):**
```
terraform/
└── terraform.tfstate  # Stored on your computer
```

**Problems:**
- ❌ If you lose your computer, you lose state
- ❌ Can't collaborate (state on your machine only)
- ❌ No locking (two people can run terraform simultaneously)
- ❌ Contains sensitive data (passwords, etc.)

### The Solution: Remote State

Store state in S3 with DynamoDB locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "myrunstreak-terraform-state-123456789012"
    key            = "myrunstreak/dev/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "myrunstreak-terraform-locks"
    encrypt        = true
  }
}
```

**Benefits:**
- ✅ State stored in S3 (durable, backed up)
- ✅ Encrypted at rest
- ✅ Multiple team members can access
- ✅ DynamoDB provides locking (prevents concurrent runs)
- ✅ State versioning (can roll back)

### How Locking Works

```
Person A starts terraform apply
  ↓
DynamoDB creates lock entry: "state-locked-by-alice"
  ↓
Person B tries terraform apply
  ↓
Terraform checks DynamoDB: "Already locked!"
  ↓
Person B gets error: "State is locked by alice"
  ↓
Person A finishes: terraform apply
  ↓
DynamoDB deletes lock entry
  ↓
Person B can now run terraform apply
```

### Bootstrap Process

The chicken-and-egg problem: You need S3 + DynamoDB for remote state, but how do you create them with Terraform if you need remote state first?

**Solution: Two-step bootstrap**

**Step 1: Local state**
```bash
cd terraform/bootstrap
terraform init      # Uses local state
terraform apply     # Creates S3 bucket + DynamoDB table
```

**Step 2: Migrate to remote state**
```bash
cd terraform/environments/dev
# Edit main.tf - uncomment backend block
terraform init      # Terraform asks: "Copy existing state to S3?" → Yes!
```

Now all future runs use remote state!

---

## Best Practices

### 1. Never Commit Secrets

**❌ BAD:**
```hcl
variable "access_token" {
  default = "my-secret-token"  # NEVER DO THIS!
}
```

**✅ GOOD:**
```hcl
variable "access_token" {
  description = "SmashRun access token"
  type        = string
  sensitive   = true  # Marks as sensitive
  # No default - must be provided at runtime
}
```

**.gitignore:**
```
*.tfvars        # Contains actual values
*.tfstate       # Contains infrastructure state
*.tfstate.*     # State backups
.terraform/     # Provider plugins
```

### 2. Use `terraform plan` Before `apply`

Always preview changes:

```bash
# See what will change
terraform plan

# If it looks good, apply
terraform apply

# Or combine (preview + ask for confirmation)
terraform apply
```

### 3. Use `depends_on` for Dependencies

Sometimes Terraform can't figure out dependencies:

```hcl
resource "aws_lambda_function" "sync" {
  # ...

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_logs
  ]
}
```

This ensures IAM permissions and log group exist before Lambda is created.

### 4. Use `terraform fmt` for Consistent Formatting

```bash
# Format all files
terraform fmt -recursive

# Check if files need formatting (CI/CD)
terraform fmt -check -recursive
```

### 5. Use `validation` Blocks

Catch errors early:

```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

If someone tries `environment = "production"`, they get a clear error before anything is created.

### 6. Use `lifecycle` for Protection

```hcl
resource "aws_s3_bucket" "important" {
  bucket = "my-important-data"

  lifecycle {
    prevent_destroy = true  # Cannot destroy this resource
  }
}
```

Prevents accidental `terraform destroy` of critical resources.

### 7. Tag Everything

```hcl
provider "aws" {
  default_tags {
    tags = {
      Project     = "MyRunStreak"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "tom"
    }
  }
}
```

**Benefits:**
- Cost allocation (see spending per project)
- Resource organization
- Compliance (required by many orgs)

---

## Summary

You now understand:

✅ **Terraform Basics** - Resources, data sources, variables, outputs
✅ **Modules** - Reusable, composable infrastructure
✅ **S3** - Versioning, encryption, lifecycle policies
✅ **IAM** - Roles, policies, least privilege
✅ **Lambda** - Serverless compute, packaging, environment variables
✅ **API Gateway** - REST APIs, methods, integrations, API keys
✅ **Secrets Manager** - Secure credential storage
✅ **EventBridge** - Cron scheduling
✅ **Remote State** - S3 backend, locking, team collaboration

**Next:** Let's finish building the remaining modules and deploy! 🚀
