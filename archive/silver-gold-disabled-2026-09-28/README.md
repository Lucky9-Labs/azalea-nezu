# Silver/Gold pipeline archive

Retired on 2026-09-28. The implementation, infrastructure helpers, notebooks, schemas, fixtures, and VPS/Garage configuration are preserved here as reference material. Runnable and deployable files carry a `.disabled` suffix. Do not remove that suffix or execute the archived deployment as-is.

The archived architecture pulled bounded Bronze pages from configured Pi/VPS sources through Tailscale, wrote one deterministic Parquet object per Bronze record to Silver, and used a manual notebook step to rebuild five Gold snapshots. Media bytes lived separately in Garage; Parquet held references and checksums. The source describes synthetic-only demo data and does not establish a safe or approved clinical workflow. The AWS resources and deploy identity were torn down; see `../..//infra/archive/aws-retired-2026-09-28/README.md` for the AWS archive.
