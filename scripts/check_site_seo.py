#!/usr/bin/env python3
"""Check sitemap-backed site pages for basic crawl and canonical regressions."""

from datetime import date, datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
SITE_PATH = "/NearByDrop/"
SITEMAP = ROOT / "docs/sitemap.xml"
TEXT_SITEMAP = ROOT / "docs/sitemap.txt"
NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


class PageMetadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = []
        self.h1s = []
        self.description = ""
        self.canonical = ""
        self.robots = ""
        self.links = []
        self.stylesheets = []
        self.capture = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self.capture = "title"
        elif tag == "h1":
            self.h1s.append([])
            self.capture = "h1"
        elif tag == "meta":
            name = attrs.get("name", "").lower()
            if name == "description":
                self.description = attrs.get("content", "").strip()
            elif name == "robots":
                self.robots = attrs.get("content", "").lower()
        elif tag == "link":
            rel = attrs.get("rel", "").lower().split()
            href = attrs.get("href", "").strip()
            if "canonical" in rel:
                self.canonical = href
            if "stylesheet" in rel:
                self.stylesheets.append(href)
        elif tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])

    def handle_endtag(self, tag):
        if (tag == "title" and self.capture == "title") or (tag == "h1" and self.capture == "h1"):
            self.capture = None

    def handle_data(self, data):
        if self.capture == "title":
            self.title.append(data.strip())
        elif self.capture == "h1" and self.h1s:
            self.h1s[-1].append(data.strip())


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def local_page_path(url_path):
    relative = unquote(url_path[len(SITE_PATH):])
    target = ROOT / "docs" / (relative or "index.html")
    if url_path.endswith("/"):
        target = target / "index.html" if relative else ROOT / "docs/index.html"
    target = target.resolve()
    docs = (ROOT / "docs").resolve()
    return target if target == docs or docs in target.parents else None


def main():
    if local_page_path(SITE_PATH) != (ROOT / "docs/index.html").resolve() or local_page_path(SITE_PATH + "../../README.md") is not None:
        return fail("site path resolution self-check failed")

    try:
        sitemap = ET.parse(SITEMAP).getroot()
    except (OSError, ET.ParseError) as exc:
        return fail(f"cannot parse {SITEMAP}: {exc}")

    urls = []
    errors = []
    today = datetime.now(timezone.utc).date()
    for entry in sitemap.findall("sm:url", NS):
        loc = (entry.findtext("sm:loc", default="", namespaces=NS) or "").strip()
        parsed = urlsplit(loc)
        if parsed.scheme != "https" or parsed.netloc != "arslanbasharat-o-o.github.io" or not parsed.path.startswith(SITE_PATH):
            errors.append(f"invalid or out-of-site sitemap URL: {loc}")
            continue
        lastmod = (entry.findtext("sm:lastmod", default="", namespaces=NS) or "").strip()
        try:
            if lastmod and date.fromisoformat(lastmod[:10]) > today:
                errors.append(f"future lastmod on {loc}: {lastmod}")
        except ValueError:
            errors.append(f"invalid lastmod on {loc}: {lastmod}")
        urls.append(loc)

    if not urls:
        errors.append("sitemap contains no valid URLs")
    if len(urls) != len(set(urls)):
        errors.append("sitemap contains duplicate URLs")
    try:
        text_urls = [line.strip() for line in TEXT_SITEMAP.read_text(encoding="utf-8").splitlines() if line.strip()]
        if text_urls != urls:
            errors.append("plain-text sitemap URLs must match the XML sitemap URLs in order")
    except OSError as exc:
        errors.append(f"cannot read {TEXT_SITEMAP}: {exc}")

    titles, descriptions, headings = set(), set(), set()
    for page_url in urls:
        page_path = local_page_path(urlsplit(page_url).path)
        if page_path is None or not page_path.is_file():
            errors.append(f"sitemap URL has no published file: {page_url}")
            continue

        page = PageMetadata()
        try:
            source = page_path.read_text(encoding="utf-8")
            page.feed(source)
        except OSError as exc:
            errors.append(f"cannot read sitemap page {page_url}: {exc}")
            continue

        expected_stylesheet = urljoin(page_url, "assets/site.css" if page_url.endswith("/") else "../assets/site.css")
        if expected_stylesheet not in {urljoin(page_url, href) for href in page.stylesheets}:
            errors.append(f"missing local site stylesheet: {page_path.relative_to(ROOT)}")
        if "cdn.tailwindcss.com" in source:
            errors.append(f"Tailwind Play CDN must not be used in production: {page_path.relative_to(ROOT)}")

        title = " ".join(" ".join(page.title).split())
        h1s = [" ".join(" ".join(h1).split()) for h1 in page.h1s]
        relative_path = page_path.relative_to(ROOT)
        if not title:
            errors.append(f"missing title: {relative_path}")
        elif title in titles:
            errors.append(f"duplicate title: {title}")
        titles.add(title)
        if not page.description:
            errors.append(f"missing meta description: {relative_path}")
        elif page.description in descriptions:
            errors.append(f"duplicate meta description: {page.description}")
        descriptions.add(page.description)
        if page.canonical != page_url:
            errors.append(f"canonical mismatch in {relative_path}: {page.canonical!r}")
        if "noindex" in page.robots:
            errors.append(f"noindex page is listed in sitemap: {relative_path}")
        if len(h1s) != 1 or not h1s[0]:
            errors.append(f"expected one non-empty H1 in {relative_path}")
        elif h1s[0] in headings:
            errors.append(f"duplicate H1: {h1s[0]}")
        if h1s:
            headings.add(h1s[0])

        for href in page.links:
            target = urlsplit(urljoin(page_url, href))
            if target.netloc != "arslanbasharat-o-o.github.io":
                continue
            if not target.path.startswith(SITE_PATH):
                errors.append(f"same-host link escapes project root in {relative_path}: {href}")
                continue
            if target.path.endswith("/index.html"):
                errors.append(f"internal link uses index.html alias: {relative_path} -> {href}")
            target_path = local_page_path(target.path)
            if target_path is None or not target_path.is_file():
                errors.append(f"broken internal link in {relative_path}: {href}")

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"SEO checks passed: {len(urls)} sitemap URLs, unique titles, canonicals, metadata, and internal links.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
