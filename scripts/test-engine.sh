#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build/module-cache"
swiftc -module-cache-path "$PROJECT_DIR/build/module-cache" "$PROJECT_DIR/MamHabit/Localization.swift" "$PROJECT_DIR/MamHabit/HabitEngine.swift" "$PROJECT_DIR/Tests/EngineTests.swift" -o "$PROJECT_DIR/build/engine-tests"
"$PROJECT_DIR/build/engine-tests"
