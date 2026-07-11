"""
garmin_sleep_fetch.py
====================
Fetch sleep-stage data from Garmin Connect and print normalized output.

Requires:
    pip install garminconnect

Credentials are read from environment variables by default:
    GARMIN_EMAIL
    GARMIN_PASSWORD

Usage examples:
    python garmin_sleep_fetch.py --date 2026-07-10 --format json
    python garmin_sleep_fetch.py --date 2026-07-10 --format env
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import date, datetime
from typing import Any


def _to_minutes(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, bool):
        return 0
    try:
        n = float(value)
    except Exception:
        return 0

    # Garmin often returns seconds for stage fields.
    if n > 1000:
        return int(round(n / 60.0))
    return int(round(n))


def _find_first(mapping: dict[str, Any], keys: list[str]) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return None


def _pick_sleep_dict(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        if "dailySleepDTO" in raw and isinstance(raw["dailySleepDTO"], dict):
            return raw["dailySleepDTO"]
        return raw
    raise RuntimeError("Garmin sleep payload is not a dictionary.")


def normalize_sleep_payload(raw_payload: dict[str, Any], target_min: int, query_date: str) -> dict[str, Any]:
    data = _pick_sleep_dict(raw_payload)

    deep = _to_minutes(_find_first(data, ["deepSleepSeconds", "deepSleepMinutes", "deep"] ))
    light = _to_minutes(_find_first(data, ["lightSleepSeconds", "lightSleepMinutes", "light"] ))
    rem = _to_minutes(_find_first(data, ["remSleepSeconds", "remSleepMinutes", "rem"] ))

    total = _to_minutes(
        _find_first(
            data,
            [
                "sleepTimeSeconds",
                "totalSleepSeconds",
                "sleepTimeMinutes",
                "totalSleepMinutes",
                "duration",
            ],
        )
    )

    if total <= 0:
        total = max(deep + light + rem, 0)

    awake = _to_minutes(
        _find_first(data, ["awakeSleepSeconds", "awakeSleepMinutes", "awakeTimeSeconds", "awake"])
    )

    return {
        "date": query_date,
        "target_sleep_min": int(target_min),
        "total_sleep_min": int(total),
        "deep_min": int(max(deep, 0)),
        "light_min": int(max(light, 0)),
        "rem_min": int(max(rem, 0)),
        "awake_min": int(max(awake, 0)),
    }


def fetch_from_garmin(query_date: str, email: str, password: str) -> dict[str, Any]:
    try:
        from garminconnect import Garmin
    except Exception as exc:
        raise RuntimeError("garminconnect package is not installed. Run: pip install garminconnect") from exc

    client = Garmin(email=email, password=password)
    client.login()

    candidates = [
        "get_sleep_data",
        "get_daily_sleep_data",
        "get_sleep_score",
    ]

    for name in candidates:
        method = getattr(client, name, None)
        if method is None:
            continue
        try:
            payload = method(query_date)
            if payload:
                return payload
        except TypeError:
            try:
                payload = method(datetime.strptime(query_date, "%Y-%m-%d").date())
                if payload:
                    return payload
            except Exception:
                continue
        except Exception:
            continue

    raise RuntimeError("Unable to fetch sleep data from Garmin with available API methods.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch normalized Garmin sleep data")
    parser.add_argument("--date", default=date.today().isoformat(), help="Date in YYYY-MM-DD")
    parser.add_argument("--target", type=int, default=480, help="Target sleep in minutes")
    parser.add_argument("--format", choices=["json", "env"], default="json", help="Output format")
    parser.add_argument("--email", default=os.getenv("GARMIN_EMAIL", ""), help="Garmin email")
    parser.add_argument("--password", default=os.getenv("GARMIN_PASSWORD", ""), help="Garmin password")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    try:
        datetime.strptime(args.date, "%Y-%m-%d")
    except ValueError as exc:
        raise SystemExit("--date must be in YYYY-MM-DD format") from exc

    if not args.email or not args.password:
        raise SystemExit("Missing Garmin credentials. Set GARMIN_EMAIL and GARMIN_PASSWORD or pass --email/--password.")

    raw = fetch_from_garmin(args.date, args.email, args.password)
    result = normalize_sleep_payload(raw, args.target, args.date)

    if args.format == "env":
        print(f"TARGET_SLEEP_MIN={result['target_sleep_min']}")
        print(f"TOTAL_SLEEP_MIN={result['total_sleep_min']}")
        print(f"DEEP_MIN={result['deep_min']}")
        print(f"LIGHT_MIN={result['light_min']}")
        print(f"REM_MIN={result['rem_min']}")
        print(f"AWAKE_MIN={result['awake_min']}")
    else:
        print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
