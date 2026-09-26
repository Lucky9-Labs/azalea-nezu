"""Minimal, explicit bronze to silver normalization."""

import json
from datetime import datetime, timezone


CLINICAL_FIELDS = {
    "symptom_reported": {"body_site", "symptom", "summary", "capture_request_id", "evidence_source", "data_origin"},
    "medication_supply_reported": {"medication_name", "formulation", "strength", "supply_status", "summary", "evidence_source", "data_origin"},
    "prescription_recorded": {"medication_name", "formulation", "strength", "supply_status", "summary", "evidence_source", "data_origin"},
}


def utc_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamps must include a UTC offset")
    return parsed.astimezone(timezone.utc).replace(tzinfo=None)


def normalize(source_id: str, record: dict) -> tuple[str, dict]:
    if record["schema_version"] != 1:
        raise ValueError("unsupported bronze schema version")
    kind = record["record_kind"]
    payload = json.loads(record["payload_json"])
    if not isinstance(payload, dict):
        raise ValueError("bronze payload must be an object")
    common = {
        "source_id": source_id,
        "bronze_seq": int(record["seq"]),
        "record_id": record["record_id"],
        "patient_id": record["patient_id"],
        "device_id": record["device_id"],
    }
    occurred_at = utc_timestamp(record["occurred_at"])
    if kind == "event":
        event_type = str(payload["event_type"])
        data = payload.get("data", {})
        if event_type in CLINICAL_FIELDS:
            if not isinstance(data, dict):
                raise ValueError("clinical event data must be an object")
            data = {key: value for key, value in data.items() if key in CLINICAL_FIELDS[event_type]}
            if any(not isinstance(value, str) or len(value) > 500 for value in data.values()):
                raise ValueError("clinical event fields must be bounded strings")
        return "device_events", {
            **common,
            "event_type": event_type,
            "occurred_at": occurred_at,
            "payload_json": json.dumps(data, sort_keys=True, separators=(",", ":")),
        }
    if kind == "span":
        return "agent_spans", {
            **common,
            "trace_id": str(payload["trace_id"]),
            "span_id": str(payload["span_id"]),
            "parent_span_id": payload.get("parent_span_id"),
            "agent_name": str(payload["agent_name"]),
            "operation": str(payload["operation"]),
            "started_at": utc_timestamp(payload.get("started_at", record["occurred_at"])),
            "ended_at": utc_timestamp(payload["ended_at"]) if payload.get("ended_at") else None,
            "status": str(payload["status"]),
            "attributes_json": json.dumps(payload.get("attributes", {}), sort_keys=True, separators=(",", ":")),
        }
    if kind == "media":
        if not record["garage_bucket"] or not record["garage_key"]:
            raise ValueError("media record requires a Garage reference")
        return "media_assets", {
            **common,
            "captured_at": occurred_at,
            "garage_bucket": record["garage_bucket"],
            "garage_key": record["garage_key"],
            "sha256": str(payload["sha256"]),
            "mime_type": str(payload["mime_type"]),
            "byte_count": int(payload["byte_count"]),
            "width_px": int(payload["width_px"]) if payload.get("width_px") is not None else None,
            "height_px": int(payload["height_px"]) if payload.get("height_px") is not None else None,
            "capture_request_id": str(payload["capture_request_id"]) if payload.get("capture_request_id") else None,
        }
    raise ValueError(f"unknown bronze record kind: {kind}")
