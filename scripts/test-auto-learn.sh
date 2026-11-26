#!/usr/bin/env bash
# Builds and runs the Auto-Learn logic tests without launching the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AL="$ROOT/VoiceInk/Features/Dictionary/AutoLearn"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O -o "$OUT/auto-learn-tests" \
    "$ROOT/Tests/AutoLearn/Stubs.swift" \
    "$ROOT/Tests/AutoLearn/main.swift" \
    "$AL/AutoLearnTypes.swift" \
    "$AL/CorrectionDiffEngine.swift" \
    "$AL/FinalSnapshotDiffEngine.swift" \
    "$AL/AutoLearnLocalReviewer.swift" \
    "$AL/AutoLearnFieldSampler.swift" \
    "$ROOT/VoiceInk/Features/Dictionary/Workflows/WordReplacementVariants.swift"

"$OUT/auto-learn-tests"
