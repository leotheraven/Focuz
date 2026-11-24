#!/usr/bin/env python3
"""Advance the app and Live Activity versions together for each release."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("version", nargs="?", help="New version, e.g. 2.3 (default: next minor)")
parser.add_argument("--dry-run", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
project = root / "MamHabit.xcodeproj/project.pbxproj"
source = project.read_text()
versions = re.findall(r"MARKETING_VERSION = ([\d.]+);", source)
builds = re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", source)
if len(versions) != 4 or len(set(versions)) != 1 or len(builds) != 4 or len(set(builds)) != 1:
    parser.error("App and extension versions must match in all four configurations")
current = tuple(map(int, versions[0].split(".")))
version = args.version or f"{current[0]}.{current[1] + 1}"
if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version) or tuple(map(int, version.split("."))) <= current:
    parser.error("Choose a version newer than " + versions[0])
build = str(int(builds[0]) + 1)
updated = re.sub(r"MARKETING_VERSION = [\d.]+;", f"MARKETING_VERSION = {version};", source)
updated = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", f"CURRENT_PROJECT_VERSION = {build};", updated)
if not args.dry_run:
    project.write_text(updated)
    readme = root / "README.md"
    readme.write_text(re.sub(r"\A# Focuz [\d.]+", f"# Focuz {version}", readme.read_text()))
print(f"{'Next' if args.dry_run else 'Updated'}: Focuz {version} ({build}), app + Live Activity")
