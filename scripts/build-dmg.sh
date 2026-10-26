#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export UNIVERSAL=1
bash scripts/build-app.sh
version="$(cat VERSION)"
bundle="$PWD/dist/NumpadLuma.app"
image="$PWD/dist/NumpadLuma-$version-universal.dmg"
staging="$(mktemp -d "${TMPDIR:-/tmp}/numpadluma-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

mkdir "$staging/volume"
ditto "$bundle" "$staging/volume/NumpadLuma.app"
ln -s /Applications "$staging/volume/Applications"
hdiutil create -volname NumpadLuma -srcfolder "$staging/volume" -format UDZO -ov "$image"

# Some macOS versions leave the image creation device attached. Release only
# devices belonging to this output image.
devices="$(hdiutil info -plist | /usr/bin/python3 -c '
import os, plistlib, sys
target = os.path.realpath(sys.argv[1])
for item in plistlib.loads(sys.stdin.buffer.read()).get("images", []):
    if os.path.realpath(item.get("image-path", "")) == target:
        for entity in item.get("system-entities", []):
            if entity.get("dev-entry"):
                print(entity["dev-entry"])
                break
' "$image")"
while IFS= read -r device; do
    if [[ -n "$device" ]]; then hdiutil detach "$device"; fi
done <<< "$devices"

(cd dist && shasum -a 256 "NumpadLuma-$version-universal.dmg" > "NumpadLuma-$version-SHA256SUMS.txt")
printf '\nDMG: %s\n' "$image"
