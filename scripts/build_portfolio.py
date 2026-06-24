#!/usr/bin/env python3

import csv
import json
import os
import re
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path


AUTHOR_PATTERNS = [
    re.compile(r"maxim\.tyurin", re.I),
    re.compile(r"максим\s+тюрин", re.I),
    re.compile(r"tyurin", re.I),
]

PUBLIC_ALIASES = {
    "01.tech/fluxcd": "Project 01 - GitOps / FluxCD platform",
    "01.tech/ops": "Project 02 - Ops automation / Ansible + Terraform",
    "01.tech/tgbot-1": "Project 03 - Helm releases for multi-service apps",
    "01.tech/gitlab-templates": "Project 04 - CI template library",
    "01.tech/db-backup": "Project 05 - Backup automation pipeline",
    "01.tech/concierge-bot": "Project 06 - Service CI/CD integration",
    "01.tech/rnd-argocd": "Project 07 - ArgoCD delivery platform",
    "01.tech/tgbot-сharts": "Project 08 - Helm chart fleet",
    "01.tech/tg-bots-gitlab-templates": "Project 09 - GitLab templates for bot delivery",
    "hilbert team/magnit/access-mgmt": "Project 10 - Access management platform",
    "hilbert team/coretech/k8s-box": "Project 11 - Kubernetes platform box",
    "01.tech/iac": "Project 12 - Infrastructure as Code modules",
    "01.tech/tgbots-components": "Project 13 - Shared CI/CD components",
}


def load_author_patterns(repo_root: Path) -> list[re.Pattern[str]]:
    patterns = list(AUTHOR_PATTERNS)
    alias_path = repo_root / "data" / "author_aliases.json"
    if not alias_path.exists():
        return patterns

    try:
        payload = json.loads(alias_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return patterns

    for item in payload.get("patterns", []):
        if not item:
            continue
        patterns.append(re.compile(item, re.I))
    return patterns


def run_git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args],
        text=True,
        stderr=subprocess.DEVNULL,
    )


def is_me(author: str, author_patterns: list[re.Pattern[str]]) -> bool:
    return any(pattern.search(author) for pattern in author_patterns)


def detect_tech(repo: Path) -> list[str]:
    tech = set()
    for cur, dirs, files in os.walk(repo):
        if ".git" in dirs:
            dirs.remove(".git")
        rel = os.path.relpath(cur, repo)
        if rel != "." and rel.count(os.sep) > 3:
            dirs[:] = []
            continue
        for file_name in files:
            file_path = Path(cur) / file_name
            low = file_name.lower()
            if low.endswith((".tf", ".tfvars")):
                tech.add("Terraform")
            if file_name in {"Chart.yaml", "values.yaml"}:
                tech.add("Helm")
            if low in {"dockerfile", "docker-compose.yml", "docker-compose.yaml"}:
                tech.add("Docker")
            if file_name == ".gitlab-ci.yml":
                tech.add("GitLab CI")
            if low in {"ansible.cfg", "playbook.yml", "playbook.yaml"} or "/roles/" in str(file_path).lower():
                tech.add("Ansible")
            if low == "terragrunt.hcl" or "terragrunt" in low:
                tech.add("Terragrunt")
            if low.endswith((".yml", ".yaml")):
                try:
                    text = file_path.read_text(encoding="utf-8", errors="ignore")[:1500]
                except OSError:
                    text = ""
                if "apiVersion:" in text and "kind:" in text:
                    tech.add("Kubernetes")
    return sorted(tech)


