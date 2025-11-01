# ==============================================================================
# S3 Module - Outputs
# ==============================================================================
# These outputs are used by other modules (Lambda) to reference the bucket

output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.database.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.database.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (for direct access)"
  value       = aws_s3_bucket.database.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.database.bucket_regional_domain_name
}

output "bucket_region" {
  description = "The AWS region this bucket resides in"
  value       = aws_s3_bucket.database.region
}
