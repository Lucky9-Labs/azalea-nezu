"""Exercise the deployed stack with local synthetic bronze, without a Pi/VPS."""

import json
import sqlite3
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

import boto3

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from azalea_pipeline.bronze import REMOTE_SQLITE_READER, Source  # noqa: E402
from azalea_pipeline.extract import extract_source  # noqa: E402
from azalea_pipeline.gold import publish_gold  # noqa: E402
from azalea_pipeline.storage import read_table  # noqa: E402

BUCKET = "azalea-nezu-medallion-964028866059-us-west-2"
SOURCE = Source("demo-local-01", "local-fixture")


def make_fixture(path: Path) -> None:
    with sqlite3.connect(path) as db:
        db.executescript((ROOT / "schemas/pi_bronze.sql").read_text())
        rows = [
            (
                "demo-event-001", "tin_device_events", "raw-event-001", "event",
                "2026-09-26T19:00:00Z", {"event_type": "pulse", "data": {"bpm": 72}}, None, None,
            ),
            (
                "demo-span-001", "tin_agent_spans", "raw-span-001", "span",
                "2026-09-26T19:01:00Z", {
                    "trace_id": "demo-trace-001", "span_id": "demo-span-001",
                    "agent_name": "demo-agent", "operation": "summarize",
                    "started_at": "2026-09-26T19:01:00Z", "ended_at": "2026-09-26T19:01:02Z",
                    "status": "ok", "attributes": {"synthetic": True},
                }, None, None,
            ),
            (
                "demo-media-001", "tin_image_refs", "raw-media-001", "media",
                "2026-09-26T19:02:00Z", {
                    "sha256": "0" * 64, "mime_type": "image/jpeg",
                    "byte_count": 123, "width_px": 16, "height_px": 16,
                }, "azalea-images", "demo/placeholder.jpg",
            ),
        ]
        for record_id, raw_table, raw_id, kind, occurred_at, payload, garage_bucket, garage_key in rows:
            db.execute(
                """INSERT INTO bronze_records
                   (record_id, raw_table, raw_id, record_kind, patient_id, device_id,
                    occurred_at, payload_json, garage_bucket, garage_key)
                   VALUES (?, ?, ?, ?, 'demo-patient-001', 'demo-device-001', ?, ?, ?, ?)""",
                (record_id, raw_table, raw_id, kind, occurred_at,
                 json.dumps(payload), garage_bucket, garage_key),
            )


def local_reader(_source: Source, cursor: int, limit: int) -> list[dict]:
    result = subprocess.run(
        [sys.executable, "-c", REMOTE_SQLITE_READER, str(FIXTURE_PATH), str(cursor), str(limit)],
        check=True, capture_output=True, text=True,
    )
    return [json.loads(line) for line in result.stdout.splitlines() if line]


def assumed_s3():
    source = boto3.Session(profile_name="azalea-nezu-source", region_name="us-west-2")
    account = source.client("sts").get_caller_identity()["Account"]
    credentials = source.client("sts").assume_role(
        RoleArn=f"arn:aws:iam::{account}:role/azalea-nezu-terraform-deployer",
        RoleSessionName="azalea-synthetic-validation",
    )["Credentials"]
    return boto3.client(
        "s3", region_name="us-west-2",
        aws_access_key_id=credentials["AccessKeyId"],
        aws_secret_access_key=credentials["SecretAccessKey"],
        aws_session_token=credentials["SessionToken"],
    )


if __name__ == "__main__":
    s3 = assumed_s3()
    with TemporaryDirectory() as directory:
        FIXTURE_PATH = Path(directory) / "bronze.sqlite3"
        make_fixture(FIXTURE_PATH)
        first = extract_source(s3, BUCKET, SOURCE, page_size=2, reader=local_reader)
        second = extract_source(s3, BUCKET, SOURCE, page_size=2, reader=local_reader)
        silver = {
            table: len(read_table(s3, BUCKET, "silver", table))
            for table in ("device_events", "agent_spans", "media_assets")
        }
        gold = publish_gold(BUCKET, s3=s3)
    assert first == second == 3
    assert silver == {"device_events": 1, "agent_spans": 1, "media_assets": 1}
    assert gold == {"patient_timeline": 3, "patient_overview": 1, "trace_summaries": 1}
    print(json.dumps({"cursor_first": first, "cursor_rerun": second, "silver": silver, "gold": gold}))
