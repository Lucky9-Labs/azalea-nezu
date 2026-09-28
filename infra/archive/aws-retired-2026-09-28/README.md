# Retired Azalea Nezu AWS Terraform

Archived 2026-09-28 after tearing down the Azalea Nezu AWS deployment. Terraform source files use the `.tf.disabled` suffix so Terraform will ignore them. These files capture the teardown configuration and are not safe to apply as-is. The shared Terraform state bucket and remote state records were retained. The Azalea data KMS key is disabled and scheduled for deletion on 2026-10-05.
