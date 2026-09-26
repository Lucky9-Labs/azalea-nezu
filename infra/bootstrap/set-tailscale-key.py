"""Interactively store a Tailscale auth key without shell history or Terraform state."""

import getpass

import boto3

ACCOUNT = "964028866059"
SECRET_NAME = "azalea-nezu/tailscale/notebook-auth-key"


def main() -> None:
    session = boto3.Session(profile_name="Lucky9 Root", region_name="us-west-2")
    identity = session.client("sts").get_caller_identity()
    if identity["Account"] != ACCOUNT:
        raise SystemExit("Lucky9 Root does not resolve to the expected AWS account")

    key = getpass.getpass("Paste the tag:azalea-notebook auth key (hidden): ").strip()
    if not key.startswith("tskey-auth-") or any(character.isspace() for character in key):
        raise SystemExit("Expected a Tailscale auth key beginning with tskey-auth-")

    session.client("secretsmanager").put_secret_value(
        SecretId=SECRET_NAME,
        SecretString=key,
    )
    print("Tailscale auth key stored in Secrets Manager.")


if __name__ == "__main__":
    main()
