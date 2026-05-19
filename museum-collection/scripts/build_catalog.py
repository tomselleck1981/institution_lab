#!/usr/bin/env python3
"""Build public catalog data for a partner museum collection prototype.

The source spreadsheet is treated as the local source of truth for v0. This
sanitized handoff keeps the parsing helpers and conventions, but excludes the
private source data files and generated catalog exports.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import re
import uuid
from pathlib import Path
from typing import Any

from numbers_parser import Document


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "collection_source.numbers"
CANDIDATES_PATH = ROOT / "subcollection_candidates.csv"
TEMPLATE_PATH = ROOT / "site-mockup" / "_template.html"
DATA_DIR = ROOT / "data"
SITE_DIR = ROOT / "site-testbed"

UUID_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://institution.art/museum-collection")


def clean(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        if value == 0:
            return ""
        if value.is_integer():
            return str(int(value))
    text = str(value).strip()
    if text in {"0", "0.0", "nan", "None"}:
        return ""
    return re.sub(r"\s+", " ", text)


def clean_text(value: Any) -> str:
    text = clean(value)
    if not text:
        return ""
    return text.replace(" | ", "\n").strip()


def parse_year(*values: Any) -> int | None:
    for value in values:
        text = clean(value)
        if not text:
            continue
        match = re.search(r"(1[4-9]\d{2}|20[0-2]\d)", text)
        if match:
            year = int(match.group(1))
            if 1400 <= year <= 2026:
                return year
    return None


def split_list(value: Any) -> list[str]:
    text = clean(value)
    if not text:
        return []
    parts = re.split(r"\s*(?:,|;|\|)\s*", text)
    out: list[str] = []
    for part in parts:
        part = clean(part)
        if part and part.lower() not in {"none", "0"} and len(part) <= 120:
            out.append(part)
    return list(dict.fromkeys(out))


def normalize_key(title: str, author_last: str, year: int | None = None) -> str:
    bits = [
        re.sub(r"[^a-z0-9]+", " ", title.lower()).strip(),
        re.sub(r"[^a-z0-9]+", " ", author_last.lower()).strip(),
    ]
    if year:
        bits.append(str(year))
    return "|".join(bits)


def slug(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return value or "unknown"


def period_for(year: int | None) -> str:
    if not year:
        return "unknown"
    if year < 1800:
        return "pre-1800"
    if year < 1850:
        return "1800-1850"
    if year < 1900:
        return "1850-1900"
    if year < 1945:
        return "1900-1945"
    if year < 1980:
        return "1945-1980"
    if year < 2000:
        return "1980-2000"
    return "2000-present"


def load_candidates(path: Path) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    by_key: dict[str, dict[str, Any]] = {}
    rows: list[dict[str, Any]] = []
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            title = clean(row.get("title"))
            author_last = clean(row.get("author_last"))
            year = parse_year(row.get("year"))
            key_year = normalize_key(title, author_last, year)
            key_no_year = normalize_key(title, author_last)
            item = {
                "candidate_key": hashlib.sha1(f"{key_year}|{row.get('evidence_quote','')}".encode()).hexdigest()[:16],
                "match_key_year": key_year,
                "match_key_no_year": key_no_year,
                "subcollection_slug": clean(row.get("subcollection_slug")) or "featured-subcollection",
                "title": title,
                "author_first": clean(row.get("author_first")),
                "author_last": author_last,
                "year": year,
                "inclusion_basis": clean(row.get("inclusion_basis")) or "subject",
                "confidence": float(clean(row.get("confidence")) or 0),
                "matched_terms": clean(row.get("matched_terms")),
                "evidence_quote": clean_text(row.get("evidence_quote")),
                "negative_flags": clean(row.get("negative_flags")),
                "review_status": "proposed",
            }
            rows.append(item)
            by_key.setdefault(key_year, item)
            by_key.setdefault(key_no_year, item)
    return by_key, rows


def load_numbers(path: Path) -> list[dict[str, Any]]:
    table = Document(str(path)).sheets[0].tables[0]
    headers = [clean(table.cell(0, c).value) for c in range(table.num_cols)]
    rows: list[dict[str, Any]] = []
    for r in range(1, table.num_rows):
        raw = {headers[c]: table.cell(r, c).value for c in range(table.num_cols)}
        title = clean(raw.get("Title"))
        if title:
            rows.append(raw)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase-url", default="")
    parser.add_argument("--supabase-anon-key", default="")
    parser.parse_args()
    raise SystemExit("This sanitized handoff omits local source data. Run from the full local workspace to build catalog exports.")


if __name__ == "__main__":
    main()
