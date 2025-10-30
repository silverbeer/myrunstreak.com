variable "aws_region" {
  description = "AWS region for infrastructure"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"
}

variable "smashrun_client_id" {
  description = "SmashRun OAuth Client ID"
  type        = string
  sensitive   = true
}

variable "smashrun_client_secret" {
  description = "SmashRun OAuth Client Secret"
  type        = string
  sensitive   = true
}
