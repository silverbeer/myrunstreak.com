#!/usr/bin/env python3
"""
Query script to display per-mile splits data.
"""

import logging
from pathlib import Path

from src.shared.duckdb_ops import DuckDBManager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATA_DIR = Path("./data")
DUCKDB_FILE = DATA_DIR / "runs.duckdb"


def main():
    """Display splits analysis."""
    db_manager = DuckDBManager(str(DUCKDB_FILE))

    with db_manager as conn:
        # Fastest mile splits
        print("=" * 100)
        print("Fastest Mile Splits - October 2025")
        print("=" * 100)
        print()

        fastest_splits = conn.execute("""
            SELECT
                start_date,
                split_number,
                pace_minutes,
                pace_seconds,
                heart_rate,
                split_elevation_gain_meters,
                run_total_miles,
                run_avg_pace_min_per_mile
            FROM fastest_mile_splits
            ORDER BY split_pace_min_per_mile ASC
            LIMIT 20
        """).fetchall()

        print(f"{'Date':<12} {'Mile':<6} {'Pace':<8} {'HR':<5} {'Elev+':<8} {'Run Dist':<10} {'Run Avg':<10}")
        print("-" * 100)

        for row in fastest_splits:
            date, split_num, pace_min, pace_sec, hr, elev, dist, avg_pace = row
            pace_str = f"{pace_min}:{pace_sec:02d}" if pace_min and pace_sec else "N/A"
            hr_str = str(int(hr)) if hr else "N/A"
            elev_str = f"{elev:.0f}m" if elev else "N/A"
            dist_str = f"{dist:.2f}mi"
            avg_str = f"{avg_pace:.1f}" if avg_pace else "N/A"

            print(f"{date} Mile {split_num:<4} {pace_str:<8} {hr_str:<5} {elev_str:<8} {dist_str:<10} {avg_str:<10}")

        print()
        print("=" * 100)
        print()

        # Average pace by mile number (e.g., are first miles faster?)
        print("=" * 100)
        print("Average Pace by Mile Number (October 2025)")
        print("=" * 100)
        print()

        pace_by_mile = conn.execute("""
            SELECT
                split_number,
                COUNT(*) as num_splits,
                AVG(split_pace_min_per_mile) as avg_pace,
                MIN(split_pace_min_per_mile) as best_pace,
                MAX(split_pace_min_per_mile) as slowest_pace
            FROM splits_miles
            WHERE split_distance_miles >= 0.9  -- Only count near-full miles
            GROUP BY split_number
            ORDER BY split_number
        """).fetchall()

        print(f"{'Mile #':<8} {'Count':<8} {'Avg Pace':<12} {'Best Pace':<12} {'Slowest Pace':<12}")
        print("-" * 100)

        for row in pace_by_mile:
            mile_num, count, avg, best, slowest = row
            avg_min = int(avg)
            avg_sec = int((avg - avg_min) * 60)
            best_min = int(best)
            best_sec = int((best - best_min) * 60)
            slow_min = int(slowest)
            slow_sec = int((slowest - slow_min) * 60)

            avg_pace_str = f"{avg_min}:{avg_sec:02d}"
            best_pace_str = f"{best_min}:{best_sec:02d}"
            slow_pace_str = f"{slow_min}:{slow_sec:02d}"
            print(f"Mile {mile_num:<3} {count:<8} {avg_pace_str:<12} {best_pace_str:<12} {slow_pace_str:<12}")

        print()
        print("=" * 100)
        print()

        # Show a sample run with all its splits
        print("=" * 100)
        print("Sample Run with Mile Splits (Oct 29, 2025)")
        print("=" * 100)
        print()

        sample_run = conn.execute("""
            SELECT
                split_number,
                split_distance_miles,
                split_seconds,
                pace_minutes,
                pace_seconds,
                heart_rate,
                cumulative_distance_miles,
                cumulative_seconds
            FROM splits_miles
            WHERE start_date = '2025-10-29'
            ORDER BY split_number
        """).fetchall()

        print(f"{'Mile':<6} {'Distance':<10} {'Time':<10} {'Pace':<10} {'HR':<5} {'Cumul Dist':<12} {'Cumul Time':<12}")
        print("-" * 100)

        for row in sample_run:
            split_num, dist, time_sec, pace_min, pace_sec, hr, cum_dist, cum_time = row
            dist_str = f"{dist:.2f}mi"
            time_min = int(time_sec // 60)
            time_sec_rem = int(time_sec % 60)
            time_str = f"{time_min}:{time_sec_rem:02d}"
            pace_str = f"{pace_min}:{pace_sec:02d}" if pace_min and pace_sec else "N/A"
            hr_str = str(int(hr)) if hr else "N/A"
            cum_dist_str = f"{cum_dist:.2f}mi"
            cum_time_min = int(cum_time // 60)
            cum_time_sec = int(cum_time % 60)
            cum_time_str = f"{cum_time_min}:{cum_time_sec:02d}"

            print(f"{split_num:<6} {dist_str:<10} {time_str:<10} {pace_str:<10} {hr_str:<5} {cum_dist_str:<12} {cum_time_str:<12}")

        print()
        print("=" * 100)


if __name__ == "__main__":
    main()
