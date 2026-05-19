#!/usr/bin/env node
/**
 * Deterministic cover audit for a partner museum collection prototype.
 *
 * Inputs:
 * - museum-collection/data/supabase-books.json
 *
 * Outputs:
 * - museum-collection/data/cover-audit-results.json
 * - museum-collection/data/cover-overrides.json
 *
 * Secrets are read from the environment and never written to disk:
 * - SUPABASE_URL
 * - SUPABASE_SERVICE_KEY
 */

import fs from 'node:fs';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DATA_DIR = path.join(ROOT, 'data');
const BOOKS_PATH = path.join(DATA_DIR, 'supabase-books.json');
const RESULTS_PATH = path.join(DATA_DIR, 'cover-audit-results.json');
const OVERRIDES_PATH = path.join(DATA_DIR, 'cover-overrides.json');

const UPDATE_THRESHOLD = Number(process.env.COVER_UPDATE_THRESHOLD || '0.9');
const MAX_RECORDS = Number(process.env.COVER_AUDIT_MAX || '0');
const CONCURRENCY = Number(process.env.COVER_AUDIT_CONCURRENCY || '4');

const GOOGLE_ENDPOINT = 'https://www.googleapis.com/books/v1/volumes';
const OPEN_LIBRARY_SEARCH = 'https://openlibrary.org/search.json';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

function clean(value) {
  return String(value || '').trim().replace(/\s+/g, ' ');
}

function normalize(value) {
  return clean(value).toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}

function tokens(value) {
  return normalize(value).split(/\s+/).filter(t => t.length > 1);
}

function titleSimilarity(a, b) {
  const aa = new Set(tokens(a));
  const bb = new Set(tokens(b));
  if (!aa.size || !bb.size) return 0;
  let overlap = 0;
  for (const token of aa) if (bb.has(token)) overlap++;
  return overlap / Math.max(aa.size, bb.size);
}

function authorMatches(book, authorText) {
  const last = normalize(book.author_last || '');
  if (!last) return true;
  return normalize(authorText || '').includes(last);
}

function yearClose(bookYear, candidateYear) {
  if (!bookYear || !candidateYear) return true;
  return Math.abs(Number(bookYear) - Number(candidateYear)) <= 3;
}

function isLikelyCoverResponse(res) {
  const type = res.headers.get('content-type') || '';
  const len = Number(res.headers.get('content-length') || 0);
  return res.ok && type.startsWith('image/') && (!len || len > 900);
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 9000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function testImage(url) {
  try {
    let res = await fetchWithTimeout(url, { method: 'HEAD', redirect: 'follow' }, 7000);
    if (isLikelyCoverResponse(res)) return true;
    res = await fetchWithTimeout(url, { method: 'GET', redirect: 'follow', headers: { Range: 'bytes=0-2048' } }, 9000);
    return isLikelyCoverResponse(res);
  } catch {
    return false;
  }
}

async function fromOpenLibrarySearch(book) {
  const params = new URLSearchParams({
    title: clean(book.title),
    author: clean(book.author_display || [book.author_first, book.author_last].filter(Boolean).join(' ')),
    fields: 'key,title,author_name,first_publish_year,cover_i,edition_key',
    limit: '5',
  });
  try {
    const res = await fetchWithTimeout(`${OPEN_LIBRARY_SEARCH}?${params}`, {
      headers: { 'User-Agent': 'institution.art collection cover audit' },
    }, 9000);
    if (!res.ok) return null;
    const json = await res.json();
    for (const doc of json.docs || []) {
      if (!doc.cover_i) continue;
      const titleScore = titleSimilarity(book.title, doc.title);
      const authorOk = authorMatches(book, (doc.author_name || []).join(' '));
      const yearOk = yearClose(book.original_pub_year, doc.first_publish_year);
      let confidence = titleScore;
      if (authorOk) confidence += 0.12;
      if (yearOk) confidence += 0.06;
      confidence = Math.min(0.94, confidence);
      if (titleScore >= 0.78 && authorOk && confidence >= 0.86) {
        const url = `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg`;
        if (!(await testImage(url))) continue;
        return { source: 'open_library_search', url, confidence };
      }
    }
  } catch {
    return null;
  }
  return null;
}

async function fromGoogleBooks(book) {
  const queryParts = [`intitle:${book.title}`];
  if (book.author_last) queryParts.push(`inauthor:${book.author_last}`);
  const params = new URLSearchParams({ q: queryParts.join(' '), printType: 'books', projection: 'lite', maxResults: '5' });
  try {
    const res = await fetchWithTimeout(`${GOOGLE_ENDPOINT}?${params}`, {}, 9000);
    if (!res.ok) return null;
    const json = await res.json();
    for (const item of json.items || []) {
      const info = item.volumeInfo || {};
      const links = info.imageLinks || {};
      const url = links.extraLarge || links.large || links.medium || links.small || links.thumbnail || links.smallThumbnail;
      if (!url) continue;
      const titleScore = titleSimilarity(book.title, info.title || '');
      const authorOk = authorMatches(book, (info.authors || []).join(' '));
      let confidence = titleScore + (authorOk ? 0.11 : 0);
      confidence = Math.min(0.91, confidence);
      if (titleScore >= 0.82 && authorOk && confidence >= 0.88) {
        const httpsUrl = url.replace(/^http:/, 'https:');
        if (!(await testImage(httpsUrl))) continue;
        return { source: 'google_books', url: httpsUrl, confidence };
      }
    }
  } catch {
    return null;
  }
  return null;
}

async function findCover(book) {
  await delay(80);
  return (await fromOpenLibrarySearch(book)) || (await fromGoogleBooks(book)) || { source: 'not_found', url: null, confidence: 0 };
}

async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let index = 0;
  async function worker(workerId) {
    while (index < items.length) {
      const current = index++;
      out[current] = await fn(items[current], current, workerId);
    }
  }
  await Promise.all(Array.from({ length: limit }, (_, i) => worker(i)));
  return out;
}

async function main() {
  const allBooks = readJson(BOOKS_PATH);
  let missing = allBooks.filter(book => !book.cover_url);
  if (MAX_RECORDS > 0) missing = missing.slice(0, MAX_RECORDS);

  const results = await mapLimit(missing, CONCURRENCY, async (book) => ({
    book_id: book.id,
    public_id: book.public_id,
    title: book.title,
    ...(await findCover(book)),
  }));

  const updates = results.filter(r => r.url && r.confidence >= UPDATE_THRESHOLD);
  const overrides = Object.fromEntries(updates.map(match => [match.book_id, {
    cover_url: match.url,
    cover_status: 'available',
    source: match.source,
    confidence: Number(match.confidence.toFixed(3)),
    updated_at: new Date().toISOString(),
  }]));

  writeJson(RESULTS_PATH, { checked: results.length, results });
  writeJson(OVERRIDES_PATH, overrides);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