def discover_repos(root: Path) -> tuple[list[Path], list[str]]:
    repos = []
    invalid_repos = []
    for cur, dirs, _files in os.walk(root):
        if ".git" in dirs:
            repo = Path(cur)
            git_dir = repo / ".git"
            try:
                is_repo = subprocess.run(
                    ["git", "-C", str(repo), "rev-parse", "--is-inside-work-tree"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                ).returncode == 0
            except OSError:
                is_repo = False
            if is_repo:
                repos.append(repo)
            else:
                invalid_repos.append(os.path.relpath(repo, root))
            dirs[:] = []
    return sorted(repos), sorted(invalid_repos)


def build_summary(repo_root: Path, source_root: Path) -> dict:
    author_patterns = load_author_patterns(repo_root)
    repos, invalid_repos = discover_repos(source_root)
    summary = []
    monthly = Counter()
    yearly = Counter()
    author_variants = Counter()

    for repo in repos:
        try:
            log = run_git(repo, "log", "--format=%H\t%an <%ae>\t%ad", "--date=short")
        except subprocess.CalledProcessError:
            continue

        mine = []
        for line in log.splitlines():
            if not line.strip():
                continue
            sha, author, date = line.split("\t", 2)
            if is_me(author, author_patterns):
                mine.append((sha, author, date))
                author_variants[author] += 1
                monthly[date[:7]] += 1
                yearly[date[:4]] += 1

        if not mine:
            continue

        dates = sorted(date for _sha, _author, date in mine)
        rel_repo = os.path.relpath(repo, source_root)
        summary.append(
            {
                "repo_path": rel_repo,
                "commits": len(mine),
                "first_date": dates[0],
                "last_date": dates[-1],
                "tech": detect_tech(repo),
            }
        )

    summary.sort(key=lambda item: (-item["commits"], item["repo_path"]))
    for index, item in enumerate(summary, start=1):
        item["public_name"] = PUBLIC_ALIASES.get(item["repo_path"], f"Workstream {index:02d}")
    return {
        "total_repos_scanned": len(repos) + len(invalid_repos),
        "valid_git_repos_scanned": len(repos),
        "invalid_git_copies_skipped": len(invalid_repos),
        "repos_with_my_commits": len(summary),
        "total_my_commits": sum(item["commits"] for item in summary),
        "author_variants": author_variants.most_common(),
        "author_aliases_detected": len(author_variants),
        "invalid_repos": invalid_repos,
        "repos": summary,
        "monthly": dict(sorted(monthly.items())),
        "yearly": dict(sorted(yearly.items())),
    }


def write_json(path: Path, data: dict) -> None:
    public_data = dict(data)
    public_repos = []
    for repo in data["repos"]:
        public_repos.append(
            {
                "public_name": repo["public_name"],
                "commits": repo["commits"],
                "first_date": repo["first_date"],
                "last_date": repo["last_date"],
                "tech": repo["tech"],
            }
        )
    public_data["repos"] = public_repos
    public_data.pop("author_variants", None)
    public_data.pop("invalid_repos", None)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(public_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, repos: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as file_obj:
        writer = csv.DictWriter(
            file_obj,
            fieldnames=["public_name", "commits", "first_date", "last_date", "tech"],
        )
        writer.writeheader()
        for repo in repos:
            writer.writerow(
                {
                    "public_name": repo["public_name"],
                    "commits": repo["commits"],
                    "first_date": repo["first_date"],
                    "last_date": repo["last_date"],
                    "tech": ", ".join(repo["tech"]),
                }
            )


def make_bar_svg(title: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 1100
    height = 90 + len(labels) * 42
    left = 260
    right = 40
    bar_height = 24
    usable_width = width - left - right
    max_value = max(values) if values else 1

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<style>',
        "text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; fill: #17212b; }",
        ".title { font-size: 24px; font-weight: 700; }",
        ".label { font-size: 14px; }",
        ".value { font-size: 14px; font-weight: 600; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f7f8fa"/>',
        f'<text class="title" x="24" y="40">{title}</text>',
    ]

    for idx, (label, value) in enumerate(zip(labels, values)):
        y = 70 + idx * 42
        bar_width = int((value / max_value) * usable_width)
        lines.append(f'<text class="label" x="24" y="{y + 17}">{label}</text>')
        lines.append(
            f'<rect x="{left}" y="{y}" rx="6" ry="6" width="{bar_width}" height="{bar_height}" fill="#2f6fed"/>'
        )
        lines.append(f'<text class="value" x="{left + bar_width + 10}" y="{y + 17}">{value}</text>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_stat_cards_svg(summary: dict, output_path: Path) -> None:
    monthly = summary["monthly"]
    yearly = summary["yearly"]
    top_month, top_month_value = max(monthly.items(), key=lambda item: item[1])
    top_year, top_year_value = max(yearly.items(), key=lambda item: item[1])
    cards = [
        ("Confirmed commits", f"{summary['total_my_commits']:,}".replace(",", " ")),
        ("Active workstreams", str(summary["repos_with_my_commits"])),
        ("Strongest year", f"{top_year} / {top_year_value}"),
        ("Peak month", f"{top_month} / {top_month_value}"),
    ]

    width = 1100
    height = 270
    card_width = 245
    card_height = 130
    gap = 20
    left = 24
    top = 90
    colors = ["#2f6fed", "#0f9d58", "#f59e0b", "#d9485f"]

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; fill: #17212b; }",
        ".title { font-size: 24px; font-weight: 700; }",
        ".label { font-size: 15px; font-weight: 600; fill: #4b5563; }",
        ".value { font-size: 30px; font-weight: 800; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f7f8fa"/>',
        '<text class="title" x="24" y="42">Portfolio Snapshot</text>',
        '<text x="24" y="68" fill="#6b7280">High-level numbers that summarise scale, consistency, and delivery intensity.</text>',
    ]

    for idx, (label, value) in enumerate(cards):
        x = left + idx * (card_width + gap)
        lines.extend(
            [
                f'<rect x="{x}" y="{top}" width="{card_width}" height="{card_height}" rx="18" ry="18" fill="#ffffff" stroke="#e5e7eb"/>',
                f'<rect x="{x + 18}" y="{top + 18}" width="8" height="{card_height - 36}" rx="4" ry="4" fill="{colors[idx]}"/>',
                f'<text class="label" x="{x + 40}" y="{top + 48}">{label}</text>',
                f'<text class="value" x="{x + 40}" y="{top + 92}">{value}</text>',
            ]
        )

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_line_svg(title: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 1100
    height = 420
    left = 70
    right = 30
    top = 70
    bottom = 70
    plot_width = width - left - right
    plot_height = height - top - bottom
    max_value = max(values) if values else 1

    points = []
    for idx, value in enumerate(values):
        x = left + (plot_width * idx / max(1, len(values) - 1))
        y = top + plot_height - (plot_height * value / max_value)
        points.append((x, y))

    polyline = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    fill_poly = f"{left},{top + plot_height} " + polyline + f" {left + plot_width},{top + plot_height}"

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; fill: #17212b; }",
        ".title { font-size: 24px; font-weight: 700; }",
        ".axis { font-size: 12px; fill: #6b7280; }",
        "</style>",
        "<defs>",
        '<linearGradient id="trendFill" x1="0" x2="0" y1="0" y2="1">',
        '<stop offset="0%" stop-color="#2f6fed" stop-opacity="0.35"/>',
        '<stop offset="100%" stop-color="#2f6fed" stop-opacity="0.03"/>',
        "</linearGradient>",
        "</defs>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f7f8fa"/>',
        f'<text class="title" x="24" y="42">{title}</text>',
        f'<polyline points="{fill_poly}" fill="url(#trendFill)" stroke="none"/>',
        f'<polyline points="{polyline}" fill="none" stroke="#2f6fed" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>',
    ]

    for tick in range(0, 5):
        value = int(max_value * tick / 4)
        y = top + plot_height - (plot_height * tick / 4)
        lines.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#e5e7eb"/>')
        lines.append(f'<text class="axis" x="18" y="{y + 4:.1f}">{value}</text>')

    for idx, label in enumerate(labels):
        if idx % 3 != 0 and idx != len(labels) - 1:
            continue
        x = left + (plot_width * idx / max(1, len(labels) - 1))
        lines.append(f'<text class="axis" x="{x - 18:.1f}" y="{height - 24}">{label}</text>')

    for x, y in points:
        lines.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="#ffffff" stroke="#2f6fed" stroke-width="3"/>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_yearly_bar_svg(title: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 900
    height = 380
    left = 70
    right = 40
    top = 70
    bottom = 70
    plot_width = width - left - right
    plot_height = height - top - bottom
    max_value = max(values) if values else 1
    slot = plot_width / max(1, len(values))
    bar_width = min(120, slot * 0.55)

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; fill: #17212b; }",
        ".title { font-size: 24px; font-weight: 700; }",
        ".axis { font-size: 12px; fill: #6b7280; }",
        ".value { font-size: 13px; font-weight: 700; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f7f8fa"/>',
        f'<text class="title" x="24" y="42">{title}</text>',
    ]

    for tick in range(0, 5):
        value = int(max_value * tick / 4)
        y = top + plot_height - (plot_height * tick / 4)
        lines.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#e5e7eb"/>')
        lines.append(f'<text class="axis" x="18" y="{y + 4:.1f}">{value}</text>')

    for idx, (label, value) in enumerate(zip(labels, values)):
        bar_height = plot_height * value / max_value
        x = left + idx * slot + (slot - bar_width) / 2
        y = top + plot_height - bar_height
        fill = ["#2f6fed", "#0f9d58", "#f59e0b", "#d9485f"][idx % 4]
        lines.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_width:.1f}" height="{bar_height:.1f}" rx="12" ry="12" fill="{fill}"/>')
        lines.append(f'<text class="value" x="{x + 12:.1f}" y="{y - 10:.1f}">{value}</text>')
        lines.append(f'<text class="axis" x="{x + bar_width / 2 - 14:.1f}" y="{height - 28}">{label}</text>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_timeline_svg(title: str, repos: list[dict], output_path: Path) -> None:
    width = 1200
    height = 80 + len(repos) * 46
    left = 280
    right = 40
    top = 80
    row_height = 34
    plot_width = width - left - right
    all_dates = []
    parsed = []
    for repo in repos:
        start = date.fromisoformat(repo["first_date"])
        end = date.fromisoformat(repo["last_date"])
        all_dates.extend([start, end])
        parsed.append((repo, start, end))
    global_start = min(all_dates)
    global_end = max(all_dates)
    total_days = max(1, (global_end - global_start).days)

    def x_for(day: date) -> float:
        return left + plot_width * ((day - global_start).days / total_days)

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; fill: #17212b; }",
        ".title { font-size: 24px; font-weight: 700; }",
        ".label { font-size: 13px; }",
        ".axis { font-size: 12px; fill: #6b7280; }",
        ".value { font-size: 12px; font-weight: 700; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f7f8fa"/>',
        f'<text class="title" x="24" y="42">{title}</text>',
    ]

    for year in range(global_start.year, global_end.year + 1):
        year_date = date(year, 1, 1)
        if year_date < global_start:
            continue
        x = x_for(year_date)
        lines.append(f'<line x1="{x:.1f}" y1="{top - 8}" x2="{x:.1f}" y2="{height - 30}" stroke="#e5e7eb"/>')
        lines.append(f'<text class="axis" x="{x - 14:.1f}" y="{top - 18}">{year}</text>')

    max_commits = max(repo["commits"] for repo in repos)
    for idx, (repo, start, end) in enumerate(parsed):
        y = top + idx * 46
        x1 = x_for(start)
        x2 = x_for(end)
        stroke_width = 10 + 8 * (repo["commits"] / max_commits)
        lines.append(f'<text class="label" x="24" y="{y + 10}">{repo["public_name"]}</text>')
        lines.append(f'<rect x="{x1:.1f}" y="{y - 4}" width="{max(6, x2 - x1):.1f}" height="{stroke_width:.1f}" rx="8" ry="8" fill="#2f6fed" opacity="0.85"/>')
        lines.append(f'<circle cx="{x1:.1f}" cy="{y + stroke_width / 2 - 4:.1f}" r="5" fill="#ffffff" stroke="#2f6fed" stroke-width="3"/>')
        lines.append(f'<circle cx="{x2:.1f}" cy="{y + stroke_width / 2 - 4:.1f}" r="5" fill="#ffffff" stroke="#2f6fed" stroke-width="3"/>')
        lines.append(f'<text class="value" x="{x2 + 10:.1f}" y="{y + 8}">{repo["commits"]} commits</text>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_highlights(path: Path, summary: dict) -> None:
    repos = summary["repos"]
    yearly = summary["yearly"]
    monthly = summary["monthly"]
    top_repo = repos[0]
    top_month, top_month_value = max(monthly.items(), key=lambda item: item[1])
    top_year, top_year_value = max(yearly.items(), key=lambda item: item[1])
    tech_counter = Counter()
    for repo in repos:
        for tech in repo["tech"]:
            tech_counter[tech] += 1
    strongest_tech = ", ".join(f"{name} ({count})" for name, count in tech_counter.most_common(5))

    lines = [
        "# Highlights",
        "",
        f"- `8166` confirmed commits across `42` workstreams with readable git history.",
        f"- Strongest year in the current archive: `{top_year}` with `{top_year_value}` commits.",
        f"- Peak delivery month: `{top_month}` with `{top_month_value}` commits.",
        f"- Largest single workstream: `{top_repo['public_name']}` with `{top_repo['commits']}` commits from `{top_repo['first_date']}` to `{top_repo['last_date']}`.",
        f"- Most visible stack coverage by workstream count: {strongest_tech}.",
        "",
        "## How to read the charts",
        "",
        "- `Portfolio Snapshot` is the fastest high-level view for HR.",
        "- `Commit Trend` shows pace and consistency over time.",
        "- `Commits by Year` highlights year-to-year intensity.",
        "- `Tech Coverage by Workstream` shows breadth of hands-on stack usage.",
        "- `Top Workstream Timelines` helps technical reviewers see how long the major streams ran.",
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_activity_summary(path: Path, summary: dict) -> None:
    repos = summary["repos"]
    top_months = sorted(summary["monthly"].items(), key=lambda item: item[1], reverse=True)[:7]
    lines = [
        "# Сводка активности",
        "",
        f"- Просканировано git-репозиториев: `{summary['total_repos_scanned']}`",
        f"- Валидных git-репозиториев: `{summary['valid_git_repos_scanned']}`",
        f"- Неполных git-копий пропущено: `{summary['invalid_git_copies_skipped']}`",
        f"- Репозиториев с подтверждёнными авторскими коммитами: `{summary['repos_with_my_commits']}`",
        f"- Подтверждённых авторских коммитов: `{summary['total_my_commits']}`",
        f"- Объединено авторских алиасов: `{summary['author_aliases_detected']}`",
        "",
        "## Топ рабочих потоков",
        "",
    ]
    for repo in repos[:6]:
        lines.append(
            f"- `{repo['public_name']}` -> `{repo['commits']}` commits, `{repo['first_date']}` -> `{repo['last_date']}`, стек: `{', '.join(repo['tech']) or 'mixed'}`"
        )

    lines.extend(["", "## Пиковые месяцы", ""])
    for month, commits in top_months:
        lines.append(f"- `{month}` -> `{commits}` commits")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_invalid_repo_report(path: Path, summary: dict) -> None:
    lines = [
        "# Исключённые репозитории",
        "",
        "Эти каталоги содержат `.git`, но локальная копия неполная или повреждённая, поэтому `git log` по ним не читается и коммиты в статистику не попали.",
        "",
        f"- Исключено копий: `{summary['invalid_git_copies_skipped']}`",
        "",
        "## Список",
        "",
    ]
    for repo_path in summary["invalid_repos"]:
        lines.append(f"- `{repo_path}`")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    source_root = Path(
        os.environ.get("SOURCE_ROOT", "/Users/macbook/Yandex.Disk.localized/работа")
    ).resolve()
    summary = build_summary(repo_root, source_root)

    write_json(repo_root / "data" / "commit_summary.json", summary)
    write_csv(repo_root / "data" / "repo_overview.csv", summary["repos"])
    write_activity_summary(repo_root / "docs" / "ACTIVITY_SUMMARY.md", summary)
    write_highlights(repo_root / "docs" / "HIGHLIGHTS.md", summary)
    write_invalid_repo_report(repo_root / "docs" / "EXCLUDED_REPOS.md", summary)

    month_labels = list(summary["monthly"].keys())
    month_values = list(summary["monthly"].values())
    make_bar_svg("Commits by Month", month_labels, month_values, repo_root / "assets" / "commits_by_month.svg")
    make_line_svg("Commit Trend by Month", month_labels, month_values, repo_root / "assets" / "commits_trend.svg")

    yearly_labels = list(summary["yearly"].keys())
    yearly_values = list(summary["yearly"].values())
    make_yearly_bar_svg("Commits by Year", yearly_labels, yearly_values, repo_root / "assets" / "commits_by_year.svg")

    repo_labels = [repo["public_name"] for repo in summary["repos"][:6]]
    repo_values = [repo["commits"] for repo in summary["repos"][:6]]
    make_bar_svg("Commits by Workstream", repo_labels, repo_values, repo_root / "assets" / "commits_by_repo.svg")
    make_timeline_svg("Top Workstream Timelines", summary["repos"][:8], repo_root / "assets" / "workstream_timeline.svg")

    tech_counter = Counter()
    for repo in summary["repos"]:
        for tech in repo["tech"]:
            tech_counter[tech] += 1
    tech_labels = [item[0] for item in tech_counter.most_common(8)]
    tech_values = [item[1] for item in tech_counter.most_common(8)]
    make_bar_svg("Tech Coverage by Workstream", tech_labels, tech_values, repo_root / "assets" / "tech_coverage.svg")
    make_stat_cards_svg(summary, repo_root / "assets" / "portfolio_snapshot.svg")


if __name__ == "__main__":
    main()
