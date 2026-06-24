#!/usr/bin/env python3

import csv
import html
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
    re.compile(r"sir[i]?zak", re.I),
    re.compile(r"stf_tyurin_ma", re.I),
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

BACKUP_ARTIFACT_ROOT = Path(
    os.environ.get(
        "BACKUP_ARTIFACT_ROOT",
        "/Users/macbook/Yandex.Disk.localized/работа/01.tech/sckript-program/db-backup",
    )
).resolve()

SVG_TEXT_STYLE = (
    "text { font-family: 'Manrope', 'Segoe UI', sans-serif; fill: #112033; }"
    ".title { font-size: 26px; font-weight: 800; }"
    ".subtitle { font-size: 13px; fill: #627084; }"
    ".label { font-size: 14px; }"
    ".axis { font-size: 12px; fill: #6d7a8d; }"
    ".value { font-size: 14px; font-weight: 700; }"
)


def format_int(value: int) -> str:
    return f"{value:,}".replace(",", " ")


def escape(value: str) -> str:
    return html.escape(value, quote=True)


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


def build_summary(source_root: Path) -> dict:
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
            sha, author, commit_date = line.split("\t", 2)
            if is_me(author, AUTHOR_PATTERNS):
                mine.append((sha, author, commit_date))
                author_variants[author] += 1
                monthly[commit_date[:7]] += 1
                yearly[commit_date[:4]] += 1

        if not mine:
            continue

        dates = sorted(commit_date for _sha, _author, commit_date in mine)
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


def build_tech_counter(summary: dict) -> Counter:
    tech_counter = Counter()
    for repo in summary["repos"]:
        for tech in repo["tech"]:
            tech_counter[tech] += 1
    return tech_counter


