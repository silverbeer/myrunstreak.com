# ==============================================================================
# GitHub OIDC Module - Secure CI/CD Authentication
# ==============================================================================
# This module sets up OpenID Connect (OIDC) authentication between GitHub Actions
# and AWS, eliminating the need for long-lived AWS credentials.
#
# How OIDC Works:
# 1. GitHub Actions requests a JWT token from GitHub's OIDC provider
# 2. AWS verifies the token with GitHub's OIDC provider
# 3. AWS issues temporary credentials to the GitHub Actions workflow
# 4. Workflow uses temporary credentials (expires in ~1 hour)
#
# Benefits:
# - No long-lived credentials to manage or rotate
# - Credentials automatically expire
# - Fine-grained access control based on repo/branch/environment
# - Audit trail in CloudTrail
#
# Learning Points:
# - OIDC identity federation
# - Trust policies with conditions
# - Temporary security credentials (STS)
# ==============================================================================

# ------------------------------------------------------------------------------
# GitHub OIDC Identity Provider
# ------------------------------------------------------------------------------
# This creates the trust relationship between AWS and GitHub's OIDC provider.
# Only needs to be created once per AWS account.

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # Client ID - always "sts.amazonaws.com" for AWS
  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint of GitHub's OIDC provider certificate
  # This is GitHub's current thumbprint (as of 2023)
  # AWS now handles thumbprint validation automatically for known providers
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  tags = merge(
    var.tags,
    {
      Name = "github-actions-oidc"
    }
  )
}

# ------------------------------------------------------------------------------
# GitHub Actions Deploy Role
# ------------------------------------------------------------------------------
# This role is assumed by GitHub Actions workflows for deployments

resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-${var.environment}"
  description = "Role for GitHub Actions CI/CD deployments"

  # Trust Policy - Defines WHO can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict to specific repository
            # Format: repo:owner/repo:ref:refs/heads/branch
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  # Optional: Add more restrictive conditions
  # Example: Only allow from main branch
  # "token.actions.githubusercontent.com:sub" = "repo:owner/repo:ref:refs/heads/main"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-github-actions"
    }
  )
}

# ------------------------------------------------------------------------------
# Lambda Deployment Permissions
# ------------------------------------------------------------------------------
# Permissions to update Lambda function code

resource "aws_iam_role_policy" "lambda_deploy" {
  name = "lambda-deployment"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaUpdateCode"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:UpdateFunctionConfiguration"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.project_name}-*"
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.project_name}-*"
        # For smoke tests after deployment
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# ECR Permissions
# ------------------------------------------------------------------------------
# Permissions to push container images to ECR

resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRGetAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.project_name}-*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# S3 Permissions (for Lambda packages if needed)
# ------------------------------------------------------------------------------
# Permissions to upload Lambda deployment packages to S3

resource "aws_iam_role_policy" "s3_deploy" {
  name = "s3-deployment"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3LambdaPackages"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Logs Permissions
# ------------------------------------------------------------------------------
# Permissions to read logs for verification

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Additional Permissions (Optional)
# ------------------------------------------------------------------------------
# Uncomment if needed for your workflows

# Terraform State Access (if running Terraform from GitHub Actions)
# resource "aws_iam_role_policy" "terraform_state" {
#   name = "terraform-state"
#   role = aws_iam_role.github_actions.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject",
#           "s3:DeleteObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           "arn:aws:s3:::${var.terraform_state_bucket}",
#           "arn:aws:s3:::${var.terraform_state_bucket}/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "dynamodb:GetItem",
#           "dynamodb:PutItem",
#           "dynamodb:DeleteItem"
#         ]
#         Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.terraform_lock_table}"
#       }
#     ]
#   })
# }
