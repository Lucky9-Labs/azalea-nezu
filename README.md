# Azalea Nezu pipeline archive

This repository's AWS-backed Silver/Gold pipeline was retired on 2026-09-28. The
AWS resources and dedicated deploy identity were torn down. The runnable pipeline,
notebooks, VPS/Garage deployment, schemas, and fixtures are preserved under
[`archive/silver-gold-disabled-2026-09-28`](archive/silver-gold-disabled-2026-09-28)
with implementation and configuration files suffixed `.disabled`.

The current physical-device milestone is local: the Pi receives speaker status
and requested camera frames over Wi-Fi, then writes Tin and append-only Bronze
records on the Pi. Its implementation and deploy guide live in the Azaleas
repository under `devices/RaspberryPi/` and
`devices/ESP32S3Speaker/firmware/`. This repository does not run or publish that
local store into Silver or Gold.

The historical Silver/Gold architecture remains documented in the archive,
including its bounded Tailscale Bronze reader, deterministic Parquet writes,
manual Gold snapshots, and Garage media references. It is reference material;
the disabled sources and Terraform must not be applied as-is.

## AWS teardown record

The AWS Terraform is separately preserved under
[`infra/archive/aws-retired-2026-09-28`](infra/archive/aws-retired-2026-09-28).
Terraform files use `.tf.disabled`. The shared `terraform-lucky9` state bucket
and Azalea Nezu state records were retained. The data KMS key is disabled and
scheduled for deletion on 2026-10-05. The dedicated deployer access key was
revoked. See the archive README for the retained-state details.
