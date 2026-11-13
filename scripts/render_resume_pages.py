#!/usr/bin/env python3
"""Render the two editorial resume pages without rescanning private archives."""

from html import escape
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PAGES = {
    "RESUME_PUBLIC.md": ("resume.html", "Максим Тюрин — DevOps / Platform Engineer"),
    "DEVSECOPS.md": ("devsecops.html", "Максим Тюрин — опыт DevSecOps"),
}
LINKS = {
    "RESUME_PUBLIC.md": "resume.html", "DEVSECOPS.md": "devsecops.html",
    "CASE_STUDIES.md": "case-studies.html", "PUBLIC_PROJECTS.md": "public-projects.html",
    "RESUME_PORTFOLIO_MAP.md": "resume-portfolio-map.html",
    "ARTIFACT_EVIDENCE.md": "artifact-evidence.html",
}


def inline(text):
    text = escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    def link(match):
        label, href = match.groups()
        name = href.rsplit("/", 1)[-1]
        if name in LINKS:
            href = LINKS[name]
        elif href.startswith("../"):
            pass
        return f'<a href="{href}">{label}</a>'
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


def render(source):
    output, in_list = [], False
    for line in source.splitlines():
        if not line.startswith("- ") and in_list:
            output.append("</ul>")
            in_list = False
        if not line.strip():
            continue
        if line.startswith("- "):
            if not in_list:
                output.append("<ul>")
                in_list = True
            output.append(f"<li>{inline(line[2:])}</li>")
        elif line.startswith("#"):
            level = len(line) - len(line.lstrip("#"))
            output.append(f"<h{level}>{inline(line[level:].strip())}</h{level}>")
        else:
            output.append(f"<p>{inline(line)}</p>")
    if in_list:
        output.append("</ul>")
    return "\n".join(output)


for source, (target, title) in PAGES.items():
    body = render((ROOT / "docs" / source).read_text())
    (ROOT / "pages" / target).write_text(f'''<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{escape(title)}</title>
  <meta name="description" content="Опыт Максима Тюрина: Kubernetes, IaC, CI/CD, DevSecOps, безопасность Linux и аварийное восстановление. Пермь, удалённо. Английский B1.">
  <link rel="canonical" href="https://tyurinmacsim-ops.github.io/portfolio/pages/{target}">
  <link rel="stylesheet" href="../assets/site.css">
</head>
<body>
  <div class="bg-orb bg-orb-a"></div><div class="bg-orb bg-orb-b"></div>
  <main class="content-shell"><section class="content-panel">
    <nav class="content-nav"><a class="brand" href="../index.html">Портфолио</a><a href="resume.html">Резюме</a><a href="devsecops.html">DevSecOps</a></nav>
    <article class="prose">{body}</article>
  </section></main>
</body>
</html>
''')
    print(f"Rendered pages/{target}")
