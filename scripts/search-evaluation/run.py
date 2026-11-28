#!/usr/bin/env python3
"""Run synthetic queries through the real Wind Run test host; gold stays outside XCTest."""
import argparse
import base64
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import plistlib
import random
import shutil
import subprocess
import tempfile
import zlib

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
REGRESSIONS = ("WorkoutQueryTests", "WorkoutSearchEngineTests", "WorkoutSearchSessionTests")
TEST = "WindRunTests/WorkoutSearchBenchmarkTests/testSyntheticSearch"
SOURCE = [REPO / "WindRun/Features/Progress" / name for name in (
    "WorkoutSearchEngine.swift", "WorkoutIntentInterpreter.swift", "HistorySearchView.swift")]


def digest(files):
    value = hashlib.sha256()
    for path in files:
        value.update(path.name.encode() + b"\0" + path.read_bytes())
    return value.hexdigest()


def evaluator_fingerprint():
    return digest([HERE / "score.py", HERE / "corpus/v1-fingerprints.json"])


def is_regression_split(split):
    suites = json.loads((HERE / "corpus/v1-fingerprints.json").read_text())
    return suites[split].get("usage") == "regression"


def corpus_fingerprints(split, path):
    expected = json.loads((HERE / "corpus/v1-fingerprints.json").read_text())[split]
    actual = {key: hashlib.sha256(file.read_bytes()).hexdigest()
              for key, file in (("corpus", path), ("gold", path.parent / "gold.json"))}
    if any(value != expected[key] for key, value in actual.items()):
        raise SystemExit("Corpus/gold differs from the preregistered suite.")
    return actual


def regressions(bundle):
    tree = json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                               "--path", bundle]))
    def walked(node):
        yield node
        for child in node.get("children", []):
            yield from walked(child)
    nodes = [n for root in tree["testNodes"] for n in walked(root)]
    receipt = {}
    for suite in REGRESSIONS:
        cases = {n["nodeIdentifier"]: n.get("result") for n in nodes if n.get("nodeType") == "Test Case"
                 and n.get("nodeIdentifier", "").startswith(suite + "/")}
        if not cases or any(status != "Passed" for status in cases.values()):
            raise SystemExit(f"Missing or failed {suite} from this exact evaluation binary.")
        receipt[suite] = cases
    return receipt


def repeated_queries(queries):
    """Fixed 30-query development sample with coverage across scenario families."""
    groups = defaultdict(list)
    for query in queries:
        groups[query["family"]].append(query["id"])
    rng = random.Random(23057)
    for group in groups.values():
        group.sort()
        rng.shuffle(group)
    chosen = []
    while len(chosen) < min(len(queries), 30):
        for group in sorted(groups):
            if groups[group] and len(chosen) < 30:
                chosen.append(groups[group].pop())
    return chosen


