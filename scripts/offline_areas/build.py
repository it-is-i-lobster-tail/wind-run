"""Build the offline US area pack that history search reads on the iPhone.

The pack is one SQLite file of named parks (about 1 hectare or more), neighborhoods, cities, states and
territories from Overture Maps. Outlines are simplified to about 20 m and stored as small integer
coordinates, so the whole file stays under 40 MB. It is never committed to git: CI uploads it as a
GitHub release asset and `fetch.sh` downloads it by checksum. Run with the pinned requirements.

    python scripts/offline_areas/build.py --output build/offline-areas
"""
import argparse
import datetime
import gzip
import hashlib
import json
import math
import re
import sqlite3
import tempfile
import uuid
from collections import Counter
from pathlib import Path

import pyarrow.parquet as pq
from pyarrow import fs
from shapely import STRtree, box, from_wkb, make_valid
from shapely.geometry import MultiPolygon, Polygon, shape

RELEASES = "overturemaps-us-west-2/release"
FILE_NAME = "USAreas.sqlite"
# Bumped when the file layout changes. The app refuses a pack with another format.
FORMAT = 2
CODES = {"US", "PR", "GU", "MP", "AS", "VI", "UM"}
TYPES = {"park": "park", "neighborhood": "neighborhood", "macrohood": "neighborhood",
         "microhood": "neighborhood", "locality": "city", "region": "state", "dependency": "territory"}
# About 20 m on the ground, in degrees of latitude.
SIMPLIFY_DEGREES = 20 / 111_320
# Coordinates are stored as whole steps of 1e-5 degrees, about 1 m.
SCALE = 100_000
MIN_PARK_SQUARE_METERS = 10_000
MAX_BYTES = 40 * 1024 * 1024


def parquet_files(s3, release):
    for theme, kind in [("base", "land_use"), ("divisions", "division_area")]:
        folder = f"{RELEASES}/{release}/theme={theme}/type={kind}"
        for item in sorted(s3.get_file_info(fs.FileSelector(folder)), key=lambda item: item.path):
            if item.path.endswith(".parquet"):
                yield kind, item.path


def square_meters(geometry):
    """Rough ground area: degrees scaled by the cosine of the middle latitude. Close enough for a 1 ha cutoff."""
    south, north = geometry.bounds[1], geometry.bounds[3]
    scale = math.cos(math.radians((south + north) / 2))
    return geometry.area * 111_320 * 111_320 * scale


def division_files(s3, release, kind):
    folder = f"{RELEASES}/{release}/theme=divisions/type={kind}"
    for item in sorted(s3.get_file_info(fs.FileSelector(folder)), key=lambda item: item.path):
        if item.path.endswith(".parquet"):
            yield item.path


def city_counties(s3, release, counties, outlined):
    """Counties that are really cities, as (key, name, region, wkb).

    San Francisco, Denver, Baltimore, St. Louis, Anchorage and the like are consolidated city-counties
    or independent cities. Overture gives their city a locality point but no outline of its own; the
    outline is the county of the same name in the same state. Ordinary counties carry a suffix in their
    name ("Marin County"), so they never match a city's name.
    """
    wanted = {(region, name) for _key, name, region, _wkb, _division in counties}
    points = {}
    for uri in division_files(s3, release, "division"):
        with s3.open_input_file(uri) as stream:
            file = pq.ParquetFile(stream)
            columns = ["id", "geometry", "names", "subtype", "country", "region"]
            for batch in file.iter_batches(columns=columns, batch_size=4096):
                for row in batch.to_pylist():
                    if row["subtype"] != "locality" or row["country"] not in CODES or row["id"] in outlined:
                        continue
                    key = (row["region"] or "", (row["names"] or {}).get("primary"))
                    if key in wanted:
                        points.setdefault(key, []).append(from_wkb(row["geometry"]))
    for key, name, region, wkb, _division in counties:
        cities = points.get((region, name))
        if cities and any(from_wkb(wkb).intersects(point) for point in cities):
            yield key, "city", name, region, wkb


