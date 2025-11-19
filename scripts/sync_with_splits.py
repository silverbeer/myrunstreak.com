#!/usr/bin/env python3
"""
Test script to sync runs WITH per-mile splits data.

Usage:
    python scripts/sync_with_splits.py
"""

import json
import logging
from datetime import date
from pathlib import Path

from src.shared.duckdb_ops import DuckDBManager, RunRepository
from src.shared.smashrun import SmashRunAPIClient

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

DATA_DIR = Path("./data")
TOKENS_FILE = DATA_DIR / "smashrun_tokens.json"
DUCKDB_FILE = DATA_DIR / "runs.duckdb"


def load_tokens() -> dict:
    """Load tokens from local file."""
    with open(TOKENS_FILE) as f:
        return json.load(f)


def main():
    """Sync October runs with splits data."""
    print("=" * 70)
    print("Syncing October 2025 Runs WITH Per-Mile Splits")
    print("=" * 70)

    # Load tokens
    tokens = load_tokens()
    access_token = tokens["access_token"]

    # Initialize database
    db_manager = DuckDBManager(str(DUCKDB_FILE))

    if not db_manager.table_exists("runs"):
        logger.info("Initializing database schema")
        db_manager.initialize_schema()

    # Sync runs for October
    with SmashRunAPIClient(access_token=access_token) as api_client:
        # Get user info
        user_info = api_client.get_user_info()
        logger.info(f"Authenticated as: {user_info.get('userName')}")

        # Fetch activities for October 2025
        since_date = date(2025, 10, 1)
        logger.info(f"Fetching activities since {since_date}...")
        activities = api_client.get_all_activities_since(since_date)
        logger.info(f"Found {len(activities)} activities")

        # Filter to only October
        october_activities = [
            act for act in activities if act.get("startDateTimeLocal", "").startswith("2025-10")
        ]
        logger.info(f"Filtered to {len(october_activities)} October activities")

        with db_manager as conn:
            repo = RunRepository(conn)

            runs_synced = 0
            splits_synced = 0

            for activity_data in october_activities:
                try:
                    # Parse and store the run
                    activity = api_client.parse_activity(activity_data)
                    repo.upsert_run(activity)
                    runs_synced += 1

                    # Fetch and store per-mile splits
                    logger.info(f"Fetching splits for activity {activity.activity_id}")
                    splits_data = api_client.get_activity_splits(activity.activity_id, unit="mi")

                    if splits_data:
                        splits = api_client.parse_splits(splits_data)
                        repo.upsert_splits(activity.activity_id, splits, unit="mi")
                        splits_synced += len(splits)
                        logger.info(f"  Stored {len(splits)} mile splits")
                    else:
                        logger.info("  No splits data available")

                    logger.info(
                        f"✓ Synced: {activity.start_date_time_local.date()} - "
                        f"{activity.distance_miles:.2f} mi - "
                        f"{len(splits_data) if splits_data else 0} splits"
                    )

                except Exception as e:
                    logger.error(f"Failed to process activity: {e}")
                    continue

    print("\n" + "=" * 70)
    print("Sync Complete!")
    print("=" * 70)
    print(f"✓ Synced {runs_synced} runs")
    print(f"✓ Stored {splits_synced} total mile splits")
    print(f"✓ Database: {DUCKDB_FILE.absolute()}")
    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nAborted by user.")
    except Exception as e:
        logger.exception(f"Sync failed: {e}")
        print("\n❌ Sync failed. Check logs above for details.")
