# MyRunStreak.com - Quick Start Guide

This guide will walk you through setting up the project from scratch.

## Prerequisites Checklist

- [ ] Python 3.12+ installed
- [ ] UV package manager installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform 1.5+ installed
- [ ] Git configured
- [ ] SmashRun API credentials (Client ID & Secret) from https://smashrun.com/settings/api

## Step 1: Install Python Dependencies

```bash
# Install all Python dependencies
make install

# Or manually:
uv sync --all-extras

# Activate the virtual environment
source .venv/bin/activate
```

## Step 2: Verify Installation

```bash
# Run tests (should pass or skip if no tests yet)
make test

# Check linting
make lint

# Verify type checking
make type-check
```

## Step 3: Bootstrap Terraform Remote State

This creates the S3 bucket and DynamoDB table for Terraform state management.

```bash
# Get your AWS account ID
aws sts get-caller-identity --query Account --output text

# Create bootstrap config
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and replace 123456789012 with your actual AWS account ID
# Example: aws_account_id = "987654321098"

# Bootstrap the remote state backend
terraform init
terraform plan
terraform apply

# IMPORTANT: Save the output - it shows your backend configuration
```

## Step 4: Configure Dev Environment

```bash
cd ../environments/dev

# Create your tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars and add:
# 1. Your SmashRun Client ID
# 2. Your SmashRun Client Secret

# Edit main.tf and uncomment the backend block (lines 6-12)
# Replace <YOUR_ACCOUNT_ID> with your actual AWS account ID
```

## Step 5: Initialize Dev Environment

```bash
# Initialize Terraform with remote backend
terraform init

# Verify configuration
terraform plan

# The plan should show resources to be created
```

## Step 6: Current Project Status

At this point, you have:

✅ Python project initialized with UV
✅ All dependencies installed
✅ Terraform remote state backend created
✅ Dev environment configured
✅ Proper .gitignore for secrets
✅ Code quality tools (ruff, mypy, pytest)
✅ Makefile for common operations

## Next Steps

Now you're ready to build the actual infrastructure:

1. **Design DuckDB Schema** - Define the data model for run data
2. **Create Terraform Modules** - Lambda, S3, API Gateway, EventBridge
3. **Implement SmashRun Integration** - OAuth flow and API client
4. **Build Lambda Functions** - Daily sync and API endpoints
5. **Set up CI/CD** - GitHub Actions for automated deployments

## Quick Reference

```bash
# Python Development
make install      # Install dependencies
make test         # Run tests
make lint         # Lint code
make format       # Format code
make type-check   # Type checking

# Terraform (from terraform/environments/dev)
terraform plan    # Preview changes
terraform apply   # Apply changes
terraform destroy # Destroy infrastructure
```

## Troubleshooting

### AWS Credentials Not Found

```bash
# Configure AWS CLI
aws configure

# Verify credentials
aws sts get-caller-identity
```

### Terraform Backend Already Exists

If you see "bucket already exists", it means the bootstrap was already run. This is normal - you only need to run it once.

### Permission Denied Errors

Make sure your AWS credentials have permissions to:
- Create S3 buckets
- Create DynamoDB tables
- Create Lambda functions
- Create API Gateway resources
- Create IAM roles and policies

## Getting SmashRun API Credentials

1. Go to https://smashrun.com/settings/api
2. Log in with your SmashRun account
3. Create a new application
4. Copy the Client ID and Client Secret
5. Add them to `terraform/environments/dev/terraform.tfvars`

## Security Reminders

🔒 **NEVER commit these files:**
- `terraform.tfvars` (contains secrets)
- `.env` files (contains credentials)
- `*.tfstate` files (contains infrastructure details)

✅ **These are already in .gitignore** - just don't force-add them!

## Need Help?

- Check the main [README.md](README.md) for architecture overview
- Read [terraform/README.md](terraform/README.md) for Terraform details
- Review the code - it's well-commented for learning!
