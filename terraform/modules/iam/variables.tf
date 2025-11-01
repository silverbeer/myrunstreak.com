# ==============================================================================
# IAM Module - Input Variables
# ==============================================================================

variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
  default     = "myrunstreak"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "account_id" {
  description = "AWS account ID (for resource ARNs)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for resource ARNs)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for database storage"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Optional Features
variable "enable_vpc_access" {
  description = "Enable VPC access for Lambda (if accessing RDS, etc.)"
  type        = bool
  default     = false
}

variable "enable_custom_metrics" {
  description = "Enable custom CloudWatch metrics publishing"
  type        = bool
  default     = false
}
