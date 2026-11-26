#!/usr/bin/env bash
# 出未签名 IPA。
#
# 前提：iOS 侧是**远程客户端**，不再打包 CPython ——
# Foundation.Process 在 iOS 上 unavailable，沙盒也不允许 fork/exec。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"

echo "==> 校验工程文件完整性"
python3 - "$ROOT" <<'PY'
import json, os, plistlib, re, sys
root = sys.argv[1]
ios = os.path.join(root, 'ios')
errors = []

# Info.plist
try:
    info = plistlib.load(open(os.path.join(ios, 'SigninHub', 'Info.plist'), 'rb'))
except Exception as e:
    errors.append(f'Info.plist 解析失败: {e}'); info = {}

# scheme
try:
    plistlib.load(open(os.path.join(ios, 'SigninHub.xcodeproj/xcshareddata/xcschemes/SigninHub.xcscheme'), 'rb'))
except Exception as e:
    errors.append(f'xcscheme 解析失败: {e}')

# pbxproj：每个 PBXFileReference 的 path 必须在磁盘上存在
pbx = open(os.path.join(ios, 'SigninHub.xcodeproj', 'project.pbxproj'), encoding='utf-8').read()
base = os.path.join(ios, 'SigninHub')
skip = {'SigninHub.app'}
for m in re.finditer(r'(\w{8}) /\* .*? \*/ = \{\s*isa = PBXFileReference;(.*?)\};', pbx, re.S):
    body = m.group(2)
    pm = re.search(r'path = "?([^";]+)"?;', body)
    if not pm: continue
    path = pm.group(1)
    if path in skip: continue
    if 'BUILT_PRODUCTS_DIR' in body: continue
    st = re.search(r"sourceTree = \"?([^\";]+)\"?;", body)
    tree = st.group(1) if st else "<group>"
    if tree == "SOURCE_ROOT":
        full = os.path.normpath(os.path.join(ios, path))
    else:
        full = os.path.normpath(os.path.join(base, path))
    if not os.path.exists(full):
        errors.append(f'pbxproj 引用了不存在的文件: {path}')

# Asset catalog 内部 JSON
for dirpath, _, files in os.walk(os.path.join(base, 'Assets.xcassets')):
    for f in files:
        if f.endswith('.json'):
            try: json.load(open(os.path.join(dirpath, f)))
            except Exception as e: errors.append(f'{f} 非法: {e}')

# BGTask id 必须与 Swift 常量一致
bg = open(os.path.join(base, 'Background', 'BGSign.swift'), encoding='utf-8').read()
swift_ids = set(re.findall(r'taskID = "([^"]+)"', bg))
plist_ids = set(info.get('BGTaskSchedulerPermittedIdentifiers', []))
if swift_ids != plist_ids:
    errors.append(f'BGTask id 不一致: swift={swift_ids} plist={plist_ids}')

if errors:
    print('工程校验失败：')
    for e in errors: print('  -', e)
    sys.exit(1)
print('工程校验通过：', len(errors), '个错误')
PY

echo "==> xcodebuild archive（不签名）"
cd "$IOS"
xcodebuild -project SigninHub.xcodeproj -scheme SigninHub -configuration Release -sdk iphoneos -destination "generic/platform=iOS" -archivePath "$ROOT/build/SigninHub.xcarchive" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive 2>&1 | tee /tmp/xcodebuild.log | tail -40

APP="$ROOT/build/SigninHub.xcarchive/Products/Applications/SigninHub.app"
test -d "$APP" || { echo "归档里没有 SigninHub.app"; exit 1; }

echo "==> 打 IPA"
rm -rf "$ROOT/build/Payload"
mkdir -p "$ROOT/build/Payload"
cp -R "$APP" "$ROOT/build/Payload/"
cd "$ROOT/build"
zip -qry "$ROOT/build/SigninHub-unsigned.ipa" Payload
ls -lh "$ROOT/build/SigninHub-unsigned.ipa"
