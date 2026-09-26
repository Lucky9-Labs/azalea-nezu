-- SQLite 3.38+; all timestamps are UTC RFC 3339 text. No image bytes or secrets.
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE IF NOT EXISTS tin_device_events (
    raw_id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
    CHECK (length(raw_id) > 0 AND length(patient_id) > 0)
);

CREATE TABLE IF NOT EXISTS tin_agent_spans (
    raw_id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    trace_id TEXT NOT NULL,
    span_id TEXT NOT NULL,
    parent_span_id TEXT,
    agent_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    status TEXT NOT NULL,
    attributes_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(attributes_json))
);

CREATE TABLE IF NOT EXISTS tin_image_refs (
    raw_id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    captured_at TEXT NOT NULL,
    garage_bucket TEXT NOT NULL,
    garage_key TEXT NOT NULL,
    sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
    mime_type TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
    width_px INTEGER,
    height_px INTEGER
);

-- Edge normalization populates this table later; this repository supplies its DDL.
-- One append-only sequence is the AWS notebook's extraction cursor.
CREATE TABLE IF NOT EXISTS bronze_records (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id TEXT NOT NULL UNIQUE,
    raw_table TEXT NOT NULL CHECK (raw_table IN ('tin_device_events', 'tin_agent_spans', 'tin_image_refs')),
    raw_id TEXT NOT NULL,
    record_kind TEXT NOT NULL CHECK (record_kind IN ('event', 'span', 'media')),
    patient_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
    garage_bucket TEXT,
    garage_key TEXT,
    schema_version INTEGER NOT NULL DEFAULT 1 CHECK (schema_version = 1),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (raw_table, raw_id),
    CHECK ((record_kind = 'media') = (garage_bucket IS NOT NULL AND garage_key IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS bronze_records_patient_time
ON bronze_records (patient_id, occurred_at);
