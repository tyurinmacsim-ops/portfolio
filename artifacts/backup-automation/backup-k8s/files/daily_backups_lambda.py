#!/usr/bin/env python3
"""
Redacted public copy of a production-shaped backup automation script.

What is preserved:
- backup orchestration for PostgreSQL and MariaDB
- secret loading from AWS Secrets Manager
- S3 bucket checks and backup presence checks
- Slack notifications
- shell-based dump + encrypt + upload pipelines

What is removed:
- private hostnames, bucket names, secret IDs and internal labels
- customer-specific DB naming
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import boto3
import botocore
import requests
from botocore.exceptions import ClientError


TIMESTAMP = time.strftime("%Y-%m-%d-%H:%M")
YEAR = time.strftime("%Y")
MONTH = time.strftime("%m")
DAY = time.strftime("%d")

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

LOGGER = logging.getLogger("backup")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


ALERT_MAP = {
    "up": {"emoji": ":white_check_mark:", "text": "DONE", "color": "#32a852"},
    "down": {"emoji": ":fire:", "text": "ERROR", "color": "#ad1721"},
    "warn": {"emoji": ":warning:", "text": "WARNING", "color": "#ff7f49"},
}


def alert_to_slack(status: str, log_url: str, s3_url: str, code: str, db_host: str) -> None:
    if not SLACK_WEBHOOK_URL:
        return

    payload = {
        "text": ENVIRONMENT,
        "username": "Backup Automation",
        "channel": SLACK_CHANNEL,
        "attachments": [
            {
                "text": (
                    f"{ALERT_MAP[status]['emoji']} [*{ALERT_MAP[status]['text']}*] "
                    f"Backup finished\ncode: {code}\nhost: {db_host}"
                ),
                "color": ALERT_MAP[status]["color"],
                "actions": [
                    {"name": "Logs", "text": "Logs", "type": "button", "url": log_url},
                    {"name": "Bucket", "text": "Bucket", "type": "button", "url": s3_url},
                ],
            }
        ],
    }
    requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)


def get_secretmanager() -> dict:
    session = boto3.session.Session()
    client = session.client(service_name="secretsmanager", region_name=AWS_REGION)
    try:
        response = client.get_secret_value(SecretId=SECRET_ID)
    except ClientError as exc:
        alert_to_slack("down", LOKI_URL or "", "s3://redacted", str(exc), "secret-manager")
        raise
    if "SecretString" in response:
        return json.loads(response["SecretString"])
    raise RuntimeError("SecretString missing in secret response")


def read_db_names() -> list[str]:
    if not DB_LIST_PATH.exists():
        raise FileNotFoundError(f"database list not found: {DB_LIST_PATH}")
    return [line.strip() for line in DB_LIST_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]


def check_bucket(bucket: str) -> None:
    boto3.client("s3").head_bucket(Bucket=bucket)


def list_available_backup(bucket: str, prefix: str, db_name: str) -> bool:
    s3_client = boto3.client("s3")
    objects = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    keys = [item["Key"] for item in objects.get("Contents", [])]
    return any(db_name in key for key in keys)


def run_shell(command: str, db_name: str) -> subprocess.CompletedProcess[str]:
    if DEBUG:
        LOGGER.info("command for %s: %s", db_name, command)
    return subprocess.run(
        command,
        capture_output=True,
        shell=True,
        text=True,
        executable="/bin/bash",
    )


def command_backup_mariadb(db_host: str, db_user: str, db_pass: str, db_name: str, bucket: str, prefix: str) -> str:
    return (
        f"mysqldump -h {db_host} -u {db_user} -p{db_pass} {db_name} "
        f"--routines --single-transaction | gzip -9 | "
        f"aescrypt -e -p {ENCRYPT_KEY} -o - - | "
        f"aws s3 cp - s3://{bucket}/{prefix}{db_name}.sql.gz.aes"
    )


def command_backup_postgres(db_host: str, db_user: str, db_pass: str, db_name: str, bucket: str, prefix: str) -> str:
    return (
        f"PGPASSWORD={db_pass} pg_dump -Z 9 -v -h {db_host} -U {db_user} -d {db_name} | "
        f"aescrypt -e -p {ENCRYPT_KEY} -o - - | "
        f"aws s3 cp - s3://{bucket}/{prefix}{db_name}.sql.gz.aes"
    )


def main() -> int:
    secret = get_secretmanager()
    db_host = secret["rds_host"].split(":")[0]
    db_user = secret["rds_user"]
    db_pass = secret["rds_pass"]
    bucket_prefix = f"{db_host}/{YEAR}/{MONTH}/{DAY}/"
    bucket_url = f"https://s3.console.aws.amazon.com/s3/buckets/{BUCKET}?region={AWS_REGION}&prefix={bucket_prefix}"

    check_bucket(BUCKET)
    db_names = read_db_names()
    errors: list[str] = []

    for db_name in db_names:
        if "mariadb" in db_host:
            command = command_backup_mariadb(db_host, db_user, db_pass, db_name, BUCKET, bucket_prefix)
        elif "postgres" in db_host:
            command = command_backup_postgres(db_host, db_user, db_pass, db_name, BUCKET, bucket_prefix)
        else:
            errors.append(f"unsupported db host type for {db_host}")
            continue

        result = run_shell(command, db_name)
        if result.returncode != 0 or "error" in result.stderr.lower():
            errors.append(f"{db_name}: {result.stderr.strip() or result.stdout.strip()}")
            continue

        if not list_available_backup(BUCKET, bucket_prefix, db_name):
            errors.append(f"{db_name}: uploaded object not found in bucket listing")

    if errors:
        alert_to_slack("down", LOKI_URL or "", bucket_url, "; ".join(errors), db_host)
        for item in errors:
            LOGGER.error(item)
        return 1

    alert_to_slack("up", LOKI_URL or "", bucket_url, "0", db_host)
    LOGGER.info("backup run completed at %s", TIMESTAMP)
    return 0


if __name__ == "__main__":
    sys.exit(main())
