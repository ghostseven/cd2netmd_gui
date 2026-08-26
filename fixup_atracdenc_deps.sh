#!/bin/bash
# fixup_atracdenc_deps.sh
#
# Copies atracdenc's Homebrew-linked .dylib dependencies into the app
# bundle's Frameworks dir, and rewrites every load command (both on
# atracdenc itself and on the dylibs' cross-references to each other)
# to be relative to @executable_path, so the finished .app doesn't
# require Homebrew to be installed on the end user's machine.
#
# Usage: ./fixup_atracdenc_deps.sh <path-to-.app>
set -euo pipefail

APP_BUNDLE="$1"
BINARY="${APP_BUNDLE}/Contents/MacOS/atracdenc"
FRAMEWORKS="${APP_BUNDLE}/Contents/Frameworks"

if [[ ! -f "${BINARY}" ]]; then
    echo "error: ${BINARY} not found. Copy atracdenc into MacOS/ before running this." >&2
    exit 1
fi

mkdir -p "${FRAMEWORKS}"

# Collect the full transitive dylib closure by walking otool -L output
# repeatedly until no new /opt/homebrew/ dependencies show up.
collect_deps() {
    local bin="$1"
    otool -L "$bin" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep '^/opt/homebrew/'
}

SEEN=""
QUEUE=("${BINARY}")
DYLIBS=()

is_seen() {
    case "${SEEN}" in
        *"|$1|"*) return 0 ;;
        *) return 1 ;;
    esac
}

while [[ ${#QUEUE[@]} -gt 0 ]]; do
    current="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if ! is_seen "$dep"; then
            SEEN="${SEEN}|${dep}|"
            DYLIBS+=("$dep")
            QUEUE+=("$dep")
        fi
    done < <(collect_deps "$current")
done

echo "Found ${#DYLIBS[@]} Homebrew dylib dependencies:"
printf '  %s\n' "${DYLIBS[@]}"

# Copy each into Frameworks/ (following symlinks to get the real file)
for dep in "${DYLIBS[@]}"; do
    realdep="$(readlink -f "$dep" 2>/dev/null || python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$dep")"
    name="$(basename "$dep")"
    cp -f "$realdep" "${FRAMEWORKS}/${name}"
    chmod 644 "${FRAMEWORKS}/${name}"
    echo "Copied ${name}"
done

# Rewrite load commands: for atracdenc itself, and for every copied dylib,
# change any /opt/homebrew/... reference to @executable_path/../Frameworks/...
# and set each dylib's own -id likewise.
rewrite() {
    local target="$1"
    for dep in "${DYLIBS[@]}"; do
        local name
        name="$(basename "$dep")"
        install_name_tool -change "$dep" "@executable_path/../Frameworks/${name}" "$target" 2>/dev/null || true
    done
}

echo "Rewriting atracdenc load commands..."
rewrite "${BINARY}"

echo "Rewriting each bundled dylib's cross-references and id..."
for dep in "${DYLIBS[@]}"; do
    name="$(basename "$dep")"
    target="${FRAMEWORKS}/${name}"
    install_name_tool -id "@executable_path/../Frameworks/${name}" "$target"
    rewrite "$target"
done

echo "Done. Verifying..."
otool -L "${BINARY}"
