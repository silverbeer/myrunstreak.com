"""API client for stk CLI."""

import json
import os
import sys
from pathlib import Path
from typing import Any

import httpx

from cli.display import display_error, display_info

DEFAULT_API_URL = "https://api.myrunstreak.run"
TIMEOUT = 30.0

# Config paths
CONFIG_DIR = Path.home() / ".config" / "stk"
CONFIG_FILE = CONFIG_DIR / "config.json"


def get_api_url() -> str:
    """Get API base URL from environment or use default."""
    return os.getenv("STK_API_URL", os.getenv("API_BASE_URL", DEFAULT_API_URL))


def get_user_id() -> str | None:
    """Get user_id from config file."""
    if not CONFIG_FILE.exists():
        return None
    try:
        with open(CONFIG_FILE) as f:
            config: dict[str, str] = json.load(f)
            user_id: str | None = config.get("user_id")
            return user_id
    except (json.JSONDecodeError, OSError):
        return None


def request(endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """
    Make HTTP GET request to API endpoint.

    Automatically includes user_id from config in all requests.

    Args:
        endpoint: API endpoint path (without leading slash)
        params: Optional query parameters

    Returns:
        JSON response data

    Raises:
        SystemExit: On request failure
    """
    # Get user_id from config
    user_id = get_user_id()
    if not user_id:
        display_error("Not logged in or missing user ID")
        display_info("Run 'stk auth login' to authenticate")
        sys.exit(1)

    # Add user_id to params
    if params is None:
        params = {}
    params["user_id"] = user_id

    url = f"{get_api_url()}/{endpoint}"

    try:
        response = httpx.get(url, params=params, timeout=TIMEOUT)
        response.raise_for_status()
        result: dict[str, Any] = response.json()
        return result
    except httpx.TimeoutException:
        display_error(f"Request timed out after {TIMEOUT}s")
        sys.exit(1)
    except httpx.HTTPStatusError as e:
        display_error(f"HTTP {e.response.status_code}: {e.response.text}")
        sys.exit(1)
    except httpx.RequestError as e:
        display_error(f"Request failed: {e}")
        sys.exit(1)


def post_request(
    endpoint: str,
    data: dict[str, Any] | None = None,
    params: dict[str, Any] | None = None,
    timeout: float | None = None,
) -> dict[str, Any]:
    """
    Make HTTP POST request to API endpoint.

    Automatically includes user_id from config in query params.

    Args:
        endpoint: API endpoint path (without leading slash)
        data: Request body as JSON
        params: Optional query parameters
        timeout: Optional custom timeout (for long-running operations)

    Returns:
        JSON response data

    Raises:
        SystemExit: On request failure
    """
    # Get user_id from config
    user_id = get_user_id()
    if not user_id:
        display_error("Not logged in or missing user ID")
        display_info("Run 'stk auth login' to authenticate")
        sys.exit(1)

    # Add user_id to params
    if params is None:
        params = {}
    params["user_id"] = user_id

    url = f"{get_api_url()}/{endpoint}"
    request_timeout = timeout if timeout else TIMEOUT

    try:
        response = httpx.post(url, json=data, params=params, timeout=request_timeout)
        response.raise_for_status()
        result: dict[str, Any] = response.json()
        return result
    except httpx.TimeoutException:
        display_error(f"Request timed out after {request_timeout}s")
        sys.exit(1)
    except httpx.HTTPStatusError as e:
        # Try to parse error message from response
        try:
            error_data = e.response.json()
            error_msg = error_data.get("message", e.response.text)
        except Exception:
            error_msg = e.response.text
        display_error(f"HTTP {e.response.status_code}: {error_msg}")
        sys.exit(1)
    except httpx.RequestError as e:
        display_error(f"Request failed: {e}")
        sys.exit(1)