def write_json(path, data):
    path.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Public or custodian-exported corpus.json")
    parser.add_argument("--output", required=True, type=Path, help="Fresh directory for results")
    parser.add_argument("--destination", required=True, help="iPhone simulator UDID")
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--lanes", default="legacy,rules,hybrid")
    parser.add_argument("--existing-build", action="store_true", help="Reuse xctestrun delivered by build-for-testing")
    parser.add_argument("--reuse-ci-build", action="store_true",
                        help="CI only: stamp the build-for-testing products this job just built from this checkout instead of rebuilding")
    parser.add_argument("--probe", action="store_true", help="Development-only production model generation preflight")
    parser.add_argument("--repeats", action="store_true", help="Repeat 30 development queries twice after the initial hybrid pass")
    parser.add_argument("--development-summary", type=Path, help="Passing development summary for a validation candidate")
    parser.add_argument("--custody-dir", type=Path, help="Single private evaluator-owned release ledger outside the repository")
    parser.add_argument("--freeze", type=Path, help="Validated freeze receipt from scoring, required on holdout")
    options = parser.parse_args()
    lanes = options.lanes.split(",")
    if len(set(lanes)) != len(lanes) or not set(lanes) <= {"legacy", "rules", "hybrid"}:
        parser.error("Select distinct legacy,rules,hybrid lanes.")
    dataset = json.loads(options.input.read_text())
    split = dataset["split"]
    if split not in {"development", "validation", "holdout"}:
        parser.error("Unknown corpus split.")
    if split == "validation" and is_regression_split(split) and "hybrid" in lanes:
        parser.error("V1 validation is now a regression suite. Use followup.py for a research comparison.")
    simulations = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    if not any(device["udid"] == options.destination for runtime, devices in simulations["devices"].items()
               if ".iOS-" in runtime for device in devices):
        parser.error("Select an available iOS simulator.")
    corpus_hashes = corpus_fingerprints(split, options.input)
    product_sources = sorted(p for folder in ("WindRun", "WindRunTests", "Shared") for p in (REPO / folder).rglob("*.swift"))
    fingerprint = digest(product_sources)
    receipt = None
    ledger = None
    if split != "development":
        if not options.custody_dir or options.custody_dir.resolve().is_relative_to(REPO):
            parser.error("Validation and holdout require an independent evaluator's private ledger outside the checkout.")
        ledger = options.custody_dir.resolve()
        ledger.mkdir(parents=True, mode=0o700, exist_ok=True)
        if split == "validation":
            development = json.loads(options.development_summary.read_text()) if options.development_summary else {}
            if (development.get("split") != "development" or development.get("fingerprint") != fingerprint
                    or development.get("evaluatorHash") != evaluator_fingerprint()):
                parser.error("This frozen candidate needs matching development results.")
            if set(lanes) == {"legacy", "rules", "hybrid"}:
                if not development.get("eligible"):
                    parser.error("Model validation requires passing development gates.")
            elif set(lanes) != {"legacy", "rules"}:
                parser.error("Use all three lanes for promotion, or legacy,rules for a deterministic audit.")
    if options.probe or options.repeats:
        if split != "development" or "hybrid" not in lanes:
            parser.error("Model preflight and repeated sampling require the development hybrid lane.")
    if split == "holdout":
        if not options.freeze or set(lanes) != {"legacy", "rules", "hybrid"}:
            parser.error("Blind evaluation requires all lanes and the validation freeze receipt.")
        receipt = json.loads(options.freeze.read_text())
        if not receipt.get("eligible") or receipt["fingerprint"] != fingerprint or receipt.get("evaluatorHash") != evaluator_fingerprint():
            parser.error("Candidate differs from the frozen, eligible candidate.")
    output = options.output.resolve()
    if split != "development" and output.is_relative_to(REPO):
        parser.error("The independent custodian must keep raw validation/holdout output outside the repository.")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    if options.probe:
        dataset["queries"] = [{"id": "generation-preflight", "historyID": dataset["histories"][0]["id"],
                               "family": "preflight", "text": "Which outings did I take on my bicycle before breakfast?"}]
        dataset["histories"] = dataset["histories"][:1]
    repeated = repeated_queries(dataset["queries"]) if options.repeats else []
    manifest = {
        "split": split, "lanes": lanes, "probe": options.probe, "repeatIDs": repeated, "fingerprint": fingerprint,
        "promptSourceHash": digest([SOURCE[1]]), "corpusHashes": corpus_hashes,
        "destination": options.destination, "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    }
    derived = options.derived_data.resolve()
    if options.existing_build and options.reuse_ci_build:
        parser.error("Use --existing-build or --reuse-ci-build, not both.")
    if not options.existing_build and not options.reuse_ci_build:
        subprocess.run(["xcodebuild", "-quiet", "-jobs", "3", "-project", "WindRun.xcodeproj",
                        "-scheme", "WindRun", "-destination", f"id={options.destination}",
                        "-derivedDataPath", str(derived), "build-for-testing"], cwd=REPO, check=True)
    product = derived / "Build/Products"
    configs = list(product.glob("WindRun_*.xctestrun"))
    if len(configs) != 1:
        raise SystemExit(f"Expected one WindRun xctestrun in {product}. Found {configs}")
    bundle = product / "Debug-iphonesimulator/WindRun.app"
    executable = bundle / "WindRun"
    test_binary = bundle / "PlugIns/WindRunTests.xctest/WindRunTests"
    binaries = [executable, test_binary, *bundle.glob("WindRun.debug.dylib")]
    binary_hash = digest(binaries)
    if fingerprint != digest(product_sources):
        raise SystemExit("Source changed during preparation. Rebuild with frozen sources.")
    provenance = derived / "search-evaluation-build.json"
    stamp = {"fingerprint": fingerprint, "binaryHash": binary_hash}
    if options.existing_build:
        if not provenance.exists() or json.loads(provenance.read_text()) != stamp:
            raise SystemExit("No matching build provenance. Re-run without --existing-build.")
    else:
        write_json(provenance, stamp)
    manifest.update(stamp)
    write_json(output / "manifest.json", manifest)
    if split == "validation":
        if development.get("binaryHash") != binary_hash:
            raise SystemExit("The submitted binary differs from its development results.")
        if (ledger / "blind-consumed").exists():
            raise SystemExit("Blind evaluation is closed for this corpus version.")
        # Reserve a slot before any validation result. Exclusive creation also handles concurrent jobs.
        slot_names = ([f"validation-{slot}.json" for slot in range(1, 4)] if "hybrid" in lanes
                      else ["rules-audit.json"])
        for name in slot_names:
            try:
                with (ledger / name).open("x") as entry:
                    json.dump(stamp, entry)
                break
            except FileExistsError:
                continue
        else:
            raise SystemExit("The release ledger has already spent the permitted evaluation slots.")
    if receipt is not None:
        if not any(json.loads(entry.read_text()) == stamp for entry in ledger.glob("validation-*.json")):
            raise SystemExit("No matching frozen candidate in the evaluator ledger.")
        if receipt.get("binaryHash") != binary_hash:
            raise SystemExit("Use the exact binary frozen in validation.")
        # Custodian keeps this single-use receipt outside the prompt development workspace.
        (ledger / "blind-consumed").open("x").close()
    execute_cases(dataset, output, configs[0], options.destination, lanes, repeated, manifest)


def execute_cases(dataset, output, configuration, destination, lanes, repeated, manifest):
    """Run an already-built host on supplied synthetic inputs; the host never receives gold."""
    config = plistlib.loads(configuration.read_bytes())
    if "TestConfigurations" in config:
        targets = [target for entry in config["TestConfigurations"] for target in entry["TestTargets"]]
    else:
        targets = [value for key, value in config.items() if key != "__xctestrun_metadata__"]
    target, = [t for t in targets if t.get("BlueprintName") == "WindRunTests"]
    raw = json.dumps(dataset, separators=(",", ":")).encode()
    compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
    zipped = compressor.compress(raw) + compressor.flush()
    target.setdefault("EnvironmentVariables", {}).update({
        "WR_SEARCH_CORPUS": base64.b64encode(zipped).decode(), "WR_SEARCH_SIZE": str(len(raw)),
        "WR_SEARCH_LANES": ",".join(lanes), "WR_SEARCH_REPEAT": ",".join(repeated),
        "TZ": dataset["timeZone"],
    })
    result_bundle = output / "evaluation.xcresult"
    # __TESTROOT__ resolves relative to the xctestrun location.
    with tempfile.NamedTemporaryFile(suffix=".xctestrun", dir=configuration.parent) as stream:
        plistlib.dump(config, stream)
        stream.flush()
        subprocess.run(["xcodebuild", "-quiet", "-xctestrun", stream.name,
                        "-destination", f"id={destination}", "-parallel-testing-enabled", "NO",
                        "-resultBundlePath", str(result_bundle), f"-only-testing:{TEST}",
                        *[f"-only-testing:WindRunTests/{suite}" for suite in REGRESSIONS],
                        "test-without-building"], check=True)
    manifest["regressions"] = regressions(result_bundle)
    write_json(output / "manifest.json", manifest)
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
                        "--test-id", "WorkoutSearchBenchmarkTests/testSyntheticSearch()", "--output-path", folder], check=True)
        attachments = json.loads((Path(folder) / "manifest.json").read_text())
        matches = [a for t in attachments for a in t["attachments"] if a["suggestedHumanReadableName"].startswith("SyntheticSearchResults")]
        if len(matches) != 1:
            raise SystemExit("Benchmark did not run, or its observations are missing.")
        shutil.copyfile(Path(folder) / matches[0]["exportedFileName"], output / "observations.json")
    payload = json.loads((output / "observations.json").read_text())
    expected = len(dataset["queries"]) * len(lanes) + 2 * len(repeated)
    if len(payload["observations"]) != expected:
        raise SystemExit(f"Expected {expected} observations, got {len(payload['observations'])}.")
    print(f"{output}: {expected} observations; model availability {payload['modelAvailability']}")


if __name__ == "__main__":
    main()
