# Azalea Nezu medallion demo

Synthetic-data hackathon stack for device and agent traces. **Do not put real patient data into this deployment.** Identity-based patient authorization, consent enforcement, resilient edge storage, and clinical validation are not provided.

| Tier | Home | Contents |
| --- | --- | --- |
| Tin | Pi or VPS SQLite | Three raw tables: events, agent spans, image metadata |
| Bronze | Pi or VPS SQLite | Append-only canonical `bronze_records` and sequence cursor |
| Silver | Lucky9 `us-west-2` S3 + Athena | Typed Parquet events, spans, and media references |
| Gold | Lucky9 `us-west-2` S3 + Athena | Patient timeline, overview, and trace summaries |

Garage on the VPS holds image **bytes**; SQLite and Parquet hold only bucket, key, checksum, and metadata. One SageMaker notebook instance in the existing Lucky9 core VPC pulls bounded bronze pages through Tailscale SSH. Its SSH command runs a fixed parameterized SQLite `SELECT`, so the notebook does not need an HTTP service or a networked SQLite server on the Pi. Two notebooks are delivered: bronze to silver, then silver to gold. Execution is manual.

## Repository contents

- `schemas/pi_bronze.sql`: Pi and VPS SQLite DDL. Edge capture and tin-to-bronze writes are separate work.
- `schemas/catalog.json`: single column/type manifest used by PyArrow and Terraform Glue tables.
- `azalea_pipeline/` and `notebooks/`: runnable copy-and-normalize logic and manual notebook entrypoints.
- `infra/bootstrap/`: one-time Lucky9 Terraform role and empty Tailscale auth secret.
- `infra/stack/`: encrypted S3, Glue, Athena, IAM, networking, and optional SageMaker notebook.
- `vps/` and `network/`: Garage Compose deployment and tailnet policy fragment.

## Bronze producer contract

Use SQLite 3.38+ and apply `schemas/pi_bronze.sql` to `/var/lib/azalea/bronze.sqlite3`. Tin writers insert into their matching raw table. An edge normalizer, outside this repository, appends to `bronze_records` with a unique `record_id` and matching `(raw_table, raw_id)`. Never update or delete a published bronze sequence. All timestamps include an offset and represent an instant; the AWS pipeline converts them to UTC.

`payload_json` is a JSON object. For `event`, use `{"event_type":"wake","data":{...}}`. For `span`, use `{"trace_id":"...","span_id":"...","parent_span_id":null,"agent_name":"...","operation":"...","started_at":"...","ended_at":null,"status":"ok","attributes":{...}}`. For `media`, use `{"sha256":"64 lowercase hex digits","mime_type":"image/jpeg","byte_count":123,"width_px":640,"height_px":480}` and populate `garage_bucket`/`garage_key`. Raw prompts, Wi-Fi passwords, images, and credentials must not be placed in these JSON objects.

Each source node must:

1. Join the tailnet with `tag:azalea-edge` or `tag:azalea-vps`, and enable Tailscale SSH (`tailscale up --ssh`). Merge `network/tailnet-fragment.hujson` into the **existing** tailnet policy; do not replace unrelated rules. The notebook auth key must carry `tag:azalea-notebook`.
2. Expose a local Unix account named `azalea-read` to Tailscale SSH. Give it read and directory traversal permission for `/var/lib/azalea/bronze.sqlite3`, with no write permission. `python3` must be available. Keep SSH and the SQLite file off public interfaces.
3. Maintain the same DDL, including `bronze_records.seq`. Add the node's Tailscale MagicDNS hostname to `config/sources.json` on the notebook, using `config/sources.example.json` as the shape. `source_id` is stable and unique.
4. On the VPS, create the `azalea-read` Unix user, run `vps/setup-vps.sh`, set `TAILSCALE_IPV4` in the generated private `.env`, then `docker compose up -d` from `vps/` with a rootful Docker engine. Compose initializes `vps/bronze/bronze.sqlite3` as a persistent bind volume. The file is owned by root and group-readable by `azalea-read`; the read account cannot write it. The Garage S3 port binds only to that Tailscale IP; RPC and admin ports are not published. The Pi may upload images to `http://<vps-tailscale-ip>:3900` with the generated Garage key using path-style S3 requests and region `garage`. Back up `vps/data/` and `vps/bronze/` separately; this single-node Garage configuration has no replica.

