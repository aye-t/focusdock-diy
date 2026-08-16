#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
if [[ -f "$project_dir/Sources/Resources/Info.plist" ]]; then
    resources_dir="$project_dir/Sources/Resources"
else
    resources_dir="$project_dir/Resources"
fi
icon_base="$resources_dir/AppIconBase.png"
iconset_dir="$project_dir/.build/AppIcon.iconset"
app_name="FocusDock"
app_dir="$project_dir/dist/$app_name.app"
resource_bundle="$project_dir/.build/release/FocusDockMac_FocusDockMac.bundle"

cd "$project_dir"
swift build -c release --disable-sandbox

mkdir -p "$resources_dir"
swift "$script_dir/make_icon.swift" "$icon_base"
rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"

sips -z 16 16 "$icon_base" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_base" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_base" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_base" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_base" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_base" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_base" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_base" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_base" --out "$iconset_dir/icon_512x512.png" >/dev/null
cp "$icon_base" "$iconset_dir/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o "$resources_dir/AppIcon.icns"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/FocusDock" "$app_dir/Contents/MacOS/$app_name"
chmod +x "$app_dir/Contents/MacOS/$app_name"
cp "$resources_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$resources_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
if [[ ! -d "$resource_bundle" ]]; then
    echo "Missing SwiftPM resource bundle: $resource_bundle" >&2
    exit 1
fi
ditto "$resource_bundle" "$app_dir/Contents/Resources/FocusDockMac_FocusDockMac.bundle"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