def fetch_rows(s3, release):
    geometries = json.loads(gzip.decompress(Path(__file__).with_name("us-mask.json.gz").read_bytes()))
    pieces = []
    for data in geometries:
        g = shape(data)
        pieces.extend(g.geoms if g.geom_type == "MultiPolygon" else [g])
    mask = STRtree(pieces)
    counties = []
    outlined = set()
    for theme, uri in parquet_files(s3, release):
        columns = ["id", "geometry", "names.primary", "subtype"]
        if theme == "division_area":
            columns += ["country", "region", "is_land", "division_id"]
        with s3.open_input_file(uri) as stream:
            file = pq.ParquetFile(stream)
            schema = file.schema
            fields = {schema.column(i).path: i for i in range(len(schema))}
            for group in range(file.num_row_groups):
                metadata = file.metadata.row_group(group)
                stats = [metadata.column(fields["bbox." + axis]).statistics for axis in ("xmin", "ymin", "xmax", "ymax")]
                if all(stat and stat.has_min_max for stat in stats):
                    extent = box(stats[0].min, stats[1].min, stats[2].max, stats[3].max)
                    if not len(mask.query(extent)):
                        continue
                for batch in file.iter_batches(row_groups=[group], columns=columns, batch_size=256):
                    for row in batch.to_pylist():
                        subtype = row["subtype"]
                        if subtype == "county" and theme == "division_area":
                            if row["is_land"] and row["country"] in CODES and (row["names"] or {}).get("primary"):
                                if len(mask.query(from_wkb(row["geometry"]), predicate="intersects")):
                                    counties.append((uuid.UUID(row["id"]).bytes, row["names"]["primary"],
                                                     row["region"] or "", row["geometry"], row["division_id"]))
                            continue
                        if subtype == "locality" and theme == "division_area":
                            outlined.add(row["division_id"])
                        if subtype not in TYPES or (theme == "land_use") != (subtype == "park"):
                            continue
                        kind = TYPES[subtype]
                        region = ""
                        if kind in ("city", "state", "territory"):
                            if not row["is_land"] or row["country"] not in CODES:
                                continue
                            region = row["region"] or ""
                        name = (row["names"] or {}).get("primary")
                        if not name:
                            continue
                        g = from_wkb(row["geometry"])
                        if g.geom_type not in ("Polygon", "MultiPolygon"):
                            continue
                        if kind == "park" and square_meters(g) < MIN_PARK_SQUARE_METERS:
                            continue
                        if len(mask.query(g, predicate="intersects")):
                            yield uuid.UUID(row["id"]).bytes, kind, name, region, row["geometry"]
    yield from city_counties(s3, release, counties, outlined)


def simplified(wkb):
    """The outline at about 20 m, as a list of polygons, each a list of rings of (x, y) degree pairs."""
    g = from_wkb(wkb)
    small = g.simplify(SIMPLIFY_DEGREES, preserve_topology=True)
    if small.is_empty or not small.is_valid:
        small = make_valid(small)
    polygons = []
    parts = small.geoms if hasattr(small, "geoms") else [small]
    for part in parts:
        if isinstance(part, MultiPolygon):
            candidates = list(part.geoms)
        elif isinstance(part, Polygon):
            candidates = [part]
        else:
            continue
        for polygon in candidates:
            if polygon.is_empty:
                continue
            rings = [list(polygon.exterior.coords)]
            rings += [list(ring.coords) for ring in polygon.interiors if Polygon(ring).area > 0]
            polygons.append(rings)
    return polygons


def varint(value, out):
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return


def zigzag(value):
    return (value << 1) ^ (value >> 63)


def encode(polygons):
    """Polygons as varints: counts, then each ring's points as zigzag steps from the point before."""
    out = bytearray()
    varint(len(polygons), out)
    for rings in polygons:
        varint(len(rings), out)
        for ring in rings:
            points = []
            for x, y in ring:
                point = (round(x * SCALE), round(y * SCALE))
                if not points or points[-1] != point:
                    points.append(point)
            if points[0] != points[-1]:
                points.append(points[0])
            varint(len(points), out)
            px = py = 0
            for x, y in points:
                varint(zigzag(x - px), out)
                varint(zigzag(y - py), out)
                px, py = x, y
    return bytes(out)


