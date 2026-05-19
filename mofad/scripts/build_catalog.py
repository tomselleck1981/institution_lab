#!/usr/bin/env python3
"""Build MoFAD public catalog data from the Rose Collection Numbers sheet.

The spreadsheet is the source of truth for v0. This script reads the real
Numbers table, normalizes row/column values conservatively, joins the Jewish
Collection candidate CSV, and writes static JSON plus a rendered site file.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import uuid
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from numbers_parser import Document


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "Claude Template ROSE COLLECTION.numbers"
CANDIDATES_PATH = ROOT / "jewish_collection_candidates.csv"
TEMPLATE_PATH = ROOT / "site-mockup" / "_template.html"
DATA_DIR = ROOT / "data"
SITE_DIR = ROOT / "site-testbed"
COVER_OVERRIDES_PATH = DATA_DIR / "cover-overrides.json"

UUID_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://institution.art/mofad/rose-collection")


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


def split_urls(*values: Any) -> list[str]:
    urls: list[str] = []
    for value in values:
        text = clean(value)
        if not text:
            continue
        for part in re.split(r"\s*\|\s*|\s+", text):
            part = part.strip()
            if part.startswith("http://") or part.startswith("https://"):
                urls.append(part)
    return list(dict.fromkeys(urls))


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


CUISINE_TERMS = [
    ("Jewish (general)", ["jewish", "kosher", "passover", "pesach", "ashkenazi", "sephardic", "israeli", "israel"]),
    ("American", ["american", "united states", "u.s.", "southern"]),
    ("British", ["british", "english", "england"]),
    ("French", ["french", "france", "paris", "provence"]),
    ("Italian", ["italian", "italy", "sicily", "tuscany"]),
    ("Chinese", ["chinese", "china", "cantonese", "szechuan", "sichuan"]),
    ("Japanese", ["japanese", "japan"]),
    ("Mexican", ["mexican", "mexico"]),
    ("Indian", ["indian", "india"]),
    ("Middle Eastern", ["middle eastern", "lebanese", "syrian", "persian", "moroccan"]),
    ("Caribbean", ["caribbean", "jamaican", "haitian", "cuban"]),
    ("African", ["african", "ethiopian", "nigerian"]),
]


FORMAT_TERMS = [
    ("reference", ["dictionary", "encyclopedia", "guide", "manual", "lexicon"]),
    ("memoir", ["memoir", "life", "autobiography"]),
    ("community-cookbook", ["sisterhood", "church", "temple", "congregation", "auxiliary", "club"]),
    ("wine-spirits", ["wine", "cocktail", "beer", "spirits"]),
    ("narrative-cookbook", ["cookbook", "cookery", "cooking", "recipes", "receipt"]),
]


def classify(text: str, terms: list[tuple[str, list[str]]], fallback: str | None = None) -> list[str]:
    hay = text.lower()
    found = [label for label, needles in terms if any(n in hay for n in needles)]
    if not found and fallback:
        return [fallback]
    return found


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
            confidence = float(clean(row.get("confidence")) or 0)
            item = {
                "candidate_key": hashlib.sha1(f"{key_year}|{row.get('evidence_quote','')}".encode()).hexdigest()[:16],
                "match_key_year": key_year,
                "match_key_no_year": key_no_year,
                "subcollection_slug": "jewish-collection",
                "title": title,
                "author_first": clean(row.get("author_first")),
                "author_last": author_last,
                "author_display": " ".join(p for p in [clean(row.get("author_first")), author_last] if p),
                "year": year,
                "inclusion_basis": clean(row.get("inclusion_basis")) or "subject",
                "confidence": confidence,
                "matched_terms": clean(row.get("matched_terms")),
                "evidence_quote": clean_text(row.get("evidence_quote")),
                "negative_flags": clean(row.get("negative_flags")),
                "source_payload": {
                    "ol_identifier": clean(row.get("ol_identifier")),
                    "ia_identifier": clean(row.get("ia_identifier")),
                    "shelf_code": clean(row.get("shelf_code")),
                    "current_location": clean(row.get("current_location")),
                },
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
        if not title:
            continue
        rows.append(raw)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase-url", default="")
    parser.add_argument("--supabase-anon-key", default="")
    args = parser.parse_args()
    raise SystemExit("This sanitized handoff omits local source data. Run from the full local workspace to build catalog exports.")


if __name__ == "__main__":
    main()
