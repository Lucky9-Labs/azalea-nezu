"""Manual, rerunnable bronze-to-silver extraction."""

import boto3

from .bronze import Source, load_sources, query_page
from .storage import get_cursor, put_cursor, write_silver_record
from .transform import normalize


def extract_source(s3, bucket: str, source: Source, page_size: int = 100, reader=None) -> int:
    reader = reader or query_page
    cursor = get_cursor(s3, bucket, source.source_id)
    while True:
        page = reader(source, cursor, page_size)
        if not page:
            return cursor
        last = cursor
        for record in page:
            seq = int(record["seq"])
            if seq <= last:
                raise ValueError("bronze sequence is not strictly increasing")
            table, row = normalize(source.source_id, record)
            write_silver_record(s3, bucket, table, row)
            last = seq
        # Never advance until every Parquet object in this page is durable.
        put_cursor(s3, bucket, source.source_id, last)
        cursor = last
        if len(page) < page_size:
            return cursor


def extract_all(bucket: str, sources_path: str, region: str = "us-west-2") -> dict[str, int | str]:
    s3 = boto3.client("s3", region_name=region)
    results = {}
    for source in load_sources(sources_path):
        try:
            results[source.source_id] = extract_source(s3, bucket, source)
        except Exception as error:
            # One offline node must not move its cursor or hide other sources.
            results[source.source_id] = f"unavailable or failed: {type(error).__name__}: {error}"
    return results
