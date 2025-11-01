#!/bin/bash
# ==============================================================================
# Update SmashRun OAuth Tokens in GitHub Secrets
# ==============================================================================
# This script reads tokens from /tmp/smashrun_tokens.txt and updates
# GitHub Secrets for CI/CD deployments.
#
# Prerequisites:
# - GitHub CLI (gh) installed and authenticated
# - Tokens saved in /tmp/smashrun_tokens.txt
#
# Usage:
#   ./scripts/update_oauth_secrets.sh
# ==============================================================================

set -e

TOKEN_FILE="/tmp/smashrun_tokens.txt"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Update SmashRun OAuth Tokens in GitHub Secrets      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if token file exists
if [ ! -f "$TOKEN_FILE" ]; then
    echo "❌ Error: Token file not found at $TOKEN_FILE"
    echo ""
    echo "Run this first:"
    echo "  uv run python scripts/get_oauth_tokens.py"
    echo ""
    exit 1
fi

# Load tokens from file
source "$TOKEN_FILE"

# Verify tokens are set
if [ -z "$SMASHRUN_ACCESS_TOKEN" ] || [ -z "$SMASHRUN_REFRESH_TOKEN" ]; then
    echo "❌ Error: Tokens not found in $TOKEN_FILE"
    echo "Expected format:"
    echo "  SMASHRUN_ACCESS_TOKEN=xxx"
    echo "  SMASHRUN_REFRESH_TOKEN=xxx"
    exit 1
fi

echo "📋 Tokens loaded from $TOKEN_FILE"
echo "   Access Token:  ${SMASHRUN_ACCESS_TOKEN:0:20}..."
echo "   Refresh Token: ${SMASHRUN_REFRESH_TOKEN:0:20}..."
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) not installed"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Error: Not authenticated with GitHub CLI"
    echo "Run: gh auth login"
    exit 1
fi

echo "🔐 Updating GitHub Secrets..."
echo ""

# Update access token
echo "Updating SMASHRUN_ACCESS_TOKEN..."
gh secret set SMASHRUN_ACCESS_TOKEN --body "$SMASHRUN_ACCESS_TOKEN"
echo "✅ SMASHRUN_ACCESS_TOKEN updated"

# Update refresh token
echo "Updating SMASHRUN_REFRESH_TOKEN..."
gh secret set SMASHRUN_REFRESH_TOKEN --body "$SMASHRUN_REFRESH_TOKEN"
echo "✅ SMASHRUN_REFRESH_TOKEN updated"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              ✅ GitHub Secrets Updated!                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Verify secrets:"
echo "  gh secret list"
echo ""
echo "🚀 Next step: Push code to trigger GitHub Actions deployment"
echo "  git add ."
echo "  git commit -m \"feat: add real Lambda sync code\""
echo "  git push"
echo ""

# Optionally clean up token file
read -p "🗑️  Delete token file? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm "$TOKEN_FILE"
    echo "✅ Token file deleted"
else
    echo "⚠️  Token file remains at: $TOKEN_FILE"
    echo "   (Remember to delete it manually later!)"
fi
