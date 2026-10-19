#!/usr/bin/env python3
"""Enrich research/sources.json with open-access metadata and download full texts.

Run it on a machine with normal internet access (Python 3.9+, curl on PATH):

    python3 research/scripts/fetch_library.py            # every source
    python3 research/scripts/fetch_library.py --only ID  # one or more source ids
    python3 research/scripts/fetch_library.py --no-download   # metadata only

For every source it:
1. Looks the source up in Europe PMC, OpenAlex and Crossref (by PMCID, PMID or DOI) to fill
   in missing identifiers, the abstract, open-access status and licence.
2. Downloads full text when a legal open copy exists (Europe PMC full-text XML, the PMC
   Article Datasets on AWS Open Data, OpenAlex open locations, publisher PDF links) into
   research/library-local/<topic>/. That folder is git-ignored: full texts are never
   committed, so the repository stays small. Each record's `local_files` lists its copies and
   `open_licence_copies` says which of them carry an open licence themselves (Creative
   Commons, public domain, Open Government Licence). The licence is checked per copy: a
   CC-licensed repository manuscript does not make the publisher's PDF openly licensed.
   Paywalled sources are not downloaded; the citation, link and abstract stay in sources.json.
3. Rebuilds INDEX.md and the topic READMEs.

It never tries to get around paywalls or bot challenges: a 403 or an HTML challenge page is
recorded as a failed route and the next legal route is tried.
Set OPENALEX_EMAIL to join OpenAlex's polite pool (optional).
"""

import argparse
import datetime
import difflib
import html
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse

RESEARCH_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES_PATH = os.path.join(RESEARCH_DIR, "sources.json")
TOPICS_PATH = os.path.join(RESEARCH_DIR, "topics.json")
LIBRARY_LOCAL = "library-local"
USER_AGENT = "Mozilla/5.0 (compatible; WindRunLiteratureFetcher/1.0; personal research use)"
API_PAUSE_SECONDS = 0.4


def log(msg):
    print(msg, flush=True)


def curl(url, accept=None, timeout=90):
    """GET url with curl. Returns (http_status, content_type, body_bytes) or (0, '', b'') on failure."""
    fd, tmp = tempfile.mkstemp(prefix="windrun-fetch-")
    os.close(fd)
    cmd = [
        "curl", "-sSL", "--compressed", "--max-time", str(timeout), "--retry", "2",
        "-A", USER_AGENT, "-o", tmp, "-w", "%{http_code} %{content_type}",
    ]
    if accept:
        cmd += ["-H", "Accept: " + accept]
    cmd.append(url)
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 30)
        parts = out.stdout.strip().split(" ", 1)
        status = int(parts[0]) if parts and parts[0].isdigit() else 0
        ctype = parts[1].lower() if len(parts) > 1 else ""
        with open(tmp, "rb") as f:
            body = f.read()
        return status, ctype, body
    except (subprocess.SubprocessError, OSError):
        return 0, "", b""
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def get_json(url):
    time.sleep(API_PAUSE_SECONDS)
    status, _, body = curl(url, accept="application/json", timeout=60)
    if status != 200 or not body:
        return None
    try:
        return json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------- metadata lookups

def europepmc_lookup(src):
    if src.get("pmcid"):
        query = "PMCID:%s" % src["pmcid"]
    elif src.get("pmid"):
        query = "EXT_ID:%s AND SRC:MED" % src["pmid"]
    elif src.get("doi"):
        query = 'DOI:"%s"' % src["doi"]
    else:
        return None
    url = "https://www.ebi.ac.uk/europepmc/webservices/rest/search?" + urllib.parse.urlencode(
        {"query": query, "resultType": "core", "format": "json", "pageSize": "1"}
    )
    data = get_json(url)
    results = (((data or {}).get("resultList") or {}).get("result")) or []
    return results[0] if results else None


