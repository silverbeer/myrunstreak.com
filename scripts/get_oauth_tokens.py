#!/usr/bin/env python3
"""
Get SmashRun OAuth Tokens

This script walks you through the OAuth flow to get access_token and refresh_token.
These tokens are needed for the Lambda function to sync data from SmashRun.

Usage:
    uv run python scripts/get_oauth_tokens.py
"""

import os
import sys

# Add src to path so we can import our modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from dotenv import load_dotenv
from shared.smashrun.oauth import SmashRunOAuthClient

def main():
    # Load environment variables
    load_dotenv()

    client_id = os.getenv('SMASHRUN_CLIENT_ID')
    client_secret = os.getenv('SMASHRUN_CLIENT_SECRET')
    redirect_uri = os.getenv('SMASHRUN_REDIRECT_URI', 'urn:ietf:wg:oauth:2.0:oob')

    if not client_id or not client_secret:
        print("❌ Error: SMASHRUN_CLIENT_ID and SMASHRUN_CLIENT_SECRET must be set in .env")
        print("\nMake sure your .env file contains:")
        print("  SMASHRUN_CLIENT_ID=streak_xxxxx")
        print("  SMASHRUN_CLIENT_SECRET=xxxxxxxx")
        sys.exit(1)

    print("╔═══════════════════════════════════════════════════════════╗")
    print("║         SmashRun OAuth Token Generator                   ║")
    print("╚═══════════════════════════════════════════════════════════╝")
    print()
    print("This will get you the access_token and refresh_token needed")
    print("for the Lambda function to sync your SmashRun data.")
    print()

    # Initialize OAuth client
    oauth = SmashRunOAuthClient(
        client_id=client_id,
        client_secret=client_secret,
        redirect_uri=redirect_uri
    )

    # Step 1: Get authorization URL
    auth_url = oauth.get_authorization_url()

    print("📍 Step 1: Authorize Access")
    print("─────────────────────────────────────────────────────────")
    print("Open this URL in your browser:")
    print()
    print(f"  {auth_url}")
    print()
    print("After authorizing, SmashRun will show you a code.")
    print()

    # Step 2: Get authorization code from user
    auth_code = input("Paste the authorization code here: ").strip()

    if not auth_code:
        print("❌ No code provided. Exiting.")
        sys.exit(1)

    print()
    print("🔄 Exchanging code for tokens...")

    # Step 3: Exchange code for tokens
    try:
        token_data = oauth.exchange_code_for_token(auth_code)

        access_token = token_data.get('access_token')
        refresh_token = token_data.get('refresh_token')
        expires_in = token_data.get('expires_in', 'unknown')

        if not access_token or not refresh_token:
            print("❌ Error: Failed to get tokens from SmashRun")
            print(f"Response: {token_data}")
            sys.exit(1)

        print()
        print("╔═══════════════════════════════════════════════════════════╗")
        print("║                 ✅ SUCCESS! Tokens Retrieved              ║")
        print("╚═══════════════════════════════════════════════════════════╝")
        print()
        print("📋 Your OAuth Tokens:")
        print("─────────────────────────────────────────────────────────")
        print()
        print(f"Access Token:  {access_token}")
        print(f"Refresh Token: {refresh_token}")
        print(f"Expires In:    {expires_in} seconds")
        print()
        print("─────────────────────────────────────────────────────────")
        print()
        print("🔐 Next Steps:")
        print()
        print("1. Update terraform.tfvars (local):")
        print(f"   smashrun_access_token  = \"{access_token}\"")
        print(f"   smashrun_refresh_token = \"{refresh_token}\"")
        print()
        print("2. Update GitHub Secrets (for CI/CD):")
        print(f"   gh secret set SMASHRUN_ACCESS_TOKEN --body \"{access_token}\"")
        print(f"   gh secret set SMASHRUN_REFRESH_TOKEN --body \"{refresh_token}\"")
        print()
        print("3. Or run the update script:")
        print("   ./scripts/update_oauth_secrets.sh")
        print()

        # Optionally save to a temporary file
        save = input("💾 Save tokens to temp file? (y/N): ").strip().lower()
        if save == 'y':
            with open('/tmp/smashrun_tokens.txt', 'w') as f:
                f.write(f"SMASHRUN_ACCESS_TOKEN={access_token}\n")
                f.write(f"SMASHRUN_REFRESH_TOKEN={refresh_token}\n")
            print(f"✅ Tokens saved to: /tmp/smashrun_tokens.txt")

    except Exception as e:
        print(f"❌ Error getting tokens: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
