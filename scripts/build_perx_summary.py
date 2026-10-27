#!/usr/bin/env python3
"""Build a public, anonymized activity summary from a local Git archive."""

import argparse
import json
import os
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path


AUTHOR_NAME = "Maxim Tyurin"
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__"}


def repositories(root: Path):
    for directory, dirs, files in os.walk(root):
        if ".git" in dirs or ".git" in files:
            yield Path(directory)
            dirs[:] = [name for name in dirs if name not in SKIP_DIRS]
        else:
            dirs[:] = [name for name in dirs if name not in SKIP_DIRS]


def summarize(root: Path) -> dict:
    if not root.is_dir():
        raise ValueError(f"Архив не найден: {root}")

    unique: dict[str, tuple[str, bool]] = {}
    appearances = 0
    scanned = 0
    matching = 0

    for repo in repositories(root):
        result = subprocess.run(
            ["git", "-C", str(repo), "log", "--all", "--format=%H%x09%P%x09%an%x09%ad", "--date=short"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            continue
        scanned += 1
        repo_matches = 0
        for line in result.stdout.splitlines():
            fields = line.split("\t", 3)
            if len(fields) != 4 or fields[2] != AUTHOR_NAME:
                continue
            sha, parents, _author, day = fields
            if len(day) != 10 or not day[:4].isdigit():
                continue
            appearances += 1
            repo_matches += 1
            unique.setdefault(sha, (day, len(parents.split()) > 1))
        if repo_matches:
            matching += 1

    if not unique:
        raise ValueError(f"Коммиты автора {AUTHOR_NAME} не найдены в {root}")

    months = Counter(day[:7] for day, _merge in unique.values())
    days = [day for day, _merge in unique.values()]
    merges = sum(merge for _day, merge in unique.values())
    return {
        "generated_on": date.today().isoformat(),
        "period": {"from": min(days), "to": max(days)},
        "repositories_scanned": scanned,
        "repositories_with_author_commits": matching,
        "commit_appearances": appearances,
        "unique_commits": len(unique),
        "non_merge_commits": len(unique) - merges,
        "merge_commits": merges,
        "monthly_unique_commits": dict(sorted(months.items())),
        "source_note": "Агрегаты локального Git-архива; приватные репозитории и коммиты не опубликованы.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Путь к локальному архиву репозиториев")
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "data" / "perx_commit_summary.json"
    summary = summarize(args.archive.resolve())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{summary['unique_commits']} уникальных коммитов в {summary['repositories_with_author_commits']} репозиториях; {output}")


if __name__ == "__main__":
    main()