def openalex_lookup(src):
    if src.get("doi"):
        key = "doi:" + src["doi"]
    elif src.get("pmid"):
        key = "pmid:" + src["pmid"]
    elif src.get("pmcid"):
        key = "pmcid:" + src["pmcid"]
    else:
        return None
    url = "https://api.openalex.org/works/" + urllib.parse.quote(key, safe=":/")
    if os.environ.get("OPENALEX_EMAIL"):
        url += "?mailto=" + urllib.parse.quote(os.environ["OPENALEX_EMAIL"])
    return get_json(url)


def crossref_lookup(doi):
    if not doi:
        return None
    data = get_json("https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="/"))
    return (data or {}).get("message")


def abstract_from_inverted_index(index):
    if not index:
        return None
    positions = []
    for word, places in index.items():
        for p in places:
            positions.append((p, word))
    positions.sort()
    return " ".join(w for _, w in positions) or None


# Only real tags: "<" + optional "/" + a tag name. A bare "<" in text such as "P < 0.05" or
# "SMD <0.12" is kept (a looser pattern deleted everything up to the next ">").
TAG_RE = re.compile(r"</?[A-Za-z][A-Za-z0-9:.-]*(?:\s[^<>]*)?/?>")


def strip_markup(text):
    if not text:
        return None
    text = re.sub(r"<jats:title>.*?</jats:title>", " ", text, flags=re.S)
    text = TAG_RE.sub(" ", text)
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip() or None


# ---------------------------------------------------------------- licences

CC_URL_RE = re.compile(r"creativecommons\.org/(licenses|publicdomain)/([a-z\-]+)/?([0-9.]+)?", re.I)
CC_NAME_RE = re.compile(r"^cc-?(by(?:-nc)?(?:-nd)?(?:-sa)?)(?:-v?([0-9.]+))?\b")


def normalize_license(raw):
    """Return (display_name, redistributable) for a licence string or URL, or (None, False)."""
    if not raw:
        return None, False
    text = str(raw).strip()
    low = text.lower()
    m = CC_URL_RE.search(low)
    if m:
        kind, code, version = m.group(1), m.group(2), m.group(3)
        if kind == "publicdomain":
            return ("CC0 1.0" if code == "zero" else "Public domain"), True
        return ("CC %s %s" % (code.upper(), version or "")).strip(), True
    compact = re.sub(r"[\s_]+", "-", low)
    if compact.startswith("cc0") or compact.startswith("cc-zero"):
        return "CC0", True
    m = CC_NAME_RE.match(compact)
    if m:
        return ("CC %s %s" % (m.group(1).upper(), m.group(2) or "")).strip(), True
    if "public-domain" in compact or compact in ("pd", "us-gov"):
        return "Public domain", True
    if "open-government-licence" in compact or compact.startswith("ogl"):
        return "Open Government Licence", True
    # publisher-specific-oa, other-oa, implied-oa, publisher text-mining licences, etc.
    return text, False


def location_license(loc):
    """Licence of one OpenAlex location. A 'public-domain' label on a repository copy is ignored:
    OpenAlex has been seen to take a repository's CC0 *metadata* notice for the item's licence."""
    name, is_open = normalize_license((loc or {}).get("license"))
    if is_open and name == "Public domain" and (loc or {}).get("version") != "publishedVersion":
        return None, False
    return name, is_open


def best_license(src, epmc, oalex, xref):
    """Pick an open licence from any source; otherwise keep a non-open label (never a bare URL)."""
    named = [src.get("license")]
    if epmc:
        named.append(epmc.get("license"))
    if oalex:
        named.extend(location_license(loc)[0] for loc in [oalex.get("best_oa_location")] + list(oalex.get("locations") or []))
    urls = [lic.get("URL") for lic in (xref or {}).get("license") or [] if lic.get("content-version") != "am"]
    fallback = None
    for c in named + urls:
        name, redistributable = normalize_license(c)
        if redistributable:
            return name, True
        if name and not fallback and c in named and "://" not in name:
            fallback = name
    return fallback, False


# A licence can cover only one copy of a paper (say a repository's accepted manuscript) while
# the publisher's version stays all rights reserved, so each downloaded copy is checked on its own.
NON_VOR_HINT_RE = re.compile(r"\b(repository|accepted|manuscript|submitted|per openalex|copy|version)\b", re.I)


def published_version_open(src, epmc, oalex, xref):
    """True when the publisher's version itself carries an open licence."""
    own = src.get("license") or ""
    if normalize_license(own)[1] and not NON_VOR_HINT_RE.search(own):
        return True
    for lic in (xref or {}).get("license") or []:
        if lic.get("content-version") != "am" and normalize_license(lic.get("URL"))[1]:
            return True
    if oalex:
        locations = [oalex.get("primary_location") or {}] + [
            loc for loc in oalex.get("locations") or [] if loc.get("version") == "publishedVersion"
        ]
        if any(normalize_license(loc.get("license"))[1] for loc in locations):
            return True
    if epmc and epmc.get("authMan") != "Y" and normalize_license(epmc.get("license"))[1]:
        return True
    return False


# ---------------------------------------------------------------- enrichment

GUIDE_TYPES = {"organization-guide", "training-plan-template", "coaching-manual", "public-health-guideline", "book"}


def title_similarity(a, b):
    def norm(t):
        return re.sub(r"[^a-z0-9 ]", "", strip_markup(t or "").lower() or "")
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()


def openalex_title_match(src):
    """Find a DOI for a paper that has no identifiers, by a close title + year match in OpenAlex."""
    if not src.get("title") or src.get("source_type") in GUIDE_TYPES:
        return None
    url = "https://api.openalex.org/works?" + urllib.parse.urlencode(
        {"filter": "title.search:" + re.sub(r"[,:;|]", " ", src["title"])[:250], "per-page": "5"}
    )
    for work in (get_json(url) or {}).get("results") or []:
        year_ok = not src.get("year") or not work.get("publication_year") or abs(work["publication_year"] - src["year"]) <= 1
        if year_ok and title_similarity(src["title"], work.get("title")) >= 0.92:
            return work
    return None


def api_title_and_year(epmc, oalex, xref):
    if epmc and epmc.get("title"):
        return epmc["title"], int(epmc["pubYear"]) if str(epmc.get("pubYear", "")).isdigit() else None
    if oalex and oalex.get("title"):
        return oalex["title"], oalex.get("publication_year")
    if xref and xref.get("title"):
        parts = (xref.get("issued") or {}).get("date-parts") or [[None]]
        return xref["title"][0], parts[0][0]
    return None, None


def titles_agree(title, epmc, oalex, xref):
    """True when the record title matches any API title, allowing for subtitles kept or dropped."""
    candidates = [(epmc or {}).get("title"), (oalex or {}).get("title")]
    for main in (xref or {}).get("title") or []:
        candidates.append(main)
        candidates.extend("%s: %s" % (main, sub) for sub in (xref or {}).get("subtitle") or [])
    mine = re.sub(r"[^a-z0-9]", "", (strip_markup(title) or "").lower())
    for cand in candidates:
        theirs = re.sub(r"[^a-z0-9]", "", (strip_markup(cand) or "").lower())
        if not theirs:
            continue
        if title_similarity(title, cand) >= 0.75 or (len(theirs) >= 15 and (theirs in mine or mine in theirs)):
            return True
    return False


def enrich(src):
    had_ids = any(src.get(k) for k in ("doi", "pmid", "pmcid"))
    if not had_ids:
        work = openalex_title_match(src)
        if work:
            ids = work.get("ids") or {}
            src["doi"] = (work.get("doi") or "").replace("https://doi.org/", "") or None
            src["pmid"] = (ids.get("pmid") or "").rstrip("/").split("/")[-1] or None
            src["pmcid"] = (ids.get("pmcid") or "").rstrip("/").split("/")[-1] or None
            src["ids_from_title_match"] = True
    epmc = europepmc_lookup(src)
    oalex = openalex_lookup(src)
    xref = crossref_lookup(src.get("doi") or (epmc or {}).get("doi"))
    src.pop("metadata_warning", None)
    if had_ids:
        api_title, api_year = api_title_and_year(epmc, oalex, xref)
        if not api_title:
            src["metadata_warning"] = "identifiers not found in Europe PMC, OpenAlex or Crossref"
        elif not titles_agree(src.get("title"), epmc, oalex, xref):
            src["metadata_warning"] = "title differs from the record for its identifiers: %s" % strip_markup(api_title)
        elif src.get("year") and api_year and abs(int(api_year) - int(src["year"])) > 1:
            src["metadata_warning"] = "year %s differs from the record (%s)" % (src["year"], api_year)
    if epmc:
        for field in ("doi", "pmid", "pmcid"):
            if not src.get(field) and epmc.get(field):
                src[field] = epmc[field]
        if epmc.get("abstractText"):
            src["abstract"] = strip_markup(epmc["abstractText"])
            src["abstract_source"] = "Europe PMC"
    if oalex:
        oa = oalex.get("open_access") or {}
        src["oa_status"] = oa.get("oa_status")
        ids = oalex.get("ids") or {}
        if not src.get("doi") and oalex.get("doi"):
            src["doi"] = oalex["doi"].replace("https://doi.org/", "")
        if not src.get("pmid") and ids.get("pmid"):
            src["pmid"] = ids["pmid"].rstrip("/").split("/")[-1]
        if not src.get("pmcid") and ids.get("pmcid"):
            src["pmcid"] = ids["pmcid"].rstrip("/").split("/")[-1]
        if not src.get("abstract"):
            text = abstract_from_inverted_index(oalex.get("abstract_inverted_index"))
            if text:
                src["abstract"] = text
                src["abstract_source"] = "OpenAlex"
    if xref and not src.get("abstract") and xref.get("abstract"):
        src["abstract"] = strip_markup(xref["abstract"])
        src["abstract_source"] = "Crossref"
    license_name, redistributable = best_license(src, epmc, oalex, xref)
    if normalize_license(src.get("license"))[1]:
        license_name = src["license"]  # keep a curated label (it may say which copy it covers)
    elif redistributable and not published_version_open(src, epmc, oalex, xref):
        license_name += " (repository or manuscript copy only)"
    if license_name:
        src["license"] = license_name
    is_oa = bool(
        redistributable
        or (epmc and "Y" in (epmc.get("isOpenAccess"), epmc.get("inPMC"), epmc.get("inEPMC")))
        or (oalex and (oalex.get("open_access") or {}).get("is_oa"))
        or src.get("access") in ("open-license", "free-to-read")
    )
    if redistributable:
        src["access"] = "open-license"
    elif is_oa and src.get("access") in (None, "unknown", "paywalled"):
        src["access"] = "free-to-read"
    elif not is_oa and src.get("access") in (None, "unknown"):
        src["access"] = "paywalled"
    return epmc, oalex, xref, redistributable, is_oa


# ---------------------------------------------------------------- downloads

def looks_like(kind, ctype, body):
    head = body[:1024].lstrip()
    if kind == "pdf":
        return body[:5] == b"%PDF-" or b"%PDF-" in body[:1024]
    if kind == "xml":
        return head.startswith(b"<?xml") or head.startswith(b"<article") or head.startswith(b"<!DOCTYPE article")
    if kind == "html":
        return "html" in ctype and b"cf-chl" not in body[:20000] and len(body) > 2000
    return False


# PDF pages on these hosts always answer scripts with a bot or proof-of-work challenge.
CHALLENGE_PDF_RE = re.compile(r"europepmc\.org/.*pdf=render|(pmc\.ncbi\.nlm\.nih\.gov|ncbi\.nlm\.nih\.gov/pmc)/articles/.*pdf", re.I)
PMC_OPEN_DATA = "https://pmc-oa-opendata.s3.amazonaws.com/"


def pmc_open_data(pmcid):
    """Article record from the PMC Article Datasets on AWS Open Data (NLM's bulk route for
    open-access PMC articles). Returns the latest version's metadata JSON, or None."""
    time.sleep(API_PAUSE_SECONDS)
    status, _, body = curl(PMC_OPEN_DATA + "?" + urllib.parse.urlencode({"list-type": "2", "prefix": pmcid + "."}), timeout=60)
    if status != 200:
        return None
    versions = re.findall(r"<Key>(%s\.(\d+))/[^<]+\.json</Key>" % re.escape(pmcid), body.decode("utf-8", "replace"))
    if not versions:
        return None
    folder = max(versions, key=lambda v: int(v[1]))[0]
    return get_json(PMC_OPEN_DATA + "%s/%s.json" % (folder, folder))


def pmc_open_data_url(s3_url):
    return PMC_OPEN_DATA + s3_url.replace("s3://pmc-oa-opendata/", "").split("?")[0] if s3_url else None


def pdf_candidates(src, epmc, oalex, xref, vor_open, pmc_copy_open, pmc_record):
    """Ordered (url, openly_licensed_copy) pairs for every legal PDF route."""
    candidates = []
    if pmc_record and pmc_record.get("pdf_url"):
        candidates.append((pmc_open_data_url(pmc_record["pdf_url"]), pmc_copy_open))
    location_open = {}
    if oalex:
        for loc in [oalex.get("best_oa_location") or {}] + list(oalex.get("locations") or []):
            if loc.get("pdf_url") and loc.get("is_oa"):
                is_open = location_license(loc)[1] or (vor_open and loc.get("version") == "publishedVersion")
                location_open[loc["pdf_url"]] = location_open.get(loc["pdf_url"], False) or is_open
    if src.get("pdf_url"):
        candidates.append((src["pdf_url"], vor_open or location_open.get(src["pdf_url"], False)))
    candidates.extend(location_open.items())
    if epmc:
        for item in ((epmc.get("fullTextUrlList") or {}).get("fullTextUrl")) or []:
            if item.get("documentStyle") == "pdf" and item.get("availabilityCode") in ("OA", "F") and item.get("url"):
                candidates.append((item["url"], vor_open and item.get("site") == "DOI"))
    if xref:
        for link in xref.get("link") or []:
            if link.get("content-type") == "application/pdf" and link.get("URL"):
                candidates.append((link["URL"], vor_open and link.get("content-version") != "am"))
    seen, ordered = set(), []
    for url, is_open in candidates:
        if url and url not in seen and not CHALLENGE_PDF_RE.search(url):
            seen.add(url)
            ordered.append((url, is_open))
    ordered.sort(key=lambda c: not c[1])  # openly licensed copies first, otherwise keep the order
    return ordered


def save(body, research_rel_path):
    path = os.path.join(RESEARCH_DIR, research_rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(body)


def existing_files(src):
    """Return copies already on disk so reruns skip them."""
    return {
        kind: rel
        for kind, rel in (src.get("local_files") or {}).items()
        if rel and os.path.exists(os.path.join(RESEARCH_DIR, rel))
    }


def download(src, folder, is_oa, epmc, oalex, xref, force):
    """Download every legal open copy. Returns (local_files, open_licence_copies, status)."""
    notes = []
    present = {} if force else existing_files(src)
    local_files = dict(present)
    open_copies = [k for k in src.get("open_licence_copies") or [] if k in present]
    if not is_oa:
        return local_files, open_copies, ("local copy kept" if present else "no open copy (citation only)")

    vor_open = published_version_open(src, epmc, oalex, xref)
    pmc_record = pmc_open_data(src["pmcid"]) if src.get("pmcid") and not ("xml" in present and "pdf" in present) else None
    pmc_copy_open = bool(
        normalize_license((pmc_record or {}).get("license_code"))[1]
        or (epmc and normalize_license(epmc.get("license"))[1])
        or (vor_open and not (pmc_record or {}).get("is_manuscript") and (epmc or {}).get("authMan") != "Y")
    )

    def place(kind, body, ext, copy_open):
        rel = "%s/%s/%s.%s" % (LIBRARY_LOCAL, folder, src["id"], ext)
        save(body, rel)
        local_files[kind] = rel
        if copy_open:
            open_copies.append(kind)

    # Full-text XML: Europe PMC first, then the PMC open data copy.
    if "xml" not in present and src.get("pmcid"):
        status = 0
        if epmc and (epmc.get("isOpenAccess") == "Y" or epmc.get("inEPMC") == "Y"):
            status, ctype, body = curl("https://www.ebi.ac.uk/europepmc/webservices/rest/%s/fullTextXML" % src["pmcid"])
            if status == 200 and looks_like("xml", ctype, body):
                place("xml", body, "xml", pmc_copy_open)
        if "xml" not in local_files and pmc_record and pmc_record.get("xml_url"):
            status, ctype, body = curl(pmc_open_data_url(pmc_record["xml_url"]))
            if status == 200 and looks_like("xml", ctype, body):
                place("xml", body, "xml", pmc_copy_open)
        if "xml" not in local_files:
            notes.append("full-text XML unavailable (HTTP %s)" % status)

    if "pdf" not in present:
        for url, copy_open in pdf_candidates(src, epmc, oalex, xref, vor_open, pmc_copy_open, pmc_record):
            status, ctype, body = curl(url)
            if status == 200 and looks_like("pdf", ctype, body):
                place("pdf", body, "pdf", copy_open)
                break
            notes.append("PDF route failed: %s (HTTP %s%s)" % (url, status, ", not a PDF" if status == 200 else ""))

    # Web guides with no PDF: keep an HTML snapshot of the page itself.
    if not local_files and not (src.get("doi") or src.get("pmid")) and src.get("url"):
        status, ctype, body = curl(src["url"])
        if status == 200 and looks_like("html", ctype, body):
            place("html", body, "html", normalize_license(src.get("license"))[1])
        else:
            notes.append("page snapshot failed (HTTP %s)" % status)

    if local_files:
        status = "local copy (openly licensed)" if open_copies else "local copy (not openly licensed)"
    else:
        status = "open copy not downloadable"
        if notes:
            status += "; " + "; ".join(notes[-3:])
    return local_files, sorted(set(open_copies)), status


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="+", help="source ids to process")
    parser.add_argument("--no-download", action="store_true", help="only enrich metadata")
    parser.add_argument("--force", action="store_true", help="re-download files that already exist")
    args = parser.parse_args()

    with open(SOURCES_PATH, encoding="utf-8") as f:
        sources = json.load(f)
    with open(TOPICS_PATH, encoding="utf-8") as f:
        topics = {t["slug"]: "%02d-%s" % (t["number"], t["slug"]) for t in json.load(f)}

    selected = [s for s in sources if not args.only or s["id"] in args.only]
    log("Processing %d of %d sources" % (len(selected), len(sources)))
    for i, src in enumerate(selected, 1):
        epmc, oalex, xref, _, is_oa = enrich(src)
        if not args.no_download:
            local_files, open_copies, status = download(
                src, topics[src["topics"][0]], is_oa, epmc, oalex, xref, args.force
            )
            src["local_files"] = local_files
            src["open_licence_copies"] = open_copies
            src["fetch_status"] = status
        src["fetched_at"] = datetime.date.today().isoformat()
        log("[%d/%d] %s: %s" % (i, len(selected), src["id"], src.get("fetch_status", "metadata")))
        if i % 10 == 0:
            write_sources(sources)
    write_sources(sources)

    build = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_index.py")
    subprocess.run([sys.executable, build], check=True)

    counts = {}
    for s in selected:
        key = (s.get("fetch_status") or "metadata").split(";")[0]
        counts[key] = counts.get(key, 0) + 1
    log("Summary: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    warnings = [s for s in selected if s.get("metadata_warning")]
    if warnings:
        log("%d sources need a metadata check (field metadata_warning):" % len(warnings))
        for s in warnings:
            log("  %s: %s" % (s["id"], s["metadata_warning"]))


def write_sources(sources):
    tmp = SOURCES_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(sources, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, SOURCES_PATH)


if __name__ == "__main__":
    main()