The connector runs `SELECT seq, ... FROM bronze_records WHERE seq > ? ORDER BY seq LIMIT ?` over Tailscale SSH, in SQLite `mode=ro` with `PRAGMA query_only=ON`. An unreachable node or invalid record leaves its S3 cursor unchanged. The notebook never reads image bytes from Garage.

## AWS deployment

Use Terraform **1.10+** and AWS profile `Lucky9 Root` for bootstrap. The existing `terraform-lucky9` state bucket, core VPC, private subnet in `us-west-2a`, NAT, and S3 endpoint are reused. No `infra-core` files or resources are modified. Both Terraform states live under the new `azalea-nezu/` key prefix. The bootstrap profile currently authenticates as the account root identity. AWS does not let root assume an IAM role, so bootstrap also creates an IAM source user whose only permission is to assume the Azalea deploy role. Its key is created outside Terraform state in a separate mode-0600 credentials file. All main stack API calls and backend access then assume the deploy role.

1. In `infra/bootstrap`, run `terraform init`, `terraform plan`, and `terraform apply`. Review the plan before apply. Record the `tailscale_auth_secret_arn` output. Run `python create-source-key.py` once. The script does not print the secret key.
2. Set `AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/azalea-nezu-credentials"` when running Terraform in `infra/stack`. Its backend and provider use the `azalea-nezu-source` profile to assume `azalea-nezu-terraform-deployer`.
3. Create a reusable, tagged Tailscale auth key in the tailnet admin console. Set its secret value in the new Secrets Manager entry **outside Terraform**; never put it in a variable file, shell history, or the repository. Merge the tailnet policy fragment.
4. In `infra/stack`, run `terraform init`, `terraform plan`, and `terraform apply`. The default `enable_notebook=false` deploys the data lake and catalog without requiring connected Pi/VPS nodes. Once the secret is populated, run `terraform plan -var='enable_notebook=true'` and apply the reviewed plan to create the private notebook.
5. In SageMaker, open `azalea-nezu-medallion`. The lifecycle configuration copies this repo's notebooks and package from the artifacts bucket to `/home/ec2-user/SageMaker/azalea-nezu`. Copy `config/sources.example.json` to `config/sources.json`, edit the two hostnames, and run notebook 01 then 02. No scheduled runs are configured.

The notebook has no public inbound security group rule and no SageMaker direct internet interface. Its private subnet has NAT for outbound HTTPS; Tailscale uses userspace networking and SSH. Only the `azalea-nezu-gold-reader` role is intended for an agent backend. For the synthetic demo it trusts the notebook role; change the trust principal when an agent backend exists. It can query the gold workgroup and read gold/result S3 prefixes, but has no silver object or catalog permission. Example SQL is in `schemas/agent_queries.sql`. Patient filters in these examples are **not** authorization controls.

## Durability and verification

Silver uses one deterministic Parquet object per bronze record (`source_id` and sequence in the key). This intentionally favors simple idempotence over large-file efficiency for the hackathon. The cursor in `control/cursors/<source_id>.json` advances only after a page's objects are durable. A retry skips existing keys. Gold rebuilds from silver and replaces three `current.parquet` snapshots; S3 versioning retains previous versions.

Install the package and pytest in a local virtual environment, then run `python -m pytest -q`, `terraform fmt -check -recursive infra`, and `terraform validate` in both Terraform directories. To validate AWS before the nodes join, run `AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/azalea-nezu-credentials" python scripts/seed_synthetic.py`. That script executes the Pi DDL against a temporary local SQLite fixture, uses the fixed bounded reader, writes three silver Parquet records, reruns extraction to check the unchanged cursor, and publishes gold. It uploads only synthetic rows; its Garage reference is a placeholder and no image is uploaded. Query all six Athena tables for counts of `1, 1, 1` in silver and `3, 1, 1` in gold. IAM policy simulation should allow gold `s3:GetObject` and deny silver `s3:GetObject` for `azalea-nezu-gold-reader`.

The deployed demo currently includes the data lake, catalog, workgroups, IAM roles, and synthetic rows. The SageMaker instance remains disabled until the external Tailscale auth key is populated, the tailnet policy is merged, and the Pi/VPS nodes join. Empty tables or unreachable nodes do not imply zero device activity.
