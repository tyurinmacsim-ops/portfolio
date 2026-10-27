#!/usr/bin/env python3
"""Root-owned example helper. No free-form command and no shell=True."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def status() -> dict:
    disk = shutil.disk_usage("/")
    nginx = subprocess.run(["systemctl", "is-active", "nginx"], text=True, capture_output=True).stdout.strip()
    xray = subprocess.run(["docker", "inspect", "--format", "{{.State.Status}}", "xray"], text=True, capture_output=True).stdout.strip()
    available = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:")) // 1024
    return {"load": "/".join(map(str, os.getloadavg())), "memory_available_mib": available, "disk_free_gib": round(disk.free / 2**30, 1), "nginx": nginx, "xray": xray}


if len(sys.argv) != 2 or sys.argv[1] != "status":
    print(json.dumps({"ok": False, "error": "unsupported action"}))
    raise SystemExit(2)

print(json.dumps({"ok": True, "data": status()}))
