#!/usr/bin/env python3

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
EXTERNAL_SCHEMES = {"http", "https", "mailto", "tel", "data"}


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.refs: list[str] = []
        self.modes: set[str] = set()
        self.filters: set[str] = set()
        self.audiences: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = dict(attrs)
        if data.get("id"):
            self.ids.add(data["id"] or "")
        for key in ("href", "src"):
            if data.get(key):
                self.refs.append(data[key] or "")
        if data.get("data-mode"):
            self.modes.add(data["data-mode"] or "")
        if data.get("data-filter"):
            self.filters.add(data["data-filter"] or "")
        if data.get("data-audiences"):
            self.audiences.update((data["data-audiences"] or "").split())


def resolve_reference(page: Path, reference: str) -> Path | None:
    parsed = urlparse(reference)
    if parsed.scheme in EXTERNAL_SCHEMES or parsed.netloc:
        return None
    if not parsed.path:
        return page
    return (page.parent / unquote(parsed.path)).resolve()


def audit_page(page: Path) -> list[str]:
    parser = PageParser()
    parser.feed(page.read_text(encoding="utf-8"))
    errors: list[str] = []

    for reference in parser.refs:
        target = resolve_reference(page, reference)
        if target is not None and not target.exists():
            errors.append(f"{page.relative_to(ROOT)}: отсутствует {reference}")

    return errors


def audit_home() -> list[str]:
    parser = PageParser()
    index = ROOT / "index.html"
    parser.feed(index.read_text(encoding="utf-8"))
    errors: list[str] = []

    required_modes = {"hr", "tech", "interview", "ai"}
    if parser.modes != required_modes:
        errors.append(f"index.html: режимы {sorted(parser.modes)}, ожидались {sorted(required_modes)}")
    if not required_modes.issubset(parser.audiences):
        errors.append("index.html: не для всех режимов определены audience-секции")
    if "all" not in parser.filters:
        errors.append("index.html: отсутствует базовый фильтр «Все»")

    source = index.read_text(encoding="utf-8")
    for required in (
        "assets/home.css?v=",
        "assets/site.js?v=",
        "data-filter-item",
        "data-categories",
        "data-mode-label",
    ):
        if required not in source:
            errors.append(f"index.html: отсутствует обязательный маркер {required}")

    return errors


def main() -> None:
    errors: list[str] = []
    pages = sorted(ROOT.rglob("*.html"))
    for page in pages:
        errors.extend(audit_page(page))
    errors.extend(audit_home())

    if errors:
        print("Проверка сайта завершилась с ошибками:")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)

    print(f"Проверено HTML-страниц: {len(pages)}")
    print("Локальные ссылки, режимы и фильтры: OK")


if __name__ == "__main__":
    main()
