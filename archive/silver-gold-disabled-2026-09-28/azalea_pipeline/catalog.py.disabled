import json
from pathlib import Path

import pyarrow as pa

CATALOG_PATH = Path(__file__).resolve().parents[1] / "schemas" / "catalog.json"

_ARROW_TYPES = {
    "string": pa.string(),
    "bigint": pa.int64(),
    "int": pa.int32(),
    "timestamp": pa.timestamp("us"),
}


def load_catalog(path: Path = CATALOG_PATH) -> dict:
    return json.loads(path.read_text())


def arrow_schema(tier: str, table: str) -> pa.Schema:
    columns = load_catalog()["tables"][tier][table]
    return pa.schema([pa.field(column["name"], _ARROW_TYPES[column["type"]]) for column in columns])
