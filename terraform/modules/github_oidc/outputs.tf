# ==============================================================================
# GitHub OIDC Module Outputs
# ==============================================================================

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy role (use this in GitHub secrets)"
  value       = aws_iam_role.github_actions.arn
}

output "deploy_role_name" {
  description = "Name of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions.name
}
