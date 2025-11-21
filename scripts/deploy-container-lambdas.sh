#!/bin/bash
# ==============================================================================
# Initial Deployment Script for Container-Based Lambdas
# ==============================================================================
# This script handles the one-time setup for migrating to container-based Lambdas.
# After initial deployment, CI/CD will handle subsequent updates.
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Terraform installed
# - Docker installed and running
#
# Usage:
#   ./scripts/deploy-container-lambdas.sh
# ==============================================================================

set -e

# Configuration
AWS_REGION="us-east-2"
AWS_ACCOUNT_ID="855323747881"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments/dev"

echo "🚀 Starting container-based Lambda deployment..."
echo ""

# ==============================================================================
# Step 1: Deploy ECR Repositories
# ==============================================================================
echo "📦 Step 1: Deploying ECR repositories..."
echo ""

cd "${TERRAFORM_DIR}"

# Always run terraform init to ensure all modules are installed
echo "  Initializing Terraform..."
AWS_PROFILE=silverbeer terraform init -upgrade

# Plan and apply ECR only (target ECR module first)
echo "  Planning ECR deployment..."
AWS_PROFILE=silverbeer terraform plan -target=module.ecr -out=ecr.tfplan

echo ""
read -p "  Apply ECR resources? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    AWS_PROFILE=silverbeer terraform apply ecr.tfplan
    echo "  ✅ ECR repositories created"
else
    echo "  ❌ ECR deployment cancelled"
    exit 1
fi

# Get ECR URLs
SYNC_ECR_URL=$(AWS_PROFILE=silverbeer terraform output -raw ecr_sync_repository_url)
QUERY_ECR_URL=$(AWS_PROFILE=silverbeer terraform output -raw ecr_query_repository_url)

echo ""
echo "  ECR repositories:"
echo "    Sync:  ${SYNC_ECR_URL}"
echo "    Query: ${QUERY_ECR_URL}"

# ==============================================================================
# Step 2: Build and Push Docker Images
# ==============================================================================
echo ""
echo "🐳 Step 2: Building and pushing Docker images..."
echo ""

cd "${PROJECT_ROOT}"

# Login to ECR
echo "  Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} --profile silverbeer | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push sync Lambda image
echo ""
echo "  Building sync Lambda image..."
docker build \
    --platform linux/amd64 \
    --provenance=false \
    --build-arg HANDLER_MODULE=sync_runs \
    -t ${SYNC_ECR_URL}:latest \
    -t ${SYNC_ECR_URL}:initial \
    .

echo "  Pushing sync Lambda image..."
docker push ${SYNC_ECR_URL}:latest
docker push ${SYNC_ECR_URL}:initial

echo "  ✅ Sync Lambda image pushed"

# Build and push query Lambda image
echo ""
echo "  Building query Lambda image..."
docker build \
    --platform linux/amd64 \
    --provenance=false \
    --build-arg HANDLER_MODULE=query_runs \
    -t ${QUERY_ECR_URL}:latest \
    -t ${QUERY_ECR_URL}:initial \
    .

echo "  Pushing query Lambda image..."
docker push ${QUERY_ECR_URL}:latest
docker push ${QUERY_ECR_URL}:initial

echo "  ✅ Query Lambda image pushed"

# ==============================================================================
# Step 3: Deploy Lambda Functions
# ==============================================================================
echo ""
echo "🔧 Step 3: Deploying Lambda functions with container images..."
echo ""

cd "${TERRAFORM_DIR}"

# Plan full deployment
echo "  Planning full infrastructure deployment..."
AWS_PROFILE=silverbeer terraform plan -out=full.tfplan

echo ""
read -p "  Apply all resources? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    AWS_PROFILE=silverbeer terraform apply full.tfplan
    echo "  ✅ All resources deployed"
else
    echo "  ❌ Full deployment cancelled"
    exit 1
fi

# ==============================================================================
# Step 4: Verify Deployment
# ==============================================================================
echo ""
echo "✅ Step 4: Verifying deployment..."
echo ""

# Get Lambda function names
SYNC_LAMBDA="myrunstreak-sync-runner-dev"
QUERY_LAMBDA="myrunstreak-query-runner-dev"

# Check sync Lambda
echo "  Testing sync Lambda..."
RESULT=$(aws lambda invoke \
    --function-name ${SYNC_LAMBDA} \
    --payload '{"source":"deployment-test"}' \
    --cli-binary-format raw-in-base64-out \
    --profile silverbeer \
    /tmp/sync-response.json 2>&1)

if [ $? -eq 0 ]; then
    echo "  ✅ Sync Lambda invoked successfully"
    cat /tmp/sync-response.json
else
    echo "  ⚠️  Sync Lambda invocation failed"
    echo "  ${RESULT}"
fi

echo ""

# Check query Lambda
echo "  Testing query Lambda..."
RESULT=$(aws lambda invoke \
    --function-name ${QUERY_LAMBDA} \
    --payload '{"source":"deployment-test"}' \
    --cli-binary-format raw-in-base64-out \
    --profile silverbeer \
    /tmp/query-response.json 2>&1)

if [ $? -eq 0 ]; then
    echo "  ✅ Query Lambda invoked successfully"
    cat /tmp/query-response.json
else
    echo "  ⚠️  Query Lambda invocation failed"
    echo "  ${RESULT}"
fi

# ==============================================================================
# Step 5: Get GitHub OIDC Role ARN
# ==============================================================================
echo ""
echo "🔑 Step 5: Getting GitHub OIDC role ARN..."
echo ""

GITHUB_ROLE_ARN=$(AWS_PROFILE=silverbeer terraform output -raw github_actions_role_arn)

echo "  GitHub Actions Role ARN:"
echo "  ${GITHUB_ROLE_ARN}"
echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================"
echo "🎉 Container-based Lambda deployment complete!"
echo "========================================"
echo ""
echo "⚠️  IMPORTANT: Update your GitHub secret"
echo ""
echo "Go to: https://github.com/silverbeer/myrunstreak.com/settings/secrets/actions"
echo ""
echo "Update or create the secret:"
echo "  Name:  AWS_LAMBDA_DEPLOY_ROLE_ARN"
echo "  Value: ${GITHUB_ROLE_ARN}"
echo ""
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Update the GitHub secret with the role ARN above"
echo "2. Push changes to main branch to trigger CI/CD"
echo "3. CI/CD will automatically build and deploy future updates"
echo ""
echo "Useful commands:"
echo "  # View sync Lambda logs"
echo "  aws logs tail /aws/lambda/${SYNC_LAMBDA} --follow --profile silverbeer"
echo ""
echo "  # View query Lambda logs"
echo "  aws logs tail /aws/lambda/${QUERY_LAMBDA} --follow --profile silverbeer"
echo ""
echo "  # Manually invoke sync Lambda"
echo "  aws lambda invoke --function-name ${SYNC_LAMBDA} \\"
echo "    --payload '{\"action\":\"manual-sync\"}' \\"
echo "    --cli-binary-format raw-in-base64-out \\"
echo "    --profile silverbeer response.json"
echo ""
