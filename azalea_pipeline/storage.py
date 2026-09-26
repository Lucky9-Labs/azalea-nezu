"""Small S3 Parquet and cursor primitives shared by both notebooks."""

import io
import json

import pyarrow as pa
import pyarrow.parquet as pq
from botocore.exceptions import ClientError

from .catalog import arrow_schema


def _missing(error: ClientError) -> bool:
    return error.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound")


def get_cursor(s3, bucket: str, source_id: str) -> int:
    try:
        body = s3.get_object(Bucket=bucket, Key=f"control/cursors/{source_id}.json")["Body"].read()
    except ClientError as error:
        if _missing(error):
            return 0
        raise
    return int(json.loads(body)["last_seq"])


def put_cursor(s3, bucket: str, source_id: str, seq: int) -> None:
    s3.put_object(
        Bucket=bucket,
        Key=f"control/cursors/{source_id}.json",
        Body=json.dumps({"last_seq": seq}, separators=(",", ":")).encode(),
        ContentType="application/json",
    )


def object_exists(s3, bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as error:
        if _missing(error):
            return False
        raise


def parquet_bytes(tier: str, table: str, rows: list[dict]) -> bytes:
    schema = arrow_schema(tier, table)
    arrow_table = pa.Table.from_pylist(rows, schema=schema)
    output = io.BytesIO()
    pq.write_table(arrow_table, output, compression="zstd")
    return output.getvalue()


def write_silver_record(s3, bucket: str, table: str, row: dict) -> str:
    key = f"silver/{table}/{row['source_id']}-{row['bronze_seq']:020d}.parquet"
    if not object_exists(s3, bucket, key):
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=parquet_bytes("silver", table, [row]),
            ContentType="application/vnd.apache.parquet",
        )
    return key


def read_table(s3, bucket: str, tier: str, table: str) -> list[dict]:
    rows = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{tier}/{table}/"):
        for item in page.get("Contents", []):
            key = item["Key"]
            if key.endswith(".parquet"):
                body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
                rows.extend(pq.read_table(io.BytesIO(body)).to_pylist())
    return rows


def write_gold_table(s3, bucket: str, table: str, rows: list[dict]) -> None:
    s3.put_object(
        Bucket=bucket,
        Key=f"gold/{table}/current.parquet",
        Body=parquet_bytes("gold", table, rows),
        ContentType="application/vnd.apache.parquet",
    )
