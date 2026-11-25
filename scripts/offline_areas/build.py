"""Build full-resolution Overture US offline resources. Run with the pinned requirements."""
import argparse
import gzip
import hashlib
import shutil
import json
import sqlite3
import tempfile
import uuid
from collections import Counter
from pathlib import Path
import re

import pyarrow.parquet as pq
from pyarrow import fs
from shapely import STRtree, box, from_wkb
from shapely.geometry import shape

RELEASES = "overturemaps-us-west-2/release"
OUTPUT = Path(__file__).resolve().parents[2] / "WindRun/OfflineAreas/Resources"
CODES = {"US", "PR", "GU", "MP", "AS", "VI", "UM"}
TYPES = {"park": "park", "neighborhood": "neighborhood", "macrohood": "neighborhood",
         "microhood": "neighborhood", "locality": "city", "region": "state", "dependency": "territory"}


def parquet_files(s3, release):
    for theme, kind in [("base", "land_use"), ("divisions", "division_area")]:
        folder = f"{RELEASES}/{release}/theme={theme}/type={kind}"
        for item in sorted(s3.get_file_info(fs.FileSelector(folder)), key=lambda item: item.path):
            if item.path.endswith(".parquet"):
                yield kind, item.path


def fetch_rows(s3, release):
    geometries = json.loads(gzip.decompress(Path(__file__).with_name("us-mask.json.gz").read_bytes()))
    pieces = []
    for data in geometries:
        g = shape(data)
        pieces.extend(g.geoms if g.geom_type == "MultiPolygon" else [g])
    mask = STRtree(pieces)
    for theme, uri in parquet_files(s3, release):
        columns = ["id", "geometry", "names.primary", "subtype"]
        if theme == "division_area":
            columns += ["country", "region", "is_land"]
        with s3.open_input_file(uri) as stream:
            file = pq.ParquetFile(stream)
            schema = file.schema
            fields = {schema.column(i).path: i for i in range(len(schema))}
            for group in range(file.num_row_groups):
                metadata = file.metadata.row_group(group)
                stats = [metadata.column(fields["bbox." + axis]).statistics for axis in ("xmin","ymin","xmax","ymax")]
                if all(stat and stat.has_min_max for stat in stats):
                    extent = box(stats[0].min, stats[1].min, stats[2].max, stats[3].max)
                    if not len(mask.query(extent)):
                        continue
                for batch in file.iter_batches(row_groups=[group], columns=columns, batch_size=256):
                    for row in batch.to_pylist():
                        subtype = row["subtype"]
                        if subtype not in TYPES or (theme == "land_use") != (subtype == "park"):
                            continue
                        kind = TYPES[subtype]
                        region = ""
                        if kind in ("city", "state", "territory"):
                            if not row["is_land"] or row["country"] not in CODES:
                                continue
                            region = row["region"] or ""
                        name = (row["names"] or {}).get("primary")
                        if name:
                            g = from_wkb(row["geometry"])
                            if g.geom_type in ("Polygon", "MultiPolygon") and len(mask.query(g, predicate="intersects")):
                                yield uuid.UUID(row["id"]).bytes, kind, name, region, row["geometry"]



def package(rows, release, output):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp)
        source = sqlite3.connect(stage / "input")
        source.execute("CREATE TABLE raw(id BLOB PRIMARY KEY, kind, name, region, geometry BLOB) WITHOUT ROWID")
        source.executemany("INSERT OR IGNORE INTO raw VALUES (?,?,?,?,?)", rows)
        source.commit()
        counts = Counter()
        shards = []
        digest = hashlib.sha256()
        db = None

        def close_shard():
            db.commit()
            if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise ValueError("Invalid area database")
            db.close()

        for key, kind, name, region, wkb in source.execute("SELECT * FROM raw ORDER BY kind,id"):
            if db is None or (number % 256 == 0 and db.execute("PRAGMA page_count").fetchone()[0] * 4096 >= 32_000_000):
                if db is not None:
                    close_shard()
                filename = f"USAreas-{len(shards):02d}.sqlite"
                db = sqlite3.connect(stage / filename)
                db.executescript("""
                    PRAGMA page_size=4096;
                    CREATE TABLE area(id BLOB NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, region TEXT, geometry BLOB NOT NULL);
                    CREATE VIRTUAL TABLE bounds USING rtree(rowid,west,east,south,north);
                """)
                number = 0
                extent = [180., 90., -180., -90.]
                shards.append({"file": filename, "extent": extent})
            number += 1
            db.execute("INSERT INTO area VALUES(?,?,?,?,?)", (key,kind,name,region,wkb))
            west,south,east,north = from_wkb(wkb).bounds
            db.execute("INSERT INTO bounds VALUES(?,?,?,?,?)",(number,west,east,south,north))
            extent[:] = [min(extent[0],west),min(extent[1],south),max(extent[2],east),max(extent[3],north)]
            counts[kind] += 1
            for field in (key, kind.encode(), name.encode(), region.encode(), wkb):
                digest.update(len(field).to_bytes(8, "big"))
                digest.update(field)
        if db is None or not all(counts[k] for k in ("park","neighborhood","city","state")):
            raise ValueError("Incomplete area layers")
        close_shard()
        source.close()
        for shard in shards:
            with (stage / shard["file"]).open("rb") as file:
                shard["sha256"] = hashlib.file_digest(file, "sha256").hexdigest()
        manifest = {"format": 1, "release": release, "digest": digest.hexdigest(), "counts": counts, "shards": shards}
        (stage/"USAreas.json").write_text(json.dumps(manifest, indent=2, sort_keys=True)+"\n")
        for old in output.glob("USAreas-*.sqlite"):
            if not (stage/old.name).exists():
                old.unlink()
        for path in [*(stage.glob("USAreas-*.sqlite")), stage/"USAreas.json"]:
            shutil.copyfile(path, output/path.name)
        print(dict(counts), digest.hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", help="Monthly Overture release. Defaults to the catalog's latest release.")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    release = args.release
    s3 = fs.S3FileSystem(region="us-west-2", anonymous=True, connect_timeout=20, request_timeout=120)
    if not release:
        available = [item.base_name for item in s3.get_file_info(fs.FileSelector(RELEASES))
                     if item.type == fs.FileType.Directory and re.fullmatch(r"\d{4}-\d{2}-\d{2}\.\d+", item.base_name)]
        release = max(available, key=lambda value: (value[:10], int(value.split(".")[1])))
    package(fetch_rows(s3, release), release, args.output)
