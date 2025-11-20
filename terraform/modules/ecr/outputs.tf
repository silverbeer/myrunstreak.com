# ==============================================================================
# ECR Module Outputs
# ==============================================================================

output "sync_repository_url" {
  description = "URL of the sync Lambda ECR repository"
  value       = aws_ecr_repository.sync.repository_url
}

output "sync_repository_arn" {
  description = "ARN of the sync Lambda ECR repository"
  value       = aws_ecr_repository.sync.arn
}

output "sync_repository_name" {
  description = "Name of the sync Lambda ECR repository"
  value       = aws_ecr_repository.sync.name
}

output "query_repository_url" {
  description = "URL of the query Lambda ECR repository"
  value       = aws_ecr_repository.query.repository_url
}

output "query_repository_arn" {
  description = "ARN of the query Lambda ECR repository"
  value       = aws_ecr_repository.query.arn
}

output "query_repository_name" {
  description = "Name of the query Lambda ECR repository"
  value       = aws_ecr_repository.query.name
}

output "registry_id" {
  description = "The registry ID where the repositories are created"
  value       = aws_ecr_repository.sync.registry_id
}
