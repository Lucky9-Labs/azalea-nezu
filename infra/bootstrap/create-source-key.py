"""One-time narrow AWS source key for the Azalea deploy role.

AWS rejects AssumeRole calls made by an account root principal. This IAM user
has only sts:AssumeRole for the Azalea deploy role. The access key is created
outside Terraform state and written to a separate mode-0600 credentials file.
"""

import os
from pathlib import Path

import boto3

ACCOUNT = "964028866059"
USER_NAME = "azalea-nezu-deployer-source"
PROFILE = "azalea-nezu-source"
CREDENTIALS_PATH = Path.home() / ".aws" / "azalea-nezu-credentials"


def main() -> None:
    if CREDENTIALS_PATH.exists():
        raise SystemExit(f"{CREDENTIALS_PATH} already exists; refusing to create another key")
    session = boto3.Session(profile_name="Lucky9 Root", region_name="us-west-2")
    identity = session.client("sts").get_caller_identity()
    if identity["Account"] != ACCOUNT or not identity["Arn"].endswith(":root"):
        raise SystemExit("Lucky9 Root did not resolve to the expected bootstrap identity")
    iam = session.client("iam")
    iam.get_user(UserName=USER_NAME)
    CREDENTIALS_PATH.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = iam.create_access_key(UserName=USER_NAME)["AccessKey"]
    try:
        fd = os.open(CREDENTIALS_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(f"[{PROFILE}]\n")
            stream.write(f"aws_access_key_id = {key['AccessKeyId']}\n")
            stream.write(f"aws_secret_access_key = {key['SecretAccessKey']}\n")
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        iam.delete_access_key(UserName=USER_NAME, AccessKeyId=key["AccessKeyId"])
        CREDENTIALS_PATH.unlink(missing_ok=True)
        raise
    print(f"Created {PROFILE} credentials in {CREDENTIALS_PATH} (mode 0600).")


if __name__ == "__main__":
    main()
