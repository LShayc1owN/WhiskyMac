"""Collect a full macOS test run and optionally check the two-runtime coverage gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile


MINIMUM = 95
ROOT = Path(__file__).resolve().parents[1]


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def inputs_digest():
    digest = hashlib.sha256()
    paths = [Path("Package.swift")]
    for directory in ("Sources", "Tests"):
        paths.extend(sorted(p for p in Path(directory).rglob("*") if p.is_file() and p.name != ".DS_Store"))
    for path in paths:
        digest.update(str(path).encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def line_counts(binary, profile, exclusions):
    raw = output("xcrun", "llvm-cov", "export", "-summary-only", binary,
                 "-instr-profile", profile, "-ignore-filename-regex=" + exclusions)
    result = {}
    for item in json.loads(raw)["data"][0]["files"]:
        source = item["filename"].split("/Sources/Whisk/", 1)
        if len(source) != 2 or source[1] in result:
            raise ValueError("Unexpected coverage source: " + item["filename"])
        lines = item["summary"]["lines"]
        result[source[1]] = [lines["covered"], lines["count"]]
    if not result:
        raise ValueError("No application source lines found")
    return result


def check_pair(peer_path, manifest, profile, binary, exclusions, work):
    with zipfile.ZipFile(peer_path) as archive:
        peer = json.loads(archive.read("manifest.json"))
        if "lines" not in peer or not peer.get("tests_passed") or {peer["os"].split(".")[0], manifest["os"].split(".")[0]} != {"15", "26"}:
            raise ValueError("The gate requires passing full runs on both macOS 15 and 26")
        for field in ("revision", "inputs", "xcode", "swift"):
            if peer[field] != manifest[field]:
                raise ValueError("Coverage inputs differ: " + field)
        other_profile = work / "peer.profdata"
        other_profile.write_bytes(archive.read("default.profdata"))
    # Swift prefixes some private counter names with the absolute checkout path,
    # even with -coverage-prefix-map. Translate that prefix before merging.
    peer_text = work / "peer.txt"
    subprocess.run(["xcrun", "llvm-profdata", "merge", "--text", other_profile, "-o", peer_text], check=True)
    old = os.fsencode(peer["root"]) + b"/Sources/Whisk/"
    new = os.fsencode(manifest["root"]) + b"/Sources/Whisk/"
    peer_text.write_bytes(b"".join(new + line[len(old):] if line.startswith(old) else line
                                  for line in peer_text.read_bytes().splitlines(keepends=True)))
    subprocess.run(["xcrun", "llvm-profdata", "merge", peer_text, "-o", other_profile], check=True)
    # Check that this binary interprets the other machine's counters exactly
    # as its own binary did, even when the checkout paths differ.
    if line_counts(binary, other_profile, exclusions) != peer["lines"]:
        raise ValueError("Peer profile does not reproduce its original per-file coverage with this binary")
    merged = work / "merged.profdata"
    subprocess.run(["xcrun", "llvm-profdata", "merge", profile, other_profile, "-o", merged], check=True)
    combined = line_counts(binary, merged, exclusions)
    if combined.keys() != manifest["lines"].keys() or combined.keys() != peer["lines"].keys():
        raise ValueError("Coverage source sets differ")
    for path, (hit, total) in combined.items():
        a, b = manifest["lines"][path], peer["lines"][path]
        if total != a[1] or total != b[1] or not max(a[0], b[0]) <= hit <= total:
            raise ValueError("Incompatible line counts for " + path)
    covered = sum(pair[0] for pair in combined.values())
    total = sum(pair[1] for pair in combined.values())
    print(f"Combined coverage: {covered}/{total} ({100 * covered / total:.2f}%), minimum {MINIMUM}%")
    return dict(covered=covered, total=total, minimum=MINIMUM, passed=covered * 100 >= total * MINIMUM,
                per_file=combined)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("peer", nargs="?", type=Path, help="coverage ZIP from the other macOS version")
    peer = parser.parse_args().peer
    peer = peer.resolve() if peer else None
    os.chdir(ROOT)
    version = output("sw_vers", "-productVersion")
    major = version.split(".")[0]
    if major not in ("15", "26"):
        parser.error("Collect acceptance results on macOS 15 or 26")
    stamp = Path("COVERAGE_REVISION")
    revision = stamp.read_text().strip() if stamp.is_file() else output("git", "rev-parse", "HEAD")
    manifest = dict(revision=revision, root=str(ROOT), os=version, arch=platform.machine(), xcode=output("xcodebuild", "-version"),
                    swift=output("xcrun", "swiftc", "-version").splitlines()[0], inputs=inputs_digest())
    destination = ROOT / f"coverage-macos-{major}.zip"
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        env = dict(os.environ, COVERAGE_MIN="", WHISK_COVERAGE_OUTPUT=str(work))
        log = work / "tests.log"
        print(f"Running the full suite on macOS {version} at {revision}. Log: {log}", flush=True)
        with log.open("wb") as stream:
            command = ["bash", "scripts/coverage.sh", "--disable-sandbox", "--no-parallel",
                       "-Xswiftc", "-coverage-prefix-map", "-Xswiftc", f"{ROOT}=/WhiskyMac"]
            status = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, env=env).returncode
        manifest["tests_passed"] = status == 0
        with zipfile.ZipFile(work / "result.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(log, "tests.log")
            if not status:
                try:
                    if manifest["inputs"] != inputs_digest():
                        raise ValueError("Test inputs changed during this run")
                    paths = (work / "paths.txt").read_text().splitlines()
                    binary, profile, exclusions = paths
                    manifest["lines"] = line_counts(binary, profile, exclusions)
                    archive.write(profile, "default.profdata")
                    if peer:
                        combined = check_pair(peer, manifest, profile, binary, exclusions, work)
                        archive.writestr("combined.json", json.dumps(combined))
                        status = 0 if combined["passed"] else 1
                except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
                    manifest["error"] = str(error)
                    print(error, file=sys.stderr)
                    status = 1
            archive.writestr("manifest.json", json.dumps(manifest, indent=2))
        # Replace the previous packet only after the ZIP has finished writing.
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as staged:
            with (work / "result.zip").open("rb") as source:
                shutil.copyfileobj(source, staged)
        os.replace(staged.name, destination)
        print(f"Test result: {'passed' if manifest['tests_passed'] else 'failed'}. Return {destination}", flush=True)
        return status


if __name__ == "__main__":
    sys.exit(main())