def analyze_backup_artifact(root: Path) -> dict | None:
    if not root.exists():
        return None

    counts = {
        "Python": 0,
        "Shell": 0,
        "YAML": 0,
        "Dockerfile": 0,
        "Env files": 0,
        "Kustomize": 0,
    }
    python_files = []
    shell_files = []
    yaml_files = []

    for file_path in root.rglob("*"):
        if not file_path.is_file():
            continue
        low = file_path.name.lower()
        rel = str(file_path.relative_to(root))
        if file_path.suffix == ".py":
            counts["Python"] += 1
            python_files.append(rel)
        if file_path.suffix == ".sh":
            counts["Shell"] += 1
            shell_files.append(rel)
        if file_path.suffix in {".yml", ".yaml"}:
            counts["YAML"] += 1
            yaml_files.append(rel)
        if low == "dockerfile":
            counts["Dockerfile"] += 1
        if low == ".env":
            counts["Env files"] += 1
        if low == "kustomization.yaml":
            counts["Kustomize"] += 1

    return {
        "root": str(root),
        "counts": counts,
        "python_files": python_files,
        "shell_files": shell_files,
        "yaml_files": yaml_files,
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


def make_bar_svg(title: str, subtitle: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 1100
    height = 110 + len(labels) * 44
    left = 300
    right = 46
    bar_height = 24
    usable_width = width - left - right
    max_value = max(values) if values else 1

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        SVG_TEXT_STYLE,
        "</style>",
        "<defs>",
        '<linearGradient id="barFill" x1="0" x2="1" y1="0" y2="0">',
        '<stop offset="0%" stop-color="#0f766e"/>',
        '<stop offset="100%" stop-color="#d97706"/>',
        "</linearGradient>",
        "</defs>",
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="28" ry="28" fill="#fffaf4"/>',
        f'<text class="title" x="30" y="44">{escape(title)}</text>',
        f'<text class="subtitle" x="30" y="68">{escape(subtitle)}</text>',
    ]

    for idx, (label, value) in enumerate(zip(labels, values)):
        y = 86 + idx * 44
        bar_width = int((value / max_value) * usable_width)
        lines.append(f'<text class="label" x="30" y="{y + 17}">{escape(label)}</text>')
        lines.append(
            f'<rect x="{left}" y="{y}" rx="8" ry="8" width="{usable_width}" height="{bar_height}" fill="#efe5d9"/>'
        )
        lines.append(
            f'<rect x="{left}" y="{y}" rx="8" ry="8" width="{bar_width}" height="{bar_height}" fill="url(#barFill)"/>'
        )
        lines.append(f'<text class="value" x="{left + bar_width + 12}" y="{y + 17}">{value}</text>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_stat_cards_svg(summary: dict, output_path: Path) -> None:
    monthly = summary["monthly"]
    yearly = summary["yearly"]
    top_month, top_month_value = max(monthly.items(), key=lambda item: item[1])
    top_year, top_year_value = max(yearly.items(), key=lambda item: item[1])
    cards = [
        ("Подтверждённые коммиты", format_int(summary["total_my_commits"])),
        ("Активные потоки", str(summary["repos_with_my_commits"])),
        ("Сильнейший год", f"{top_year} / {format_int(top_year_value)}"),
        ("Пиковый месяц", f"{top_month} / {format_int(top_month_value)}"),
    ]

    width = 1100
    height = 280
    card_width = 245
    card_height = 136
    gap = 18
    left = 30
    top = 96
    colors = ["#0f766e", "#d97706", "#b45309", "#c2410c"]

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        SVG_TEXT_STYLE,
        ".big { font-size: 31px; font-weight: 800; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="30" ry="30" fill="#fffaf4"/>',
        '<text class="title" x="30" y="46">Снимок портфолио</text>',
        '<text class="subtitle" x="30" y="70">Ключевые числа по масштабу, стабильности и интенсивности поставки изменений.</text>',
    ]

    for idx, (label, value) in enumerate(cards):
        x = left + idx * (card_width + gap)
        lines.extend(
            [
                f'<rect x="{x}" y="{top}" width="{card_width}" height="{card_height}" rx="24" ry="24" fill="#fff" stroke="#eadfce"/>',
                f'<rect x="{x + 18}" y="{top + 18}" width="10" height="{card_height - 36}" rx="5" ry="5" fill="{colors[idx]}"/>',
                f'<text class="label" x="{x + 44}" y="{top + 50}">{escape(label)}</text>',
                f'<text class="big" x="{x + 44}" y="{top + 96}">{escape(value)}</text>',
            ]
        )

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_line_svg(title: str, subtitle: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 1100
    height = 420
    left = 76
    right = 36
    top = 84
    bottom = 76
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
        SVG_TEXT_STYLE,
        "</style>",
        "<defs>",
        '<linearGradient id="trendFill" x1="0" x2="0" y1="0" y2="1">',
        '<stop offset="0%" stop-color="#0f766e" stop-opacity="0.30"/>',
        '<stop offset="100%" stop-color="#0f766e" stop-opacity="0.02"/>',
        "</linearGradient>",
        "</defs>",
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="28" ry="28" fill="#fffaf4"/>',
        f'<text class="title" x="30" y="46">{escape(title)}</text>',
        f'<text class="subtitle" x="30" y="70">{escape(subtitle)}</text>',
        f'<polyline points="{fill_poly}" fill="url(#trendFill)" stroke="none"/>',
        f'<polyline points="{polyline}" fill="none" stroke="#0f766e" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>',
    ]

    for tick in range(0, 5):
        value = int(max_value * tick / 4)
        y = top + plot_height - (plot_height * tick / 4)
        lines.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#eadfce"/>')
        lines.append(f'<text class="axis" x="22" y="{y + 4:.1f}">{value}</text>')

    for idx, label in enumerate(labels):
        if idx % 3 != 0 and idx != len(labels) - 1:
            continue
        x = left + (plot_width * idx / max(1, len(labels) - 1))
        lines.append(f'<text class="axis" x="{x - 18:.1f}" y="{height - 28}">{escape(label)}</text>')

    for x, y in points:
        lines.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="#fffaf4" stroke="#0f766e" stroke-width="3"/>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_yearly_bar_svg(title: str, subtitle: str, labels: list[str], values: list[int], output_path: Path) -> None:
    width = 900
    height = 390
    left = 76
    right = 38
    top = 84
    bottom = 76
    plot_width = width - left - right
    plot_height = height - top - bottom
    max_value = max(values) if values else 1
    slot = plot_width / max(1, len(values))
    bar_width = min(126, slot * 0.58)
    colors = ["#0f766e", "#d97706", "#0f766e", "#c2410c"]

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        SVG_TEXT_STYLE,
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="28" ry="28" fill="#fffaf4"/>',
        f'<text class="title" x="30" y="46">{escape(title)}</text>',
        f'<text class="subtitle" x="30" y="70">{escape(subtitle)}</text>',
    ]

    for tick in range(0, 5):
        value = int(max_value * tick / 4)
        y = top + plot_height - (plot_height * tick / 4)
        lines.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_width}" y2="{y:.1f}" stroke="#eadfce"/>')
        lines.append(f'<text class="axis" x="20" y="{y + 4:.1f}">{value}</text>')

    for idx, (label, value) in enumerate(zip(labels, values)):
        bar_height = plot_height * value / max_value
        x = left + idx * slot + (slot - bar_width) / 2
        y = top + plot_height - bar_height
        lines.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_width:.1f}" height="{bar_height:.1f}" rx="16" ry="16" fill="{colors[idx % len(colors)]}"/>'
        )
        lines.append(f'<text class="value" x="{x + 12:.1f}" y="{y - 10:.1f}">{value}</text>')
        lines.append(f'<text class="axis" x="{x + bar_width / 2 - 14:.1f}" y="{height - 30}">{escape(label)}</text>')

    lines.append("</svg>")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_timeline_svg(title: str, subtitle: str, repos: list[dict], output_path: Path) -> None:
    width = 1200
    height = 96 + len(repos) * 48
    left = 300
    right = 42
    top = 96
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
        SVG_TEXT_STYLE,
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="28" ry="28" fill="#fffaf4"/>',
        f'<text class="title" x="30" y="46">{escape(title)}</text>',
        f'<text class="subtitle" x="30" y="70">{escape(subtitle)}</text>',
    ]

    for year in range(global_start.year, global_end.year + 1):
        year_date = date(year, 1, 1)
        if year_date < global_start:
            continue
        x = x_for(year_date)
        lines.append(f'<line x1="{x:.1f}" y1="{top - 8}" x2="{x:.1f}" y2="{height - 34}" stroke="#eadfce"/>')
        lines.append(f'<text class="axis" x="{x - 14:.1f}" y="{top - 18}">{year}</text>')

    max_commits = max(repo["commits"] for repo in repos)
    for idx, (repo, start, end) in enumerate(parsed):
        y = top + idx * 48
        x1 = x_for(start)
        x2 = x_for(end)
        stroke_width = 10 + 8 * (repo["commits"] / max_commits)
        lines.append(f'<text class="label" x="30" y="{y + 10}">{escape(repo["public_name"])}</text>')
        lines.append(
            f'<rect x="{x1:.1f}" y="{y - 4}" width="{max(8, x2 - x1):.1f}" height="{stroke_width:.1f}" rx="10" ry="10" fill="#0f766e" opacity="0.88"/>'
        )
        lines.append(
            f'<circle cx="{x1:.1f}" cy="{y + stroke_width / 2 - 4:.1f}" r="5" fill="#fffaf4" stroke="#0f766e" stroke-width="3"/>'
        )
        lines.append(
            f'<circle cx="{x2:.1f}" cy="{y + stroke_width / 2 - 4:.1f}" r="5" fill="#fffaf4" stroke="#0f766e" stroke-width="3"/>'
        )
        lines.append(f'<text class="value" x="{x2 + 10:.1f}" y="{y + 8}">{repo["commits"]} коммитов</text>')

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
    tech_counter = build_tech_counter(summary)
    strongest_tech = ", ".join(f"{name} ({count})" for name, count in tech_counter.most_common(5))

    lines = [
        "# Ключевые выводы",
        "",
        f"- Подтверждено `{format_int(summary['total_my_commits'])}` коммитов в `{summary['repos_with_my_commits']}` рабочих потоках с читаемой git-историей.",
        f"- Самый сильный год в текущем архиве: `{top_year}` с `{format_int(top_year_value)}` коммитами.",
        f"- Пиковый месяц по интенсивности: `{top_month}` с `{format_int(top_month_value)}` коммитами.",
        f"- Крупнейший подтверждённый поток: `{top_repo['public_name']}` с `{format_int(top_repo['commits'])}` коммитами за период `{top_repo['first_date']}` -> `{top_repo['last_date']}`.",
        f"- Наиболее часто подтверждаемый стек по числу потоков: {strongest_tech}.",
        "",
        "## Как читать графики",
        "",
        "- `Снимок портфолио` даёт самый быстрый обзор для HR.",
        "- `Тренд активности по месяцам` показывает темп и стабильность работы.",
        "- `Коммиты по годам` подсвечивают интенсивность по периодам.",
        "- `Покрытие стека по потокам` показывает ширину практического опыта.",
        "- `Ключевые рабочие потоки во времени` помогают техспециалисту быстро понять длительность основных направлений.",
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
        "",
        "## Крупнейшие рабочие потоки",
        "",
    ]
    for repo in repos[:6]:
        tech = ", ".join(repo["tech"]) or "mixed"
        lines.append(
            f"- `{repo['public_name']}` -> `{repo['commits']}` коммитов, `{repo['first_date']}` -> `{repo['last_date']}`, стек: `{tech}`"
        )

    lines.extend(["", "## Пиковые месяцы", ""])
    for month, commits in top_months:
        lines.append(f"- `{month}` -> `{commits}` коммитов")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


