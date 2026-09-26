"""Read a bounded SQLite bronze page over Tailscale SSH, without a Pi daemon."""

import base64
import json
import re
import shlex
import subprocess
from dataclasses import dataclass

SOURCE_ID = re.compile(r"^[a-zA-Z0-9_-]{1,64}$")
HOST = re.compile(r"^[a-zA-Z0-9_.-]{1,255}$")

# Executed by the remote host's Python standard library. The SQL is fixed and
# parameterized; neither notebook input nor a source manifest supplies SQL.
REMOTE_SQLITE_READER = r'''
import json, sqlite3, sys
from pathlib import Path
from urllib.parse import quote
db_path, cursor, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
if not Path(db_path).is_absolute() or cursor < 0 or not 1 <= limit <= 500:
    raise SystemExit("invalid query arguments")
uri = "file:" + quote(db_path, safe="/") + "?mode=ro"
with sqlite3.connect(uri, uri=True, timeout=5) as db:
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA query_only=ON")
    rows = db.execute("""SELECT seq, record_id, raw_table, raw_id, record_kind,
      patient_id, device_id, occurred_at, payload_json, garage_bucket,
      garage_key, schema_version FROM bronze_records
      WHERE seq > ? ORDER BY seq LIMIT ?""", (cursor, limit))
    for row in rows:
        print(json.dumps(dict(row), separators=(",", ":")))
'''


@dataclass(frozen=True)
class Source:
    source_id: str
    host: str
    db_path: str = "/var/lib/azalea/bronze.sqlite3"
    ssh_user: str = "azalea-read"

    def validate(self) -> None:
        if not SOURCE_ID.fullmatch(self.source_id) or not HOST.fullmatch(self.host):
            raise ValueError("invalid source ID or Tailscale hostname")
        if not SOURCE_ID.fullmatch(self.ssh_user) or not self.db_path.startswith("/"):
            raise ValueError("invalid SSH user or SQLite path")


def load_sources(path: str) -> list[Source]:
    with open(path, encoding="utf-8") as stream:
        data = json.load(stream)
    sources = [Source(**item) for item in data["sources"]]
    if len({s.source_id for s in sources}) != len(sources):
        raise ValueError("duplicate source IDs")
    for source in sources:
        source.validate()
    return sources


def query_page(source: Source, cursor: int, limit: int = 100) -> list[dict]:
    source.validate()
    if cursor < 0 or not 1 <= limit <= 500:
        raise ValueError("invalid cursor or page size")
    encoded = base64.b64encode(REMOTE_SQLITE_READER.encode()).decode()
    python = "import base64;exec(base64.b64decode('" + encoded + "'))"
    remote_command = "python3 -c " + shlex.quote(python)
    remote_command += " " + shlex.quote(source.db_path) + f" {cursor} {limit}"
    result = subprocess.run(
        ["tailscale", "ssh", f"{source.ssh_user}@{source.host}", remote_command],
        check=True,
        text=True,
        capture_output=True,
        timeout=90,
    )
    rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    if any(row["seq"] <= cursor for row in rows):
        raise ValueError("bronze source returned a non-increasing cursor")
    return rows
