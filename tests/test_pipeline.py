import json
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest
from botocore.exceptions import ClientError

from azalea_pipeline import bronze, extract, gold
from azalea_pipeline.storage import get_cursor, read_table


class FakeBody:
    def __init__(self, content):
        self.content = content

    def read(self):
        return self.content


class FakePaginator:
    def __init__(self, objects):
        self.objects = objects

    def paginate(self, Bucket, Prefix):
        yield {"Contents": [{"Key": key} for key in self.objects if key.startswith(Prefix)]}


class FakeS3:
    def __init__(self):
        self.objects = {}
        self.fail_on_key = None

    def _missing(self):
        raise ClientError({"Error": {"Code": "NoSuchKey", "Message": "missing"}}, "GetObject")

    def head_object(self, Bucket, Key):
        if Key not in self.objects:
            self._missing()
        return {}

    def get_object(self, Bucket, Key):
        if Key not in self.objects:
            self._missing()
        return {"Body": FakeBody(self.objects[Key])}

    def put_object(self, Bucket, Key, Body, **kwargs):
        if Key == self.fail_on_key:
            raise RuntimeError("simulated S3 failure")
        self.objects[Key] = Body

    def get_paginator(self, operation):
        assert operation == "list_objects_v2"
        return FakePaginator(self.objects)


def event(seq, record_id=None):
    return {
        "seq": seq, "record_id": record_id or f"event-{seq}",
        "raw_table": "tin_device_events", "raw_id": f"raw-{seq}",
        "record_kind": "event", "patient_id": "demo-patient-001",
        "device_id": "pi-01", "occurred_at": "2026-09-26T12:00:00-07:00",
        "payload_json": json.dumps({"event_type": "wake", "data": {"count": seq}}),
        "garage_bucket": None, "garage_key": None, "schema_version": 1,
    }


def test_sqlite_contract_and_fixed_remote_reader(tmp_path):
    db_path = tmp_path / "bronze.sqlite3"
    with sqlite3.connect(db_path) as db:
        db.executescript((Path(__file__).parents[1] / "schemas/pi_bronze.sql").read_text())
        db.execute(
            "INSERT INTO bronze_records (record_id, raw_table, raw_id, record_kind, patient_id, device_id, occurred_at, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ("event-1", "tin_device_events", "raw-1", "event", "demo-patient-001", "pi-01", "2026-09-26T19:00:00Z", '{"event_type":"wake"}'),
        )
    result = subprocess.run(
        [sys.executable, "-c", bronze.REMOTE_SQLITE_READER, str(db_path), "0", "10"],
        check=True, capture_output=True, text=True,
    )
    assert json.loads(result.stdout)["seq"] == 1


def test_cursor_stays_put_and_rerun_is_idempotent(monkeypatch):
    s3 = FakeS3()
    source = bronze.Source("demo-pi-01", "pi.example-tailnet.ts.net")
    rows = [event(1), event(2)]
    monkeypatch.setattr(extract, "query_page", lambda _source, cursor, _limit: [r for r in rows if r["seq"] > cursor])
    s3.fail_on_key = "silver/device_events/demo-pi-01-00000000000000000002.parquet"
    with pytest.raises(RuntimeError, match="simulated S3 failure"):
        extract.extract_source(s3, "demo-bucket", source)
    assert get_cursor(s3, "demo-bucket", source.source_id) == 0
    s3.fail_on_key = None
    assert extract.extract_source(s3, "demo-bucket", source) == 2
    assert extract.extract_source(s3, "demo-bucket", source) == 2
    silver = read_table(s3, "demo-bucket", "silver", "device_events")
    assert len(silver) == 2
    assert silver[0]["occurred_at"].hour == 19
    snapshots = gold.build_gold(silver, [], [])
    assert snapshots["patient_overview"][0]["event_count"] == 2


def test_invalid_timestamp_does_not_advance_cursor(monkeypatch):
    s3 = FakeS3()
    source = bronze.Source("demo-pi-01", "pi.example-tailnet.ts.net")
    bad = event(1)
    bad["occurred_at"] = "2026-09-26T12:00:00"
    monkeypatch.setattr(extract, "query_page", lambda *_args: [bad])
    with pytest.raises(ValueError, match="UTC offset"):
        extract.extract_source(s3, "demo-bucket", source)
    assert get_cursor(s3, "demo-bucket", source.source_id) == 0