CONTENT_PAGE_MAP = {
    "docs/HIGHLIGHTS.md": "pages/highlights.html",
    "docs/ACTIVITY_SUMMARY.md": "pages/activity-summary.html",
    "docs/CASE_STUDIES.md": "pages/case-studies.html",
    "docs/PUBLIC_PROJECTS.md": "pages/public-projects.html",
    "docs/APPLICATION_BLURB.md": "pages/application-blurb.html",
    "docs/ARTIFACT_EVIDENCE.md": "pages/artifact-evidence.html",
    "projects/platform-engineering-demo/README.md": "pages/platform-engineering-demo.html",
}


def inline_markdown(text: str, href_resolver=None) -> str:
    text = escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", text)

    def replace_link(match: re.Match[str]) -> str:
        label = match.group(1)
        target = match.group(2)
        href = href_resolver(target) if href_resolver else CONTENT_PAGE_MAP.get(target, target)
        return f'<a href="{escape(href)}">{escape(label)}</a>'

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", replace_link, text)
    return text


def markdown_to_html(markdown_text: str, href_resolver=None) -> str:
    lines = markdown_text.splitlines()
    parts: list[str] = []
    in_list = False
    in_code = False
    code_lines: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            parts.append(f"<p>{inline_markdown(' '.join(paragraph), href_resolver=href_resolver)}</p>")
            paragraph = []

    def flush_list() -> None:
        nonlocal in_list
        if in_list:
            parts.append("</ul>")
            in_list = False

    for raw_line in lines:
        line = raw_line.rstrip("\n")
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_paragraph()
            flush_list()
            if in_code:
                code_html = escape("\n".join(code_lines))
                parts.append(f"<pre><code>{code_html}</code></pre>")
                code_lines = []
                in_code = False
            else:
                in_code = True
            continue

        if in_code:
            code_lines.append(line)
            continue

        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        if stripped.startswith("# "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h1>{inline_markdown(stripped[2:], href_resolver=href_resolver)}</h1>")
            continue

        if stripped.startswith("## "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h2>{inline_markdown(stripped[3:], href_resolver=href_resolver)}</h2>")
            continue

        if stripped.startswith("### "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h3>{inline_markdown(stripped[4:], href_resolver=href_resolver)}</h3>")
            continue

        if stripped.startswith("- "):
            flush_paragraph()
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append(f"<li>{inline_markdown(stripped[2:], href_resolver=href_resolver)}</li>")
            continue

        numbered = re.match(r"^\d+\.\s+(.*)$", stripped)
        if numbered:
            flush_paragraph()
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append(f"<li>{inline_markdown(numbered.group(1), href_resolver=href_resolver)}</li>")
            continue

        paragraph.append(stripped)

    flush_paragraph()
    flush_list()
    if in_code:
        code_html = escape("\n".join(code_lines))
        parts.append(f"<pre><code>{code_html}</code></pre>")

    return "\n".join(parts)


def write_content_page(path: Path, title: str, subtitle: str, body_html: str) -> None:
    page_html = f"""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{escape(title)} • Портфолио</title>
  <meta name="description" content="{escape(subtitle)}">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="../assets/site.css">
</head>
<body>
  <div class="bg-orb bg-orb-a"></div>
  <div class="bg-orb bg-orb-b"></div>
  <main class="content-shell">
    <section class="content-panel">
      <nav class="content-nav">
        <a class="brand" href="../index.html">Назад к портфолио</a>
      </nav>
      <header class="content-head">
        <p class="eyebrow">Материал</p>
        <h1>{escape(title)}</h1>
        <p class="content-lead">{escape(subtitle)}</p>
      </header>
      <article class="prose">
        {body_html}
      </article>
    </section>
  </main>
</body>
</html>
"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(page_html, encoding="utf-8")


def write_content_pages(repo_root: Path) -> None:
    page_titles = {
        "docs/HIGHLIGHTS.md": ("Ключевые выводы", "Краткая выжимка по подтверждённой активности и стеку."),
        "docs/ACTIVITY_SUMMARY.md": ("Сводка активности", "Числа, периоды и крупнейшие рабочие потоки."),
        "docs/CASE_STUDIES.md": ("Кейсы и результаты", "Типовые задачи и результаты, которые уже подтверждаются архивом."),
        "docs/PUBLIC_PROJECTS.md": ("Публичные демо-проекты", "Отдельные воспроизводимые артефакты для техпроверки."),
        "docs/APPLICATION_BLURB.md": ("Краткое описание", "Короткая версия описания портфолио для отклика."),
        "docs/ARTIFACT_EVIDENCE.md": ("Дополнительные артефакты", "Подтверждения по рабочим материалам без читаемой git-истории."),
        "projects/platform-engineering-demo/README.md": (
            "Демо-стенд platform engineering",
            "Воспроизводимый Terraform + Kubernetes + observability стенд.",
        ),
    }

    for source, target in CONTENT_PAGE_MAP.items():
        source_path = repo_root / source
        if not source_path.exists():
            continue
        target_path = repo_root / target

        def resolve_href(link_target: str) -> str:
            normalized = os.path.normpath(os.path.join(os.path.dirname(source), link_target)).replace("\\", "/")
            mapped = CONTENT_PAGE_MAP.get(normalized) or CONTENT_PAGE_MAP.get(link_target)
            if mapped:
                return os.path.relpath(repo_root / mapped, target_path.parent)
            return link_target

        body_html = markdown_to_html(source_path.read_text(encoding="utf-8"), href_resolver=resolve_href)
        title, subtitle = page_titles[source]
        write_content_page(target_path, title, subtitle, body_html)


def write_artifact_evidence(path: Path, artifact: dict | None) -> None:
    lines = [
        "# Дополнительные артефакты без git-истории",
        "",
        "Этот раздел не смешивается с commit-графиками. Здесь вынесены рабочие материалы, у которых в локальном архиве нет читаемой `.git`-истории, но сама структура артефактов подтверждает тип задач и стек.",
        "",
    ]

    if not artifact:
        lines.append("- Каталог с дополнительными артефактами не найден в текущем окружении сборки.")
    else:
        counts = artifact["counts"]
        lines.extend(
            [
                "## Backup / Restore Automation Toolkit",
                "",
                f"- Источник: `{artifact['root']}`",
                "- Тип подтверждения: non-git evidence по рабочему каталогу.",
                "- Что подтверждает: практическую работу с backup/restore automation, Kubernetes CronJob, Dockerized utilities, S3/AWS, Secrets Manager, Slack alerting, PostgreSQL, MariaDB и MongoDB.",
                "",
                "## Состав артефакта",
                "",
                f"- Python-скрипты: `{counts['Python']}`",
                f"- Shell-скрипты: `{counts['Shell']}`",
                f"- YAML manifests: `{counts['YAML']}`",
                f"- Dockerfiles: `{counts['Dockerfile']}`",
                f"- Env files: `{counts['Env files']}`",
                f"- Kustomize overlays: `{counts['Kustomize']}`",
                "",
                "## Что видно по содержимому",
                "",
                "- Python-скрипты реализуют backup и restore сценарии с логированием, Slack-оповещением и работой через AWS Secrets Manager / S3.",
                "- В каталоге есть Kubernetes-манифесты для cron-based backup/restore джобов.",
                "- Есть отдельные shell-сценарии для миграций и ручного экспорта баз.",
                "- Это хороший артефакт не про «настроил кластер», а про эксплуатацию данных, резервное копирование и recovery-процессы.",
                "",
                "## Ключевые файлы",
                "",
            ]
        )
        for item in artifact["python_files"]:
            lines.append(f"- `{item}`")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_landing_page(path: Path, summary: dict) -> None:
    repos = summary["repos"]
    monthly = summary["monthly"]
    yearly = summary["yearly"]
    tech_counter = build_tech_counter(summary)
    top_month, top_month_value = max(monthly.items(), key=lambda item: item[1])
    top_year, top_year_value = max(yearly.items(), key=lambda item: item[1])
    strongest_stack = [name for name, _count in tech_counter.most_common(6)]
    first_period = min(monthly)
    last_period = max(monthly)

    stat_cards = [
        ("Подтверждённые коммиты", format_int(summary["total_my_commits"])),
        ("Подтверждённые потоки", str(summary["repos_with_my_commits"])),
        ("Период активности", f"{first_period} -> {last_period}"),
        ("Сильнейший год", f"{top_year} / {format_int(top_year_value)}"),
    ]

    route_cards = [
        (
            "Для HR",
            "Быстро видно, что опыт подтверждается не только резюме, но и цифровым следом: коммиты, инфраструктурные артефакты, кейсы и воспроизводимый демо-стенд.",
        ),
        (
            "Для техлида",
            "Можно быстро пройти путь от верхнеуровневой сводки к конкретным направлениям: Kubernetes, Terraform, GitOps, CI/CD, observability и platform engineering.",
        ),
        (
            "Для собеседования",
            "Портфолио помогает обсуждать не абстрактные навыки, а конкретные потоки, периоды активности, стек и типы задач.",
        ),
    ]

    case_cards = [
        (
            "Production GitOps / Kubernetes",
            "Контур с 100+ сервисами, GitOps-процессы, Helm, GitLab CI/CD, мониторинг и эксплуатационные изменения в production.",
        ),
        (
            "Azure / AKS / PCI DSS readiness",
            "Terraform, Terragrunt, AKS, private ingress, Key Vault, сетевые политики и инфраструктурная подготовка к аудиту.",
        ),
        (
            "Yandex Cloud / аналитическая платформа",
            "Kubernetes, Airflow, Trino, JupyterHub, Vault, External Secrets, registry и observability для data-направления.",
        ),
        (
            "Backup / Restore Automation",
            "Отдельный рабочий toolkit без git-истории: Python backup/restore скрипты, Kubernetes CronJob, Docker utility-образы, S3/AWS, Slack alerting, PostgreSQL, MariaDB и MongoDB.",
        ),
    ]

    quick_links = [
        ("Ключевые выводы", "pages/highlights.html"),
        ("Сводка активности", "pages/activity-summary.html"),
        ("Кейсы", "pages/case-studies.html"),
        ("Публичные демо-проекты", "pages/public-projects.html"),
        ("Дополнительные артефакты", "pages/artifact-evidence.html"),
        ("Краткое описание", "pages/application-blurb.html"),
        ("JSON со статистикой", "data/commit_summary.json"),
    ]

    stat_cards_html = "\n".join(
        f'<article class="stat-card"><span class="stat-label">{escape(label)}</span><strong>{escape(value)}</strong></article>'
        for label, value in stat_cards
    )
    route_cards_html = "\n".join(
        f'<article class="route-card"><h3>{escape(title)}</h3><p>{escape(text)}</p></article>'
        for title, text in route_cards
    )
    case_cards_html = "\n".join(
        f'<article class="case-card"><h3>{escape(title)}</h3><p>{escape(text)}</p></article>'
        for title, text in case_cards
    )
    workstream_rows = "\n".join(
        (
            "<tr>"
            f"<td>{escape(repo['public_name'])}</td>"
            f"<td>{repo['commits']}</td>"
            f"<td>{escape(repo['first_date'])}</td>"
            f"<td>{escape(repo['last_date'])}</td>"
            f"<td>{escape(', '.join(repo['tech']) or 'mixed')}</td>"
            "</tr>"
        )
        for repo in repos[:8]
    )
    stack_badges = "\n".join(f'<li>{escape(name)}</li>' for name in strongest_stack)
    quick_links_html = "\n".join(
        f'<li><a href="{escape(href)}">{escape(label)}</a></li>' for label, href in quick_links
    )

    html_text = f"""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Максим Тюрин • Портфолио DevOps / Platform Engineer</title>
  <meta name="description" content="Портфолио DevOps / Platform Engineer с подтверждаемыми артефактами: git-статистика, кейсы, графики, демо-проект.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="assets/site.css">
</head>
<body>
  <div class="bg-orb bg-orb-a"></div>
  <div class="bg-orb bg-orb-b"></div>
  <header class="hero" id="top">
    <nav class="topbar">
      <a class="brand" href="#top">Максим Тюрин</a>
      <div class="topbar-links">
        <a href="#overview">Обзор</a>
        <a href="#charts">Графики</a>
        <a href="#cases">Кейсы</a>
        <a href="#demo">Стенд</a>
      </div>
    </nav>
    <div class="hero-grid">
      <div class="hero-copy">
        <p class="eyebrow">DevOps / Platform Engineer</p>
        <h1>Портфолио с проверяемыми артефактами, а не только со словами в резюме</h1>
        <p class="hero-lead">Собрано на основе локального архива рабочих каталогов и публичного демо-стенда. Показывает подтверждённую активность по Kubernetes, Terraform, GitOps, CI/CD и observability.</p>
        <div class="hero-actions">
          <a class="btn btn-primary" href="#overview">Маршрут для HR</a>
          <a class="btn btn-secondary" href="#tech">Маршрут для техспеца</a>
        </div>
        <ul class="hero-points">
          <li>Подтверждённый период активности: {escape(first_period)} -> {escape(last_period)}</li>
          <li>Пиковый месяц: {escape(top_month)} / {format_int(top_month_value)} коммитов</li>
          <li>Ключевой стек: {escape(", ".join(strongest_stack))}</li>
        </ul>
      </div>
      <aside class="hero-panel">
        <span class="panel-kicker">Быстрый срез</span>
        <h2>Что уже видно из данных</h2>
        <div class="stats-grid">
          {stat_cards_html}
        </div>
      </aside>
    </div>
  </header>

  <main class="page">
    <section class="panel" id="overview">
      <div class="section-head">
        <p class="eyebrow">Обзор</p>
        <h2>Зачем это смотреть HR и техспециалисту</h2>
      </div>
      <div class="route-grid">
        {route_cards_html}
      </div>
      <div class="note-box">
        <strong>Важно.</strong> В графиках показаны только те репозитории, где локально сохранилась читаемая git-история. Ранние копии части рабочих каталогов, включая некоторые архивы 2021–2022 годов, местами сохранились неполно и поэтому недопредставлены в статистике.
      </div>
    </section>

    <section class="panel" id="charts">
      <div class="section-head">
        <p class="eyebrow">Графики</p>
        <h2>Картина активности и распределения по стеку</h2>
      </div>
      <div class="chart-grid">
        <figure class="chart-card chart-card-wide">
          <img src="assets/portfolio_snapshot.svg" alt="Снимок портфолио">
        </figure>
        <figure class="chart-card chart-card-wide">
          <img src="assets/commits_trend.svg" alt="Тренд активности по месяцам">
        </figure>
        <figure class="chart-card">
          <img src="assets/commits_by_year.svg" alt="Коммиты по годам">
        </figure>
        <figure class="chart-card">
          <img src="assets/tech_coverage.svg" alt="Покрытие стека по потокам">
        </figure>
        <figure class="chart-card">
          <img src="assets/backup_artifact_map.svg" alt="Состав backup automation toolkit">
        </figure>
        <figure class="chart-card chart-card-wide">
          <img src="assets/commits_by_repo.svg" alt="Коммиты по ключевым потокам">
        </figure>
        <figure class="chart-card chart-card-wide">
          <img src="assets/workstream_timeline.svg" alt="Ключевые рабочие потоки во времени">
        </figure>
      </div>
    </section>

    <section class="panel" id="tech">
      <div class="section-head">
        <p class="eyebrow">Техсрез</p>
        <h2>Крупнейшие подтверждённые потоки</h2>
      </div>
      <div class="stack-strip">
        <span>Чаще всего в потоке встречаются:</span>
        <ul>
          {stack_badges}
        </ul>
      </div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Поток</th>
              <th>Коммиты</th>
              <th>Старт</th>
              <th>Финиш</th>
              <th>Стек</th>
            </tr>
          </thead>
          <tbody>
            {workstream_rows}
          </tbody>
        </table>
      </div>
    </section>

    <section class="panel" id="cases">
      <div class="section-head">
        <p class="eyebrow">Кейсы</p>
        <h2>Какие типы задач этот архив уже подтверждает</h2>
      </div>
      <div class="case-grid">
        {case_cards_html}
      </div>
    </section>

    <section class="panel" id="demo">
      <div class="section-head">
        <p class="eyebrow">Стенд</p>
        <h2>Публичный воспроизводимый стенд</h2>
      </div>
      <div class="demo-card">
        <div>
          <h3>platform-engineering-demo</h3>
          <p>Отдельный демо-проект внутри портфолио: <code>Terraform + Kubernetes + GitHub Actions + Prometheus/Grafana/Loki</code>. Локально прогнан end-to-end через <code>kind</code>, deployment и smoke-test.</p>
        </div>
        <a class="btn btn-primary" href="pages/platform-engineering-demo.html">Открыть описание демо-проекта</a>
      </div>
    </section>

    <section class="panel panel-links">
      <div class="section-head">
        <p class="eyebrow">Материалы</p>
        <h2>Быстрые ссылки</h2>
      </div>
      <ul class="links-list">
        {quick_links_html}
      </ul>
    </section>
  </main>
</body>
</html>
"""

    path.write_text(html_text, encoding="utf-8")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    source_root = Path(os.environ.get("SOURCE_ROOT", "/Users/macbook/Yandex.Disk.localized/работа")).resolve()
    summary = build_summary(source_root)
    backup_artifact = analyze_backup_artifact(BACKUP_ARTIFACT_ROOT)

    write_json(repo_root / "data" / "commit_summary.json", summary)
    write_csv(repo_root / "data" / "repo_overview.csv", summary["repos"])
    write_activity_summary(repo_root / "docs" / "ACTIVITY_SUMMARY.md", summary)
    write_highlights(repo_root / "docs" / "HIGHLIGHTS.md", summary)
    write_artifact_evidence(repo_root / "docs" / "ARTIFACT_EVIDENCE.md", backup_artifact)
    write_landing_page(repo_root / "index.html", summary)
    write_content_pages(repo_root)
    (repo_root / ".nojekyll").write_text("", encoding="utf-8")

    month_labels = list(summary["monthly"].keys())
    month_values = list(summary["monthly"].values())
    make_bar_svg(
        "Коммиты по месяцам",
        "Динамика подтверждённой активности в локальном архиве.",
        month_labels,
        month_values,
        repo_root / "assets" / "commits_by_month.svg",
    )
    make_line_svg(
        "Тренд активности по месяцам",
        "Показывает темп работы и изменение нагрузки по времени.",
        month_labels,
        month_values,
        repo_root / "assets" / "commits_trend.svg",
    )

    yearly_labels = list(summary["yearly"].keys())
    yearly_values = list(summary["yearly"].values())
    make_yearly_bar_svg(
        "Коммиты по годам",
        "Сводная интенсивность по подтверждённым периодам.",
        yearly_labels,
        yearly_values,
        repo_root / "assets" / "commits_by_year.svg",
    )

    repo_labels = [repo["public_name"] for repo in summary["repos"][:6]]
    repo_values = [repo["commits"] for repo in summary["repos"][:6]]
    make_bar_svg(
        "Коммиты по ключевым потокам",
        "Крупнейшие подтверждённые направления по объёму вклада.",
        repo_labels,
        repo_values,
        repo_root / "assets" / "commits_by_repo.svg",
    )
    make_timeline_svg(
        "Ключевые рабочие потоки во времени",
        "Видно, какие направления шли дольше и где был самый плотный вклад.",
        summary["repos"][:8],
        repo_root / "assets" / "workstream_timeline.svg",
    )

    tech_counter = build_tech_counter(summary)
    tech_labels = [item[0] for item in tech_counter.most_common(8)]
    tech_values = [item[1] for item in tech_counter.most_common(8)]
    make_bar_svg(
        "Покрытие стека по потокам",
        "Сколько подтверждённых потоков содержат практическую работу с конкретным стеком.",
        tech_labels,
        tech_values,
        repo_root / "assets" / "tech_coverage.svg",
    )
    if backup_artifact:
        artifact_labels = list(backup_artifact["counts"].keys())
        artifact_values = list(backup_artifact["counts"].values())
        make_bar_svg(
            "Состав backup automation toolkit",
            "Отдельный рабочий артефакт без git-истории, вынесенный в портфолио как non-git evidence.",
            artifact_labels,
            artifact_values,
            repo_root / "assets" / "backup_artifact_map.svg",
        )
    make_stat_cards_svg(summary, repo_root / "assets" / "portfolio_snapshot.svg")


if __name__ == "__main__":
    main()
