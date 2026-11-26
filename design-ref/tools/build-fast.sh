#!/bin/bash
# Incremental version of `make local`: same xcodebuild settings, but keeps .local-build between
# runs instead of wiping it, so only changed files recompile.
#
#   build-fast.sh            build only (the running app is untouched)
#   build-fast.sh --install  also quit VoiceInk, replace /Applications/VoiceInk.app, and relaunch it
#                            (override the target with INSTALL_PATH=/some/where/VoiceInk.app)
set -euo pipefail
cd "$(dirname "$0")/../.."

# Same identity choice as the Makefile: LOCAL_CODESIGN_IDENTITY, else the Apple Development
# identity if there is exactly one, else ad-hoc ("-", permissions reset on every rebuild).
ID="${LOCAL_CODESIGN_IDENTITY:-}"
if [ -z "$ID" ]; then
    IDS=$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $2 }')
    [ "$(printf '%s\n' "$IDS" | awk 'NF' | wc -l | tr -d ' ')" = "1" ] && ID="$IDS"
fi
if [ -n "$ID" ] && [ "$ID" != "-" ]; then REQUIRED=YES; else ID="-"; REQUIRED=NO; fi

START=$(date +%s)
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
    -derivedDataPath "$PWD/.local-build" \
    -xcconfig LocalBuild.xcconfig \
    CODE_SIGN_IDENTITY="$ID" CODE_SIGNING_REQUIRED="$REQUIRED" CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    -skipPackagePluginValidation -skipMacroValidation \
    -quiet build
echo "build: $(( $(date +%s) - START ))s, signed with: $ID"

if [ "${1:-}" = "--install" ]; then
    osascript -e 'tell application id "com.prakashjoshipax.VoiceInk" to quit' >/dev/null 2>&1 || true
    sleep 1
    TARGET="${INSTALL_PATH:-/Applications/VoiceInk.app}"
    rm -rf "$TARGET"
    ditto ".local-build/Build/Products/Release/VoiceInk.app" "$TARGET"
    xattr -cr "$TARGET"
    open "$TARGET"
    echo "installed and relaunched $TARGET"
fi
