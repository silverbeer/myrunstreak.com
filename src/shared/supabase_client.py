"""Supabase client connection utilities for MyRunStreak.com."""

import logging
from functools import lru_cache
from typing import Any

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from supabase import Client, create_client

from .config import find_env_file
from .secrets import get_supabase_credentials, is_running_in_lambda

logger = logging.getLogger(__name__)

# Find env file once at module load
_env_file = find_env_file()


class SupabaseSettings(BaseSettings):
    """
    Supabase connection settings loaded from environment variables.

    Used for local development. In Lambda, credentials come from Secrets Manager.

    Attributes:
        supabase_url: Supabase project URL (local or production)
        supabase_key: Supabase service role key (bypasses RLS for Lambda)
    """

    model_config = SettingsConfigDict(
        env_file=_env_file,
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    supabase_url: str = Field(
        description="Supabase project URL",
        examples=["http://127.0.0.1:54321", "https://xxx.supabase.co"],
    )

    supabase_key: str = Field(
        description="Supabase service role key (for Lambda/backend access)",
    )


@lru_cache
def get_supabase_settings() -> SupabaseSettings:
    """
    Get Supabase settings (cached singleton pattern).

    Returns:
        SupabaseSettings instance loaded from environment

    Raises:
        ValidationError: If required environment variables are missing
    """
    return SupabaseSettings()  # type: ignore[call-arg]


# Cache the client to avoid repeated Secrets Manager calls
_supabase_client: Client | None = None


def get_supabase_client() -> Client:
    """
    Get authenticated Supabase client.

    In Lambda: Fetches credentials from AWS Secrets Manager
    Locally: Uses environment variables from .env file

    Uses service role key to bypass Row Level Security (RLS).
    This is safe for backend Lambda functions that enforce their own authorization.

    Returns:
        Supabase client instance

    Example:
        ```python
        supabase = get_supabase_client()
        result = supabase.table("runs").select("*").eq("user_id", user_id).execute()
        ```
    """
    global _supabase_client

    if _supabase_client is not None:
        return _supabase_client

    if is_running_in_lambda():
        # In Lambda: Use Secrets Manager
        logger.debug("Running in Lambda - fetching Supabase credentials from Secrets Manager")
        creds = get_supabase_credentials()
        url = creds["url"]
        key = creds["key"]
    else:
        # Locally: Use environment variables
        settings = get_supabase_settings()
        url = settings.supabase_url
        key = settings.supabase_key

    logger.debug(f"Connecting to Supabase at {url}")
    _supabase_client = create_client(url, key)
    return _supabase_client


def test_connection() -> dict[str, Any]:
    """
    Test Supabase connection by querying a simple table.

    Returns:
        Dict with connection status and user count

    Raises:
        Exception: If connection fails
    """
    try:
        supabase = get_supabase_client()

        # Query users table to verify connection
        result = supabase.table("users").select("count", count="exact").execute()  # type: ignore[arg-type]

        return {
            "status": "connected",
            "user_count": result.count,
            "supabase_url": get_supabase_settings().supabase_url,
        }

    except Exception as e:
        logger.error(f"Supabase connection test failed: {e}")
        raise
