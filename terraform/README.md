# Terraform Infrastructure Setup

This directory contains all Terraform configurations for MyRunStreak.com infrastructure.

## Architecture Overview

The infrastructure is organized into:

1. **Bootstrap** (`bootstrap/`) - Creates S3 backend for remote state management
2. **Modules** (`modules/`) - Reusable infrastructure components
3. **Environments** (`environments/`) - Environment-specific configurations (dev, prod)

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials
- AWS account with appropriate permissions

## Initial Setup (First Time Only)

### Step 1: Bootstrap Remote State Backend

The first step is to create the S3 bucket and DynamoDB table for Terraform remote state management. This only needs to be done once per AWS account.

```bash
# Navigate to bootstrap directory
cd terraform/bootstrap

# Get your AWS account ID
aws sts get-caller-identity --query Account --output text

# Copy the example tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and add your AWS account ID
# Replace 123456789012 with your actual account ID

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the bootstrap configuration
terraform apply
```

After successful apply, Terraform will output the backend configuration. **Save this output** - you'll need it for the next step.

### Step 2: Configure Main Infrastructure Backend

Now that the remote state backend exists, configure the main infrastructure to use it.

```bash
# Navigate to dev environment
cd ../environments/dev

# Edit main.tf and uncomment the backend block
# Replace <YOUR_ACCOUNT_ID> with your actual AWS account ID

# Copy the example tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and add your SmashRun credentials
```

### Step 3: Initialize Main Infrastructure

```bash
# Initialize Terraform with the new backend
terraform init

# You'll be asked if you want to copy existing state - say yes if prompted

# Verify everything is working
terraform plan
```

## Project Structure

```
terraform/
├── bootstrap/              # Remote state backend setup
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── modules/                # Reusable Terraform modules
│   ├── lambda/            # Lambda function module
│   ├── api_gateway/       # API Gateway module
│   ├── s3/                # S3 bucket module
│   └── eventbridge/       # EventBridge rule module
└── environments/           # Environment-specific configs
    ├── dev/               # Development environment
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars.example
    └── prod/              # Production environment
        └── (same structure)
```

## Why Remote State?

Remote state storage on S3 with DynamoDB locking provides:

1. **Team Collaboration** - Multiple team members can work on infrastructure
2. **State Locking** - Prevents concurrent modifications via DynamoDB
3. **Versioning** - S3 versioning enables state recovery
4. **Security** - Encrypted at rest with server-side encryption
5. **Durability** - S3 provides 99.999999999% durability

## Working with Terraform

### Common Commands

```bash
# Navigate to environment
cd terraform/environments/dev

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy
```

### Best Practices

1. **Never commit `terraform.tfvars`** - Contains sensitive credentials
2. **Always run `terraform plan`** before `apply`
3. **Use workspaces** for multiple environments (optional)
4. **Enable state locking** - Prevents concurrent modifications
5. **Regular backups** - S3 versioning provides this automatically

## Troubleshooting

### Backend Initialization Failed

If you get an error about the backend not existing:
1. Make sure you ran the bootstrap configuration first
2. Verify the bucket name matches your AWS account ID
3. Check that you have the correct AWS credentials configured

### State Lock Errors

If Terraform complains about a state lock:
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Credentials Issues

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Configure AWS CLI if needed
aws configure
```

## Next Steps

After completing the bootstrap:

1. Create reusable modules for Lambda, API Gateway, S3, EventBridge
2. Configure dev environment infrastructure
3. Set up CI/CD with GitHub Actions
4. Create prod environment when ready

## Security Notes

- All S3 buckets have public access blocked
- State files are encrypted at rest
- DynamoDB table uses on-demand pricing (pay-per-request)
- Sensitive variables are marked as `sensitive = true`
- Never commit `.tfvars` files to version control
