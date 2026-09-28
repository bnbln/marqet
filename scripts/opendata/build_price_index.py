#!/usr/bin/env python3
"""Builds bundled category names from Open Prices (docs/OFFENE-DATEN.md §3).

The builder uses price observations from DE, AT and CH to select useful categories and aliases.
Only category metadata is written into the app resource; no prices are bundled. At runtime the
app fetches current observations from the Open Prices API when a price surface is opened.

Sources (all ODbL – the output file is ODbL as well and must stay a separate file):
- prices.parquet from https://huggingface.co/datasets/openfoodfacts/open-prices (which
  locations are in DACH)
- /api/v1/prices of https://prices.openfoodfacts.org (prices with product and store embedded)
- categories.json from https://static.openfoodfacts.org/data/taxonomies/ (names DE/EN)

Usage:
    python3 -m venv .venv && .venv/bin/pip install -r scripts/opendata/requirements.txt
    .venv/bin/python scripts/opendata/build_price_index.py [--months 18] [--cache DIR]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import statistics
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Packages/MarqetKit/Sources/MarqetCore/Resources"
CATALOG = RESOURCES / "StoreCatalog.json"
OUTPUT = RESOURCES / "OpenPriceCategories.json"

USER_AGENT = "Marqet/0.1 (price index build; contact via App Store listing)"
PARQUET_URL = "https://huggingface.co/datasets/openfoodfacts/open-prices/resolve/main/prices.parquet"
TAXONOMY_URL = "https://static.openfoodfacts.org/data/taxonomies/categories.json"
PRICES_API = "https://prices.openfoodfacts.org/api/v1/prices"

COUNTRIES = ("DE", "AT", "CH")
CURRENCY = {"DE": "EUR", "AT": "EUR", "CH": "CHF"}
LOCATIONS_PER_REQUEST = 40
PAGE_SIZE = 100

# Too broad to say anything about the price of a list item.
SKIPPED_TAGS = {
    "en:plant-based-foods-and-beverages", "en:plant-based-foods", "en:beverages", "en:snacks",
    "en:sweet-snacks", "en:salty-snacks", "en:dairies", "en:groceries", "en:meals", "en:foods",
    "en:fermented-foods", "en:fermented-milk-products", "en:condiments", "en:sauces",
    "en:breakfasts", "en:desserts", "en:frozen-foods", "en:canned-foods", "en:non-food-products",
    "en:alcoholic-beverages", "en:non-alcoholic-beverages", "en:unsweetened-beverages",
    "en:cereals-and-potatoes", "en:cereals-and-their-products", "en:fruits-and-vegetables-based-foods",
    "en:meats-and-their-products", "en:seafood", "en:spreads", "en:sweet-spreads",
    "en:dietary-supplements", "en:farming-products", "en:dried-products", "en:cocoa-and-its-products",
    "en:confectioneries", "en:biscuits-and-cakes", "en:hot-beverages", "en:carbonated-drinks",
}

# Everyday words the taxonomy names differently (folded). Only used where the tag has prices.
MANUAL_ALIASES = {
    "en:chicken-eggs": ["eier", "eggs", "freilandeier", "bioeier"],
    "en:creams": ["sahne", "schlagsahne"],
    "en:lettuces": ["salat", "kopfsalat", "eisbergsalat"],
    "en:ground-coffees": ["kaffeepulver"],
    "en:toothpastes": ["zahnpasta", "zahncreme"],
    "en:toilet-papers": ["toilettenpapier", "klopapier"],
    "en:dishwashing-liquids": ["spuelmittel"],
    "en:laundry-detergents": ["waschmittel"],
    "en:whipping-creams": ["schlagsahne"],
}

# German plural endings; a plural name also answers to its singular ("Brote" → "brot").
PLURAL_ENDINGS = ("en", "n", "e", "s")


# MARK: - Download

def fetch(url: str, attempts: int = 4) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except Exception as error:  # noqa: BLE001 – network errors of every kind are retried
            if attempt == attempts - 1:
                raise
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s after {error}", file=sys.stderr)
            time.sleep(wait)
    raise AssertionError("unreachable")


def cached(cache: Path, name: str, url: str) -> Path:
    path = cache / name
    if not path.exists():
        print(f"Downloading {url}")
        path.write_bytes(fetch(url))
    return path


def dach_location_ids(parquet: Path) -> dict[str, list[int]]:
    table = pq.read_table(parquet, columns=["location_id", "location_osm_address_country_code"])
    ids: dict[str, set[int]] = defaultdict(set)
    for row in table.to_pylist():
        country = row["location_osm_address_country_code"]
        if country in COUNTRIES and row["location_id"] is not None:
            ids[country].add(row["location_id"])
    return {country: sorted(values) for country, values in ids.items()}


def fetch_prices(location_ids: list[int], since: dt.date, cache: Path) -> list[dict]:
    path = cache / f"prices-{since.isoformat()}-{len(location_ids)}.json"
    if path.exists():
        return json.loads(path.read_text())
    prices: list[dict] = []
    for start in range(0, len(location_ids), LOCATIONS_PER_REQUEST):
        chunk = ",".join(map(str, location_ids[start:start + LOCATIONS_PER_REQUEST]))
        page = 1
        while True:
            query = urllib.parse.urlencode({
                "location_id__in": chunk, "date__gte": since.isoformat(),
                "size": PAGE_SIZE, "page": page, "order_by": "id",
            })
            data = json.loads(fetch(f"{PRICES_API}?{query}"))
            prices.extend(data["items"])
            if page >= data.get("pages", 1):
                break
            page += 1
        print(f"  {min(start + LOCATIONS_PER_REQUEST, len(location_ids))}/{len(location_ids)} Orte, {len(prices)} Preise")
    path.write_text(json.dumps(prices))
    return prices


# MARK: - Normalization

def fold(text: str) -> str:
    """Same folding as ItemKeyNormalizer.fold in the app."""
    text = unicodedata.normalize("NFC", text).lower()
    for umlaut, replacement in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")):
        text = text.replace(umlaut, replacement)
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(c for c in decomposed if unicodedata.category(c) != "Mn")


def store_name_key(name: str) -> str:
    return "".join(c for c in fold(name) if c.isalnum())


def words(name: str) -> list[str]:
    return [w for w in "".join(c if c.isalnum() else " " for c in fold(name)).split() if w]


def catalog_matcher():
    """osm_brand → catalog key, like ChainRecognizer in the app: exact name, alias or map search
    term, otherwise the longest one leading the brand as whole words ("Netto City" → netto)."""
    catalog = json.loads(CATALOG.read_text())
    keys: dict[str, str] = {}
    prefixes: list[tuple[list[str], str]] = []
    for entry in catalog["stores"]:
        if entry["key"].startswith("generic-"):
            continue
        for name in [entry["name"], *entry.get("aliases", []), *(entry.get("mapSearchTerms") or [])]:
            keys.setdefault(store_name_key(name), entry["key"])
            if len(store_name_key(name)) >= 2:
                prefixes.append((words(name), entry["key"]))
    prefixes.sort(key=lambda p: -len("".join(p[0])))

    def match(brand: str | None) -> str | None:
        if not brand:
            return None
        if key := keys.get(store_name_key(brand)):
            return key
        brand_words = words(brand)
        return next((key for name_words, key in prefixes if brand_words[:len(name_words)] == name_words), None)

    return match


def unit_price(price: dict) -> tuple[str, float] | None:
    """Regular price per kg, l or piece; None if it cannot be compared."""
    value = price.get("price")
    if price.get("price_is_discounted"):
        value = price.get("price_without_discount")  # compare shelf prices, not promotions
    if value is None or value <= 0:
        return None
    if price.get("type") == "CATEGORY":
        per = price.get("price_per")
        if per == "KILOGRAM":
            return "kg", value
        if per == "UNIT":
            return "piece", value
        return None
    product = price.get("product") or {}
    quantity, unit = product.get("product_quantity"), (product.get("product_quantity_unit") or "").lower()
    if not quantity or quantity <= 0:
        return None
    factors = {"g": ("kg", 1000), "kg": ("kg", 1), "ml": ("l", 1000), "cl": ("l", 100), "l": ("l", 1)}
    if unit not in factors:
        return None
    base, factor = factors[unit]
    amount = quantity / factor
    # Portions below 20 g and bulk above 25 kg are almost always data errors.
    if not 0.02 <= amount <= 25:
        return None
    return base, value / amount


def category_tags(price: dict, taxonomy: dict) -> list[str]:
    if price.get("type") == "CATEGORY":
        tag = price.get("category_tag")
        return ancestors(tag, taxonomy) if tag else []
    tags = (price.get("product") or {}).get("categories_tags") or []
    return [tag for tag in tags if tag.startswith("en:")]


def entry_price(values: list[float]) -> float:
    """Typical entry price: the lower quartile. Categories mix budget and premium products, and
    "where is butter cheapest" asks for the budget end, without trusting a single outlier."""
    if len(values) < 4:
        return statistics.median(values)
    return statistics.quantiles(values, n=4, method="inclusive")[0]


def ancestors(tag: str, taxonomy: dict) -> list[str]:
    seen, stack = [], [tag]
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.append(current)
        stack.extend(taxonomy.get(current, {}).get("parents", []))
    return seen


def depth(tag: str, taxonomy: dict) -> int:
    return len(ancestors(tag, taxonomy)) - 1


# MARK: - Build

def build(months: int, cache: Path, min_count: int) -> dict:
    cache.mkdir(parents=True, exist_ok=True)
    since = dt.date.today() - dt.timedelta(days=months * 30)
    parquet = cached(cache, "prices.parquet", PARQUET_URL)
    taxonomy = json.loads(cached(cache, "categories.json", TAXONOMY_URL).read_text())
    to_catalog_key = catalog_matcher()

    ids_by_country = dach_location_ids(parquet)
    all_ids = sorted({i for ids in ids_by_country.values() for i in ids})
    print(f"DACH-Orte: { {c: len(v) for c, v in ids_by_country.items()} }")
    prices = fetch_prices(all_ids, since, cache)

    # (country, tag, unit, chain key) → unit prices, dates
    groups: dict[tuple[str, str, str, str], list[tuple[float, str]]] = defaultdict(list)
    brands: dict[str, str] = {}
    unmatched: dict[str, int] = defaultdict(int)
    for price in prices:
        location = price.get("location") or {}
        country = location.get("osm_address_country_code")
        if country not in COUNTRIES or price.get("currency") != CURRENCY[country]:
            continue
        if price.get("duplicate_of"):
            continue
        brand = location.get("osm_brand") or location.get("osm_name")
        chain = to_catalog_key(brand)
        if chain is None:
            unmatched[brand or "?"] += 1
            continue
        brands.setdefault(chain, brand)
        normalized = unit_price(price)
        if normalized is None:
            continue
        unit, value = normalized
        date = price.get("date") or price.get("created", "")[:10]
        for tag in category_tags(price, taxonomy):
            if tag in SKIPPED_TAGS:
                continue
            groups[(country, tag, unit, chain)].append((value, date))

    entries: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    used_tags: set[str] = set()
    for (country, tag, unit, chain), observations in groups.items():
        if len(observations) < min_count:
            continue
        values = sorted(v for v, _ in observations)
        entries[country][tag].append({
            "store": chain,
            "unit": unit,
            "typical": round(entry_price(values), 2),
            "median": round(statistics.median(values), 2),
            "low": round(min(values), 2),
            "high": round(max(values), 2),
            "count": len(values),
            "latest": max(d for _, d in observations),
        })
        used_tags.add(tag)

    categories = {}
    for tag in sorted(used_tags):
        names = taxonomy.get(tag, {}).get("name", {})
        localized = {lang: names[lang] for lang in ("de", "en") if lang in names}
        if not localized and tag not in MANUAL_ALIASES:
            continue
        aliases = set(MANUAL_ALIASES.get(tag, []))
        if "de" in localized and " " not in localized["de"]:
            name = fold(localized["de"])
            aliases.update(name[:-len(e)] for e in PLURAL_ENDINGS if name.endswith(e) and len(name) - len(e) >= 3)
        aliases -= {fold(n) for n in localized.values()}
        categories[tag] = {"names": localized, "depth": depth(tag, taxonomy)}
        if aliases:
            categories[tag]["aliases"] = sorted(aliases)

    prices_out = {
        country: {tag: sorted(rows, key=lambda r: (r["unit"], r["typical"]))
                  for tag, rows in sorted(by_tag.items()) if tag in categories}
        for country, by_tag in sorted(entries.items())
    }
    top_unmatched = sorted(unmatched.items(), key=lambda kv: -kv[1])[:15]
    print(f"Nicht im Katalog (Top 15): {top_unmatched}")
    return {
        "version": 1,
        "generated": dt.date.today().isoformat(),
        "since": since.isoformat(),
        "source": "Open Prices (prices.openfoodfacts.org), ODbL 1.0",
        "categories": categories,
        "prices": prices_out,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--months", type=int, default=18, help="Zeitfenster in Monaten (Standard 18)")
    parser.add_argument("--min-count", type=int, default=1, help="Mindestzahl Preise pro Kette und Kategorie")
    parser.add_argument("--cache", type=Path, default=ROOT / ".build/opendata", help="Zwischenspeicher für Downloads")
    args = parser.parse_args()

    index = build(args.months, args.cache, args.min_count)
    metadata = {key: index[key] for key in ("version", "generated", "source", "categories")}
    OUTPUT.write_text(json.dumps(metadata, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
    rows = sum(len(r) for by_tag in index["prices"].values() for r in by_tag.values())
    print(f"{OUTPUT.relative_to(ROOT)}: {len(index['categories'])} Kategorien, {rows} Preise nur bei der Erzeugung ausgewertet, "
          f"{OUTPUT.stat().st_size // 1024} KB ohne Preise in der App")


if __name__ == "__main__":
    main()
