#!/usr/bin/env python3

import json
from datetime import UTC, datetime
from pathlib import Path


SOURCE_ROOT = Path("/Users/macbook/Yandex.Disk.localized/работа")


def list_child_dirs(path: Path) -> list[str]:
    if not path.exists():
        return []
    return sorted(
        child.name
        for child in path.iterdir()
        if child.is_dir() and child.name != ".git"
    )


def count_regular_files(path: Path) -> int:
    if not path.exists():
        return 0
    count = 0
    for item in path.rglob("*"):
        if ".git" in item.parts:
            continue
        if item.is_file() and item.name != ".DS_Store":
            count += 1
    return count


def build_eusy_evidence() -> dict:
    root = SOURCE_ROOT / "eusy"
    return {
        "source": "eusy",
        "path": str(root),
        "exists": root.exists(),
        "summary": (
            "The snapshot preserves strong repository topology for Ansible, Terraform, FluxCD, "
            "Terragrunt, Helm, and Kafka topic management, but the working trees are mostly empty "
            "and the local .git copies are incomplete."
        ),
        "regular_file_count_excluding_git": count_regular_files(root),
        "evidence_points": [
            {
                "label": "Ansible role topology",
                "path": "ansible/roles",
                "items": list_child_dirs(root / "ansible" / "roles"),
            },
            {
                "label": "Terraform scope layout",
                "path": "infra/terraform",
                "items": list_child_dirs(root / "infra" / "terraform"),
            },
            {
                "label": "Shared module layout",
                "path": "modules",
                "items": list_child_dirs(root / "modules"),
            },
            {
                "label": "FluxCD repository layout",
                "path": "fluxcd",
                "items": [
                    "apps/base",
                    "apps/dev-k8s",
                    "clusters/dev-k8s",
                    "clusters/prod-k8s",
                    "infrastructure/base",
                    "infrastructure/dev-k8s",
                    "infrastructure/monitoring",
                    "infrastructure/prod-k8s",
                ],
            },
            {
                "label": "Terragrunt live layout",
                "path": "terragrunt-live",
                "items": [
                    "_global/environments",
                    "_global/hub",
                    "_global/infra",
                    "_global/logger",
                    "_global/opensearch",
                    "_global/postgresql",
                    "_global/redis",
                    "_global/vault",
                    "eusy_prod/westeurope",
                ],
            },
            {
                "label": "Helm chart layout",
                "path": "charts",
                "items": [
                    "kafka-topics/templates",
                    "web/templates",
                ],
            },
            {
                "label": "Kafka topic repository layout",
                "path": "kafka-topics",
                "items": [
                    "migrations/topics",
                    "test/examples",
                ],
            },
            {
                "label": "Terragrunt modules",
                "path": "terragrunt-modules",
                "items": list_child_dirs(root / "terragrunt-modules"),
            },
        ],
        "caveats": [
            "This is topology-based evidence, not commit-based evidence.",
            "Directory modification timestamps mostly reflect copy or import time, not original authoring time.",
            "The local .git copies under eusy are incomplete, so git history could not be read reliably.",
        ],
    }


def build_payload() -> dict:
    return {
        "generated_at_utc": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": [
            build_eusy_evidence(),
        ],
    }


def write_json(repo_root: Path, payload: dict) -> None:
    path = repo_root / "data" / "additional_non_git_evidence.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_markdown(repo_root: Path, payload: dict) -> None:
    source = payload["sources"][0]
    lines = [
        "# Additional Non-Git Evidence",
        "",
        "This section exists for cases where a working archive still preserves strong technical topology, but does not preserve a readable git history.",
        "",
        "## eusy snapshot",
        "",
        f"- Source exists: `{source['exists']}`",
        f"- Regular files outside `.git`: `{source['regular_file_count_excluding_git']}`",
        f"- Assessment: {source['summary']}",
        "",
        "## Observed topology",
        "",
    ]

    for point in source["evidence_points"]:
        lines.append(f"- `{point['path']}` -> {', '.join(point['items'])}")

    lines.extend([
        "",
        "## How to interpret this",
        "",
        "- This does not prove authorship at commit level.",
        "- It does support the claim of hands-on exposure to the relevant toolchain and repository structure.",
        "- In practice, this is useful as secondary evidence next to the main commit-based portfolio.",
        "",
        "## Caveats",
        "",
    ])

    for caveat in source["caveats"]:
        lines.append(f"- {caveat}")

    path = repo_root / "docs" / "ADDITIONAL_NON_GIT_EVIDENCE.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    payload = build_payload()
    write_json(repo_root, payload)
    write_markdown(repo_root, payload)


if __name__ == "__main__":
    main()
