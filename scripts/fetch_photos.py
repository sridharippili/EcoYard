#!/usr/bin/env python3
"""Fetches one openly licensed photo per species from Wikimedia.

Why a script and not hand-picked files: every photo must carry a licence and
an author we can prove, and that has to be repeatable when the content grows.

How it works, per species:
  1. English Wikipedia's lead image for the article (editors choose it to
     represent the species, so it is rarely a map or a herbarium sheet),
  2. that file's licence and author from Commons,
  3. refuse anything that is not public domain or CC0/CC-BY/CC-BY-SA,
  4. download a ~900 px JPEG and record the credit.

Writes the images into app/assets/photos/ and the credits into
content/photo_credits.json. Nothing is invented: every field comes from the
API response.

Usage:  python3 scripts/fetch_photos.py [--check]
        --check re-reads the manifest and verifies each file is present.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "app", "assets", "photos")
MANIFEST = os.path.join(ROOT, "content", "photo_credits.json")
UA = "EcoYardDev/0.1 (habitat app, non-commercial development; Wikimedia API)"

# Licences we may ship. Anything else is refused rather than guessed at.
ALLOWED = (
    "cc0",
    "cc by",
    "cc by-sa",
    "public domain",
    "pd",
)


def _open(url, timeout=60):
    """Fetches a URL, waiting and retrying when Wikimedia rate-limits us."""
    delay = 2.0
    for attempt in range(6):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            return urllib.request.urlopen(req, timeout=timeout).read()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503) or attempt == 5:
                raise
            wait = float(e.headers.get("Retry-After") or delay)
            print(f"    rate limited, waiting {wait:.0f}s")
            time.sleep(wait)
            delay *= 2
    raise RuntimeError("unreachable")


def get(url):
    return json.loads(_open(url))


def strip_html(text):
    """The API returns HTML in Artist; keep the visible text only."""
    out, depth = [], 0
    for ch in text:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return " ".join("".join(out).split())


def lead_image(scientific_name):
    """The file name of the Wikipedia article's lead image, or None."""
    q = urllib.parse.urlencode(
        {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "pageimages",
            "piprop": "name",
            "titles": scientific_name,
            "redirects": "1",
        }
    )
    data = get("https://en.wikipedia.org/w/api.php?" + q)
    pages = data.get("query", {}).get("pages", [])
    if not pages:
        return None
    return pages[0].get("pageimage")


def commons_info(file_name, width=900):
    q = urllib.parse.urlencode(
        {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "imageinfo",
            "iiprop": "url|extmetadata|mime",
            "iiurlwidth": str(width),
            "titles": "File:" + file_name,
        }
    )
    data = get("https://commons.wikimedia.org/w/api.php?" + q)
    pages = data.get("query", {}).get("pages", [])
    if not pages or "imageinfo" not in pages[0]:
        return None
    info = pages[0]["imageinfo"][0]
    meta = info.get("extmetadata", {})

    def field(key):
        return meta.get(key, {}).get("value", "")

    return {
        "file": file_name,
        "thumb": info.get("thumburl"),
        "mime": info.get("mime", ""),
        "licence": strip_html(field("LicenseShortName")),
        "licenceUrl": field("LicenseUrl"),
        "author": strip_html(field("Artist")),
        "credit": strip_html(field("Credit")),
        "descriptionUrl": info.get("descriptionurl", ""),
    }


def licence_ok(licence):
    low = licence.lower()
    if "nc" in low.split() or "non-commercial" in low or "nd" in low.split():
        return False
    return any(low.startswith(a) for a in ALLOWED)


def fetch(kind, species, existing):
    """species: list of (id, scientific name). Returns manifest entries."""
    entries = []
    for ident, sci in species:
        try:
            # Resume: a photo already fetched and credited is left alone.
            done = existing.get((kind, ident))
            if done and os.path.exists(
                os.path.join(ROOT, "app", done["asset"])
            ):
                entries.append(done)
                print(f"  have {ident}")
                continue
            file_name = lead_image(sci)
            if not file_name:
                print(f"  SKIP {ident}: no lead image for {sci}")
                continue
            info = commons_info(file_name)
            if not info or not info["thumb"]:
                print(f"  SKIP {ident}: no Commons info for {file_name}")
                continue
            if not licence_ok(info["licence"]):
                print(f"  SKIP {ident}: licence '{info['licence']}' not allowed")
                continue
            if not info["mime"].startswith("image/"):
                print(f"  SKIP {ident}: not an image ({info['mime']})")
                continue

            out_name = f"{kind}-{ident}.jpg"
            out_path = os.path.join(OUT_DIR, out_name)
            data = _open(info["thumb"], timeout=120)
            with open(out_path, "wb") as f:
                f.write(data)

            entries.append(
                {
                    "id": ident,
                    "kind": kind,
                    "asset": f"assets/photos/{out_name}",
                    "bytes": len(data),
                    "author": info["author"] or "Unknown",
                    "licence": info["licence"],
                    "licenceUrl": info["licenceUrl"],
                    "sourceUrl": info["descriptionUrl"],
                }
            )
            print(
                f"  ok  {ident}: {len(data)//1024} KB, "
                f"{info['licence']}, {info['author'][:40]}"
            )
            time.sleep(1.5)  # be polite to the API
        except Exception as e:  # noqa: BLE001 - report and carry on
            print(f"  FAIL {ident}: {e}")
    return entries


def main():
    plants = json.load(open(os.path.join(ROOT, "content", "plants.json")))
    birds = json.load(open(os.path.join(ROOT, "content", "birds.json")))

    if "--check" in sys.argv:
        manifest = json.load(open(MANIFEST))
        missing = [
            p["asset"]
            for p in manifest["photos"]
            if not os.path.exists(os.path.join(ROOT, "app", p["asset"]))
        ]
        print("missing:", missing or "none")
        return 1 if missing else 0

    os.makedirs(OUT_DIR, exist_ok=True)
    existing = {}
    if os.path.exists(MANIFEST):
        for e in json.load(open(MANIFEST)).get("photos", []):
            existing[(e["kind"], e["id"])] = e

    print("plants:")
    entries = fetch(
        "plant",
        [(p["id"], p["scientificName"]) for p in plants["plants"]],
        existing,
    )
    print("birds:")
    entries += fetch(
        "bird",
        [(b["id"], b["scientificName"]) for b in birds["birds"]],
        existing,
    )

    manifest = {
        "schemaVersion": 1,
        "reviewStatus": "draft",
        "region": "us-ne",
        "note": (
            "Photos fetched by scripts/fetch_photos.py from Wikimedia "
            "Commons (the English Wikipedia lead image for each species). "
            "Every entry carries the licence and author reported by the "
            "Commons API. A person must check that each photo really shows "
            "the species before release."
        ),
        "sources": ["Wikimedia Commons", "English Wikipedia (lead images)"],
        "photos": sorted(entries, key=lambda e: (e["kind"], e["id"])),
    }
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    total = sum(e["bytes"] for e in entries)
    print(f"\n{len(entries)} photos, {total//1024} KB total -> {MANIFEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
