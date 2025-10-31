# Terraform Bootstrap

This directory contains the bootstrap configuration that creates the foundational infrastructure for Terraform remote state management.

## ⚠️ IMPORTANT: Run This FIRST

Bootstrap must be completed **BEFORE** deploying the main infrastructure.

## What This Creates

- **S3 Bucket**: Stores Terraform state files remotely
- **DynamoDB Table**: Provides state locking to prevent concurrent modifications

## Quick Start

```bash
# 1. Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your AWS Account ID: $AWS_ACCOUNT_ID"

# 2. Configure variables
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and replace 123456789012 with your account ID

# 3. Initialize and apply
terraform init
terraform plan    # Review what will be created
terraform apply   # Type 'yes' to confirm

# 4. Save the output for later
terraform output -raw backend_config
```

## What Happens Next?

After bootstrap completes:

1. **Update main Terraform backend**: Edit `terraform/environments/dev/main.tf` and uncomment the backend block, replacing `<YOUR_ACCOUNT_ID>` with your actual account ID
2. **Initialize main infrastructure**: Run `terraform init` in `terraform/environments/dev/`
3. **Deploy**: Follow the [deployment guide](../../docs/GITHUB_ACTIONS.md)

## Detailed Documentation

See [docs/TERRAFORM_BOOTSTRAP.md](../../docs/TERRAFORM_BOOTSTRAP.md) for comprehensive documentation including:
- Why bootstrap is needed
- What resources are created
- Step-by-step walkthrough
- Troubleshooting
- Cost information

## Cost

Bootstrap infrastructure costs less than $0.01/month:
- S3 bucket: ~$0.001/month (state files are tiny)
- DynamoDB table: ~$0.00/month (free tier covers locking operations)

## ⚠️ CRITICAL: Backup Bootstrap State

After running bootstrap, back up the state file:

```bash
# Bootstrap state is stored locally at:
# terraform/bootstrap/terraform.tfstate

# Back it up immediately
cp terraform.tfstate ~/terraform-bootstrap-backup.json

# If lost, you'll need to import resources manually
```

## Need Help?

- Full guide: [docs/TERRAFORM_BOOTSTRAP.md](../../docs/TERRAFORM_BOOTSTRAP.md)
- Terraform guide: [docs/TERRAFORM_GUIDE.md](../../docs/TERRAFORM_GUIDE.md)
- CI/CD setup: [docs/GITHUB_ACTIONS.md](../../docs/GITHUB_ACTIONS.md)
