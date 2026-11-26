#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"
PY_VER="${PY_VER:-3.12.8}"
PY_TAG="${PY_TAG:-20241122}"

echo "==> clean python-dist"
rm -rf "$IOS/python-dist"
mkdir -p "$IOS/python-dist"

URL="https://github.com/indygreg/python-build-standalone/releases/download/${PY_TAG}/cpython-${PY_VER}+${PY_TAG}-aarch64-apple-ios-install_only.tar.gz"
echo "==> download $URL"
curl -fL --retry 3 --retry-delay 3 -o /tmp/py-ios.tar.gz "$URL"

echo "==> extract"
tar -xzf /tmp/py-ios.tar.gz -C "$IOS/python-dist" --strip-components=1
ls -la "$IOS/python-dist/bin" | head -10

"$IOS/python-dist/bin/python3" -c "import sys; print(sys.version)"
"$IOS/python-dist/bin/python3" -c "import json, urllib.request, socket, sqlite3, hmac, hashlib, http.server; print('stdlib ok')"

test -f "$ROOT/backend/run.py"

echo "==> xcodebuild archive (no code sign)"
cd "$IOS"
xcodebuild -project SigninHub.xcodeproj -scheme SigninHub -configuration Release -sdk iphoneos -destination "generic/platform=iOS" -archivePath "$ROOT/build/SigninHub.xcarchive" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive 2>&1 | tee /tmp/xcodebuild.log | tail -40

APP="$ROOT/build/SigninHub.xcarchive/Products/Applications/SigninHub.app"
test -d "$APP" || { echo "no SigninHub.app in archive"; exit 1; }

echo "==> package IPA"
rm -rf "$ROOT/build/Payload"
mkdir -p "$ROOT/build/Payload"
cp -R "$APP" "$ROOT/build/Payload/"
cd "$ROOT/build"
zip -qry "$ROOT/build/SigninHub-unsigned.ipa" Payload

ls -lh "$ROOT/build/SigninHub-unsigned.ipa"
unzip -l "$ROOT/build/SigninHub-unsigned.ipa" | head -20
