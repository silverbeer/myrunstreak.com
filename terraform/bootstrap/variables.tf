variable "aws_region" {
  description = "AWS region for infrastructure"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "myrunstreak"
}

variable "aws_account_id" {
  description = "AWS account ID for unique bucket naming"
  type        = string
}
