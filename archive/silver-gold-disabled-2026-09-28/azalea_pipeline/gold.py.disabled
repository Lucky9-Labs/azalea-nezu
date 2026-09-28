"""Rebuild small synthetic gold snapshots from durable silver Parquet."""

import json
from collections import defaultdict

import boto3

from .storage import read_table, write_gold_table


def build_gold(events: list[dict], spans: list[dict], media: list[dict]) -> dict[str, list[dict]]:
    timeline = []
    medical_events = []
    prescription_events = []
    overview = defaultdict(lambda: {
        "latest_activity_at": None,
        "event_count": 0,
        "span_count": 0,
        "media_count": 0,
        "error_span_count": 0,
    })
    traces = {}
    photos_by_request = {}
    for asset in media:
        request_id = asset.get("capture_request_id")
        if request_id:
            key = (asset["patient_id"], request_id)
            if key in photos_by_request:
                raise ValueError("multiple photos for one patient capture request")
            photos_by_request[key] = asset

    def activity(patient_id, when):
        current = overview[patient_id]["latest_activity_at"]
        if current is None or when > current:
            overview[patient_id]["latest_activity_at"] = when

    for event in events:
        patient_id = event["patient_id"]
        when = event["occurred_at"]
        event_type = event["event_type"]
        if event_type in {"symptom_reported", "medication_supply_reported", "prescription_recorded"}:
            data = json.loads(event["payload_json"])
            if not isinstance(data, dict):
                raise ValueError("clinical silver payload must be an object")
            common = {
                "patient_id": patient_id, "event_id": event["record_id"],
                "occurred_at": when, "event_type": event_type,
                "summary": data.get("summary"), "source_id": event["source_id"],
                "device_id": event["device_id"], "evidence_source": data.get("evidence_source"),
                "data_origin": data.get("data_origin"),
            }
            if event_type == "symptom_reported":
                request_id = data.get("capture_request_id")
                photo = photos_by_request.get((patient_id, request_id)) if request_id else None
                medical_events.append({
                    **common, "body_site": data.get("body_site"), "symptom": data.get("symptom"),
                    "capture_request_id": request_id,
                    "trace_id": request_id,
                    "photo_record_id": photo["record_id"] if photo else None,
                    "photo_captured_at": photo["captured_at"] if photo else None,
                    "photo_garage_bucket": photo["garage_bucket"] if photo else None,
                    "photo_garage_key": photo["garage_key"] if photo else None,
                    "photo_sha256": photo["sha256"] if photo else None,
                })
            else:
                prescription_events.append({
                    **common, "medication_name": data.get("medication_name"),
                    "formulation": data.get("formulation"), "strength": data.get("strength"),
                    "supply_status": data.get("supply_status"),
                    "capture_request_id": data.get("capture_request_id"),
                    "trace_id": data.get("capture_request_id"),
                })
        activity(patient_id, when)
        overview[patient_id]["event_count"] += 1
        timeline.append({
            "patient_id": patient_id, "occurred_at": when, "kind": "event",
            "summary": event["event_type"], "source_id": event["source_id"],
            "record_id": event["record_id"], "garage_bucket": None, "garage_key": None,
        })
    for span in spans:
        patient_id = span["patient_id"]
        when = span["started_at"]
        activity(patient_id, when)
        overview[patient_id]["span_count"] += 1
        failed = span["status"].lower() in {"error", "failed"}
        overview[patient_id]["error_span_count"] += int(failed)
        timeline.append({
            "patient_id": patient_id, "occurred_at": when, "kind": "span",
            "summary": f"{span['operation']}: {span['status']}",
            "source_id": span["source_id"], "record_id": span["record_id"],
            "garage_bucket": None, "garage_key": None,
        })
        key = (patient_id, span["trace_id"])
        trace = traces.setdefault(key, {
            "patient_id": patient_id, "trace_id": span["trace_id"],
            "first_started_at": when, "last_ended_at": span["ended_at"] or when,
            "span_count": 0, "error_span_count": 0,
        })
        trace["first_started_at"] = min(trace["first_started_at"], when)
        trace["last_ended_at"] = max(trace["last_ended_at"], span["ended_at"] or when)
        trace["span_count"] += 1
        trace["error_span_count"] += int(failed)
    for asset in media:
        patient_id = asset["patient_id"]
        when = asset["captured_at"]
        activity(patient_id, when)
        overview[patient_id]["media_count"] += 1
        timeline.append({
            "patient_id": patient_id, "occurred_at": when, "kind": "media",
            "summary": asset["mime_type"], "source_id": asset["source_id"],
            "record_id": asset["record_id"],
            "garage_bucket": asset["garage_bucket"], "garage_key": asset["garage_key"],
        })

    return {
        "medical_events_gold": sorted(medical_events, key=lambda row: (row["patient_id"], row["occurred_at"], row["event_id"])),
        "prescription_events_gold": sorted(prescription_events, key=lambda row: (row["patient_id"], row["occurred_at"], row["event_id"])),
        "patient_timeline": sorted(timeline, key=lambda row: (row["patient_id"], row["occurred_at"], row["record_id"])),
        "patient_overview": [
            {"patient_id": patient_id, **row} for patient_id, row in sorted(overview.items())
        ],
        "trace_summaries": [traces[key] for key in sorted(traces)],
    }


def publish_gold(bucket: str, region: str = "us-west-2", s3=None) -> dict[str, int]:
    s3 = s3 or boto3.client("s3", region_name=region)
    tables = build_gold(
        read_table(s3, bucket, "silver", "device_events"),
        read_table(s3, bucket, "silver", "agent_spans"),
        read_table(s3, bucket, "silver", "media_assets"),
    )
    for table, rows in tables.items():
        write_gold_table(s3, bucket, table, rows)
    return {name: len(rows) for name, rows in tables.items()}
