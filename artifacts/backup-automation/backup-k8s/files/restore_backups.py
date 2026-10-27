#!/usr/bin/env python3
"""
Redacted public copy of a restore automation script.

What is preserved:
- restore flows for PostgreSQL and MariaDB
- S3 object lookup before restore
- database existence checks and conditional creation
- decrypt + gunzip + restore shell pipelines
- Slack notifications for recovery outcomes
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from pathlib import Path

import boto3
import requests
from botocore.exceptions import ClientError


YEAR = os.getenv("YEAR")
MONTH = os.getenv("MONTH")
DAY = os.getenv("DAY")
BUCKET = os.getenv("BUCKET")
DB_LIST_PATH = Path(os.getenv("DB_NAME", "/config/databases.txt"))
AWS_REGION = os.getenv("AWS_REGION")
SECRET_ID = os.getenv("SECRETMANAGER")
ENCRYPT_KEY = os.getenv("ENCRYPT_KEY")
LOKI_URL = os.getenv("LOKI")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
SLACK_CHANNEL = os.getenv("SLACK_CHANNEL")
ENVIRONMENT = os.getenv("ENVIRONMENT", "redacted-environment")
DEBUG = os.getenv("DEBUG")

LOGGER = logging.getLogger("restore")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def alert_to_slack(status: str, log_url: str, s3_url: str, code: str, db_host: str) -> None:
    if not SLACK_WEBHOOK_URL:
        return
    payload = {
        "text": ENVIRONMENT,
        "username": "Restore Automation",
        "channel": SLACK_CHANNEL,
        "attachments": [
            {
                "text": f"[{status.upper()}] restore finished\ncode: {code}\nhost: {db_host}",
                "actions": [
                    {"name": "Logs", "text": "Logs", "type": "button", "url": log_url},
                    {"name": "Bucket", "text": "Bucket", "type": "button", "url": s3_url},
                ],
            }
        ],
    }
    requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)


def get_secretmanager() -> dict:
    client = boto3.session.Session().client("secretsmanager", region_name=AWS_REGION)
    response = client.get_secret_value(SecretId=SECRET_ID)
    return json.loads(response["SecretString"])


def read_db_names() -> list[str]:
    return [line.strip() for line in DB_LIST_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]


def list_available_restore(bucket: str, prefix: str, db_name: str) -> bool:
    s3_client = boto3.client("s3")
    objects = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    keys = [item["Key"] for item in objects.get("Contents", [])]
    return any(f"{db_name}.sql.gz" in key for key in keys)


def run_shell(command: str) -> subprocess.CompletedProcess[bytes]:
    if DEBUG:
        LOGGER.info(command)
    return subprocess.run(command, capture_output=True, shell=True, executable="/bin/bash")


def command_restore_mariadb(db_host: str, db_user: str, db_pass: str, db_name: str, bucket: str, prefix: str) -> str:
    return (
        f"aws s3 cp s3://{bucket}/{prefix}{db_name}.sql.gz.aes - | "
        f"aescrypt -d -p {ENCRYPT_KEY} -o - - | gunzip -c | "
        f"mysql -h {db_host} -u {db_user} -p{db_pass} {db_name}"
    )


def command_restore_postgres(db_host: str, db_user: str, db_pass: str, db_name: str, bucket: str, prefix: str) -> str:
    return (
        f"aws s3 cp s3://{bucket}/{prefix}{db_name}.sql.gz.aes - | "
        f"aescrypt -d -p {ENCRYPT_KEY} -o - - | gunzip -c | "
        f"PGPASSWORD={db_pass} psql -h {db_host} -U {db_user} -d {db_name}"
    )


def ensure_database_exists(db_host: str, db_user: str, db_pass: str, db_name: str) -> None:
    """
    Redacted placeholder. In the original internal script:
    - MariaDB databases were checked and created when missing
    - PostgreSQL databases were checked and created from the postgres DB when missing
    """
    LOGGER.info("ensure database exists: host=%s db=%s user=%s", db_host, db_name, db_user)


def main() -> int:
    secret = get_secretmanager()
    db_host = secret["rds_host"].split(":")[0]
    db_user = secret["rds_user"]
    db_pass = secret["rds_pass"]
    bucket_prefix = f"{db_host}/{YEAR}/{MONTH}/{DAY}/"
    bucket_url = f"https://s3.console.aws.amazon.com/s3/buckets/{BUCKET}?region={AWS_REGION}&prefix={bucket_prefix}"

    errors: list[str] = []
    for db_name in read_db_names():
        if not list_available_restore(BUCKET, bucket_prefix, db_name):
            errors.append(f"{db_name}: restore object not found")
            continue

        ensure_database_exists(db_host, db_user, db_pass, db_name)

        if "mariadb" in db_host:
            command = command_restore_mariadb(db_host, db_user, db_pass, db_name, BUCKET, bucket_prefix)
        elif "postgres" in db_host:
            command = command_restore_postgres(db_host, db_user, db_pass, db_name, BUCKET, bucket_prefix)
        else:
            errors.append(f"unsupported db host type for {db_host}")
            continue

        result = run_shell(command)
        stderr = result.stderr.decode("utf-8", errors="ignore")
        if result.returncode != 0 or "error" in stderr.lower():
            errors.append(f"{db_name}: {stderr.strip()}")

    if errors:
        alert_to_slack("down", LOKI_URL or "", bucket_url, "; ".join(errors), db_host)
        for item in errors:
            LOGGER.error(item)
        return 1

    alert_to_slack("up", LOKI_URL or "", bucket_url, "0", db_host)
    LOGGER.info("restore run completed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ClientError as exc:
        LOGGER.exception("aws error: %s", exc)
        sys.exit(1)
