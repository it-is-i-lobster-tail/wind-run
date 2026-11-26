"""Build and run the annual study's rules lane as a linked iOS simulator executable."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import textwrap


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BENCHMARK = REPO / "WindRunTests/WorkoutSearchBenchmarkTests.swift"
ROUTES = REPO / "WindRunTests/SyntheticSearchRoute.swift"
TEMPLATE = HERE / "FastReplay.swift.in"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_driver():
    source = BENCHMARK.read_text()
    template = TEMPLATE.read_text()
    # Copy the actual app-hosted fixture projection, clock, search invocation and output
    # encoding. Failing a marker check forces a review if that reference flow changes.
    sections = {
        "FIXTURE_TYPES_AND_SEED": ("    struct Corpus:", "    private func corpus("),
        "SLOT_ENCODING_AND_CLOCK": ("    @MainActor\n    private func slots(", "    @MainActor\n    func testSyntheticSearch("),
        "SETUP_HISTORY_AND_CALENDAR": ("        let store = WindRunStore(inMemory: true)", "        let lanes ="),
        "SELECT_AS_OF": ("                var history = try XCTUnwrap(histories", "                if pass == 0 && lanes.contains"),
        "RULES_OBSERVATION": ("                let start = ContinuousClock.now\n                let rule =", '                for lane in ["toolHybrid"'),
    }
    for marker, (start, end) in sections.items():
        if source.count(start) != 1 or template.count(f"__{marker}__") != 1:
            raise ValueError(f"Review benchmark source and driver template for {marker}")
        first = source.index(start)
        last = source.index(end, first)
        part = source[first:last].rstrip()
        if marker in ("SELECT_AS_OF", "RULES_OBSERVATION"):
            part = textwrap.indent(textwrap.dedent(part), " " * 12)
        template = template.replace(f"__{marker}__", part)
    return template


def app_product(configuration):
    products = configuration.resolve(strict=True).parent / "Debug-iphonesimulator"
    return products, products / "WindRun.app/WindRun.debug.dylib"


def build(configuration, driver_dir):
    products, app = app_product(configuration)
    version_info = subprocess.check_output(["xcrun", "vtool", "-show-build", str(app)], text=True)
    if "IOSSIMULATOR" not in version_info:
        raise ValueError("Choose an iOS Simulator Debug build of Wind Run")
    deployment = re.search(r"\bminos\s+(\d+(?:\.\d+)*)", version_info).group(1)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    driver_dir.mkdir(exist_ok=True, parents=True)
    swift = driver_dir / "FastReplay.swift"
    swift.write_text(render_driver())
    destination = driver_dir / "fast-replay"
    temporary = destination.with_suffix(".new")
    initial_hash = sha256(app)
    command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-parse-as-library",
               "-target", f"arm64-apple-ios{deployment}-simulator", "-default-isolation", "MainActor",
               "-sdk", sdk, "-module-cache-path", str(driver_dir / "cache"), "-I", str(products)]
    # A build-for-testing usually has this explicit module map. Without it swiftc creates
    # its own cache. Derive the Clang ABI from the selected SDK to match Xcode's PCMs.
    objects = products.parents[1] / "Intermediates.noindex/WindRun.build/Debug-iphonesimulator/WindRunTests.build/Objects-normal/arm64"
    module_map = objects / "WindRunTests-dependencies-1.json"
    if module_map.is_file():
        sdk_version = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
        command += ["-Xfrontend", "-clang-target", "-Xfrontend", f"arm64-apple-ios{sdk_version}-simulator",
                    "-Xfrontend", "-disable-implicit-swift-modules", "-Xfrontend", "-explicit-swift-module-map-file",
                    "-Xfrontend", str(module_map), "-Xcc", "-fno-implicit-modules", "-Xcc", "-fno-implicit-module-maps"]
    command += ["-Xlinker", "-rpath", "-Xlinker", str(app.parent), str(swift), str(ROUTES),
                str(app), "-o", str(temporary)]
    subprocess.run(command, check=True)
    if sha256(app) != initial_hash:
        raise ValueError("The app was rebuilt while linking. Rerun the driver build.")
    temporary.replace(destination)
    receipt = {"appSHA256": initial_hash, "driverSHA256": sha256(destination),
               "benchmarkSHA256": sha256(BENCHMARK), "profileSHA256": sha256(ROUTES),
               "sourceSHA256": sha256(swift), "products": str(products)}
    (driver_dir / "build-receipt.json").write_text(json.dumps(receipt, indent=2))
    return receipt


def execute_cases(driver_dir, data, attempt, configuration, simulator, lanes, repeats, manifest):
    if lanes != ["rules"] or repeats:
        raise ValueError("The annual simulator driver supports a single rules pass")
    products, app = app_product(configuration)
    binary = driver_dir / "fast-replay"
    build_info = json.loads((driver_dir / "build-receipt.json").read_text())
    expected_hash = sha256(app)
    if (expected_hash != manifest["binarySHA256"] or expected_hash != build_info["appSHA256"]
            or str(products) != build_info["products"] or sha256(binary) != build_info["driverSHA256"]
            or sha256(BENCHMARK) != build_info["benchmarkSHA256"] or sha256(ROUTES) != build_info["profileSHA256"]):
        raise ValueError("Driver receipt differs from current app or benchmark. Rebuild the driver.")
    attempt = attempt.resolve()
    inputs = attempt / "input.json"
    inputs.write_text(json.dumps(data, separators=(",", ":")))
    destination = attempt / "observations.json"
    subprocess.run(["xcrun", "simctl", "spawn", simulator, str(binary), str(inputs), str(destination), simulator],
                   check=True, timeout=240)
    payload = json.loads(destination.read_text())
    observed = [row["queryID"] for row in payload["observations"]]
    if (payload["simulatorID"] != simulator or payload["appSHA256"] != expected_hash
            or observed != [query["id"] for query in data["queries"]]):
        raise ValueError("Simulator, loaded app binary, or returned query IDs differ from the replay request")
    details = {**manifest, **build_info, "simulatorID": simulator, "hardware": payload["hardware"],
               "os": payload["os"], "method": "linked iOS simulator executable"}
    (attempt / "manifest.json").write_text(json.dumps(details, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    compile_driver = commands.add_parser("build", help="Link to the app from a Debug build-for-testing")
    compile_driver.add_argument("--configuration", required=True, type=Path, help="Wind Run .xctestrun file")
    replay = commands.add_parser("replay", add_help=False, help="Run year_study.py on booted assigned simulators")
    for command in (compile_driver, replay):
        command.add_argument("--driver-dir", required=True, type=Path)
    args, forwarded = parser.parse_known_args()
    driver_dir = args.driver_dir.resolve()
    if args.action == "build":
        if forwarded:
            parser.error("Unexpected build arguments: " + " ".join(forwarded))
        print(json.dumps(build(args.configuration, driver_dir), indent=2))
        return

    # Use the same annual input preparation, runner assignment, resume and answer writing
    # as the XCTest path. Only the function executing one prepared case set changes.
    from functools import partial
    sys.path.insert(0, str(HERE.parent))
    import year_study
    year_study.execute_cases = partial(execute_cases, driver_dir)
    sys.argv[1:] = forwarded
    year_study.main()


if __name__ == "__main__":
    main()
