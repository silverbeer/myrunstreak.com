# MyRunStreak.com - Development Environment
# This is the main Terraform configuration for the dev environment

terraform {
  required_version = ">= 1.5.0"

  # IMPORTANT: Run the bootstrap configuration first to create this backend
  # After bootstrap completes, uncomment the backend block below and run terraform init

  # backend "s3" {
  #   bucket         = "myrunstreak-terraform-state-<YOUR_ACCOUNT_ID>"
  #   key            = "myrunstreak/dev/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "myrunstreak-terraform-locks"
  #   encrypt        = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "MyRunStreak"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

locals {
  project_name = "myrunstreak"
  common_tags = {
    Project     = "MyRunStreak"
    Environment = var.environment
  }
}