def package(rows, release, output, built):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp)
        source = sqlite3.connect(stage / "input")
        source.execute("CREATE TABLE raw(id BLOB PRIMARY KEY, kind, name, region, geometry BLOB) WITHOUT ROWID")
        source.executemany("INSERT OR IGNORE INTO raw VALUES (?,?,?,?,?)", rows)
        source.commit()

        path = stage / FILE_NAME
        db = sqlite3.connect(path)
        db.executescript("""
            PRAGMA page_size=4096;
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE area(kind TEXT NOT NULL, name TEXT NOT NULL, region TEXT NOT NULL, geometry BLOB NOT NULL);
            CREATE VIRTUAL TABLE bounds USING rtree(rowid, west, east, south, north);
        """)
        counts = Counter()
        digest = hashlib.sha256()
        number = 0
        for _key, kind, name, region, wkb in source.execute("SELECT * FROM raw ORDER BY kind, id"):
            polygons = simplified(wkb)
            if not polygons:
                continue
            blob = encode(polygons)
            xs = [x for rings in polygons for x, _ in rings[0]]
            ys = [y for rings in polygons for _, y in rings[0]]
            number += 1
            db.execute("INSERT INTO area(rowid, kind, name, region, geometry) VALUES(?,?,?,?,?)",
                       (number, kind, name, region, blob))
            db.execute("INSERT INTO bounds VALUES(?,?,?,?,?)", (number, min(xs), max(xs), min(ys), max(ys)))
            counts[kind] += 1
            for field in (kind.encode(), name.encode(), region.encode(), blob):
                digest.update(len(field).to_bytes(8, "big"))
                digest.update(field)
        source.close()
        if not all(counts[k] for k in ("park", "neighborhood", "city", "state")):
            raise ValueError("Incomplete area layers")
        meta = {"format": str(FORMAT), "release": release, "built": built, "digest": digest.hexdigest(),
                "counts": json.dumps(counts, sort_keys=True)}
        db.executemany("INSERT INTO meta VALUES(?,?)", meta.items())
        db.commit()
        db.execute("VACUUM")
        if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise ValueError("Invalid area database")
        db.close()

        size = path.stat().st_size
        if size > MAX_BYTES:
            raise SystemExit(f"The area pack is {size / 1_048_576:.1f} MB, over the 40 MB limit")
        with path.open("rb") as file:
            sha256 = hashlib.file_digest(file, "sha256").hexdigest()
        (output / FILE_NAME).write_bytes(path.read_bytes())
        info = {"format": FORMAT, "release": release, "built": built, "digest": digest.hexdigest(),
                "sha256": sha256, "bytes": size, "counts": dict(sorted(counts.items()))}
        (output / "pack-info.json").write_text(json.dumps(info, indent=2) + "\n")
        print(json.dumps(info, indent=2))


def latest_release(s3):
    available = [item.base_name for item in s3.get_file_info(fs.FileSelector(RELEASES))
                 if item.type == fs.FileType.Directory and re.fullmatch(r"\d{4}-\d{2}-\d{2}\.\d+", item.base_name)]
    return max(available, key=lambda value: (value[:10], int(value.split(".")[1])))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", help="Monthly Overture release. Defaults to the latest one.")
    parser.add_argument("--output", type=Path, required=True, help="Folder for USAreas.sqlite and pack-info.json")
    args = parser.parse_args()
    s3 = fs.S3FileSystem(region="us-west-2", anonymous=True, connect_timeout=20, request_timeout=120)
    release = args.release or latest_release(s3)
    built = datetime.datetime.now(datetime.UTC).date().isoformat()
    package(fetch_rows(s3, release), release, args.output, built)
