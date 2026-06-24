#!/usr/bin/env python3
"""
Redacted public copy of a MongoDB backup automation script.

What is preserved:
- MongoDB backup orchestration with mongodump
- Secrets Manager based credential loading
- archive encryption and S3 upload
- post-backup cleanup of temporary dump folders
- Slack-based operational notifications
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
import pymongo
import requests
from botocore.exceptions import ClientError


YEAR = time.strftime("%Y")
MONTH = time.strftime("%m")
DAY = time.strftime("%d")

BUCKET = os.getenv("BUCKET")
DB_ENGINE = os.getenv("DB_ENGINE", "mongodb")
DB_LIST_PATH = Path(os.getenv("DB_LIST", "/config/databases.txt"))
AWS_REGION = os.getenv("AWS_REGION")
SECRET_ID = os.getenv("SECRETMANAGER")
ENCRYPT_KEY = os.getenv("ENCRYPT_KEY")
BUCKET_PREFIX = os.getenv("BUCKET_PREFIX")
LOKI_URL = os.getenv("LOKI")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
SLACK_CHANNEL = os.getenv("SLACK_CHANNEL")
ENVIRONMENT = os.getenv("ENVIRONMENT", "redacted-environment")
DEBUG = os.getenv("DEBUG")

LOGGER = logging.getLogger("mongo-backup")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def alert_to_slack(status: str, log_url: str, s3_url: str, code: str, db_host: str) -> None:
    if not SLACK_WEBHOOK_URL:
        return
    payload = {
        "text": ENVIRONMENT,
        "username": "Mongo Backup Automation",
        "channel": SLACK_CHANNEL,
        "attachments": [
            {
                "text": f"[{status.upper()}] mongodb backup finished\ncode: {code}\nhost: {db_host}",
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


def check_bucket(bucket: str) -> None:
    boto3.client("s3").head_bucket(Bucket=bucket)


def read_db_names() -> list[str]:
    return [line.strip() for line in DB_LIST_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]


def mongodb_info(db_host: str, db_user: str, db_pass: str, db_port: int) -> pymongo.MongoClient:
    return pymongo.MongoClient(
        host=db_host,
        username=db_user,
        password=db_pass,
        authSource="admin",
        port=db_port,
    )


def command_backup_mongodb(db_host: str, db_user: str, db_pass: str, db_name: str, bucket: str, prefix: str) -> str:
    return (
        f"mongodump --host={db_host} --port=27017 --username={db_user} --password={db_pass} "
        f"--authenticationDatabase=admin --db={db_name} --out=/script && "
        f"cd /script/{db_name} && tar -cvf - --exclude=*.tar* . | "
        f"aescrypt -e -p {ENCRYPT_KEY} -o - - > {db_name}.tar.gz.aes && "
        f"aws s3 cp *.tar* s3://{bucket}/{prefix}{db_name}.tar.gz.aes"
    )


def command_clean_archive(db_name: str) -> str:
    return f"rm -rf /script/{db_name}"


def run_shell(command: str) -> subprocess.CompletedProcess[str]:
    if DEBUG:
        LOGGER.info(command)
    return subprocess.run(
        command,
        capture_output=True,
        shell=True,
        text=True,
        executable="/bin/bash",
    )


def main() -> int:
    if DB_ENGINE != "mongodb":
        LOGGER.error("unsupported DB_ENGINE: %s", DB_ENGINE)
        return 1

    secret = get_secretmanager()
    db_host = secret["rds_host"].split(":")[0]
    db_user = secret["rds_user"]
    db_pass = secret["rds_pass"]
    db_port = int(os.getenv("DB_PORT", "27017"))

    prefix = f"{BUCKET_PREFIX + '/' if BUCKET_PREFIX else ''}{db_host}/{YEAR}/{MONTH}/{DAY}/"
    bucket_url = f"https://s3.console.aws.amazon.com/s3/buckets/{BUCKET}?region={AWS_REGION}&prefix={prefix}"

    check_bucket(BUCKET)
    client = mongodb_info(db_host, db_user, db_pass, db_port)
    LOGGER.info("connected to mongodb, visible databases: %s", client.list_database_names())
    client.close()

    errors: list[str] = []
    success: list[str] = []
    for db_name in read_db_names():
        backup_result = run_shell(command_backup_mongodb(db_host, db_user, db_pass, db_name, BUCKET, prefix))
        if backup_result.returncode != 0 or "error" in backup_result.stderr.lower():
            errors.append(f"{db_name}: {backup_result.stderr.strip()}")
            continue

        cleanup_result = run_shell(command_clean_archive(db_name))
        if cleanup_result.returncode != 0:
            errors.append(f"{db_name}: cleanup failed: {cleanup_result.stderr.strip()}")
            continue

        success.append(db_name)

    if errors:
        alert_to_slack("down", LOKI_URL or "", bucket_url, "; ".join(errors), db_host)
        LOGGER.error("backup errors: %s", errors)
        LOGGER.info("successful db list: %s", success)
        return 1

    alert_to_slack("up", LOKI_URL or "", bucket_url, f"success: {success}", db_host)
    LOGGER.info("mongodb backup run completed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ClientError as exc:
        LOGGER.exception("aws error: %s", exc)
        sys.exit(1)
