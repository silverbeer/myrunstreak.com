-- Migration: Add OAuth token columns to user_sources table
-- Stores tokens directly in Supabase instead of just referencing Secrets Manager
-- This enables the Lambda to manage user tokens without per-user secrets

-- Add token columns
ALTER TABLE user_sources
ADD COLUMN IF NOT EXISTS access_token TEXT,
ADD COLUMN IF NOT EXISTS refresh_token TEXT,
ADD COLUMN IF NOT EXISTS token_expires_at TIMESTAMPTZ;

-- Add comment explaining the columns
COMMENT ON COLUMN user_sources.access_token IS 'OAuth access token for the source API';
COMMENT ON COLUMN user_sources.refresh_token IS 'OAuth refresh token for obtaining new access tokens';
COMMENT ON COLUMN user_sources.token_expires_at IS 'When the access token expires (NULL = no expiration)';

-- Create index for finding expired tokens
CREATE INDEX IF NOT EXISTS idx_user_sources_token_expiry
ON user_sources(token_expires_at)
WHERE token_expires_at IS NOT NULL;
