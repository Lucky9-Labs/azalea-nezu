import json
from pathlib import Path

import pytest

from scripts.poll_silver import load_runtime_config


def configured_repo(tmp_path: Path, sources: list[dict]) -> Path:
    (tmp_path / "deployment.json").write_text(json.dumps({
        "medallion_bucket": "test-medallion", "region": "us-west-2",
    }))
    config = tmp_path / "config"
    config.mkdir()
    (config / "sources.json").write_text(json.dumps({"sources": sources}))
    return tmp_path


def test_poller_requires_at_least_one_bronze_source(tmp_path):
    repo = configured_repo(tmp_path, [])
    with pytest.raises(ValueError, match="no Bronze sources"):
        load_runtime_config(repo)


def test_poller_loads_deployment_and_sources(tmp_path):
    source = {"source_id": "demo-pi", "host": "azalea-pi.example.ts.net"}
    repo = configured_repo(tmp_path, [source])
    deployment, sources_path = load_runtime_config(repo)
    assert deployment == {"medallion_bucket": "test-medallion", "region": "us-west-2"}
    assert sources_path == repo / "config" / "sources.json"


def test_poller_rejects_incomplete_deployment_config(tmp_path):
    repo = configured_repo(tmp_path, [{"source_id": "demo-pi", "host": "azalea-pi.example.ts.net"}])
    (repo / "deployment.json").write_text(json.dumps({"medallion_bucket": "test-medallion"}))
    with pytest.raises(ValueError, match="deployment config"):
        load_runtime_config(repo)
