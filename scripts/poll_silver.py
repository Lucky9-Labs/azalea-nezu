#!/usr/bin/env python3
"""Continuously pull configured Pi/VPS bronze sources into Silver."""

import argparse
import fcntl
import json
import logging
import signal
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from azalea_pipeline.bronze import load_sources
from azalea_pipeline.extract import extract_all


def load_runtime_config(repo: Path) -> tuple[dict, Path]:
    deployment_path = repo / "deployment.json"
    sources_path = repo / "config" / "sources.json"
    deployment = json.loads(deployment_path.read_text(encoding="utf-8"))
    if not all(deployment.get(key) for key in ("medallion_bucket", "region")):
        raise ValueError("deployment config needs medallion_bucket and region")
    if not load_sources(str(sources_path)):
        raise ValueError("no Bronze sources are configured")
    return deployment, sources_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--interval-seconds", type=int, default=30)
    parser.add_argument("--lock-file", type=Path, default=Path("/home/ec2-user/SageMaker/.azalea-silver-poll.lock"))
    args = parser.parse_args()
    if args.interval_seconds < 5:
        parser.error("interval must be at least 5 seconds")

    repo = args.repo.resolve()
    try:
        deployment, sources_path = load_runtime_config(repo)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(f"poller configuration is unavailable ({type(error).__name__})")
    args.lock_file.parent.mkdir(parents=True, exist_ok=True)
    lock = args.lock_file.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        logging.info("Silver poller already running")
        return

    stopped = False

    def stop(_signum, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    while not stopped:
        started = time.monotonic()
        try:
            result = extract_all(deployment["medallion_bucket"], str(sources_path), deployment["region"])
            logging.info("silver pull result: %s", json.dumps(result, sort_keys=True))
        except Exception as error:
            logging.error("silver pull unavailable: %s", type(error).__name__)
        remaining = max(0.0, args.interval_seconds - (time.monotonic() - started))
        if not stopped:
            time.sleep(remaining)


if __name__ == "__main__":
    main()
