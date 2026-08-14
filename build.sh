#!/bin/bash
# =============================================================================
# DeepSeek Harness 一键重建脚本
#   用法: bash build.sh                    # 重建 build/DeepSeek Harness.app 并安装到 ~/Applications
#         bash build.sh --no-install       # 只重建到 build/，不安装
#   前置: swiftc(Xcode CLT)、sips、iconutil、node
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/src/main.swift"
PLIST_SRC="$PROJECT_DIR/assets/Info.plist"
BUILD_DIR="$PROJECT_DIR/build"
APP="$BUILD_DIR/DeepSeek Harness.app"
INSTALL_DIR="$HOME/Applications"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

INSTALL=1
[ "${1:-}" = "--no-install" ] && INSTALL=0

command -v swiftc  >/dev/null || { echo "缺少 swiftc（请安装 Xcode Command Line Tools）"; exit 1; }
command -v sips     >/dev/null || { echo "缺少 sips"; exit 1; }
command -v iconutil >/dev/null || { echo "缺少 iconutil"; exit 1; }
command -v node     >/dev/null || { echo "缺少 node"; exit 1; }

# ---------- 1. 组装目录 ----------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/icon.iconset"

# ---------- 2. 编译 ----------
# 【绝对不要踩的坑】必须显式 -target arm64-apple-macosx26.0：
#   swiftc 默认把 minos 编成 SDK 版本(如 28.0)，高于本机系统(27.0)时，
#   LaunchServices 拒绝启动，open 报 -10825 (kLSIncompatibleSystemVersionErr)。
#   部署目标必须 ≤ 当前系统版本；Info.plist 的 LSMinimumSystemVersion 要同步。
swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 \
  -framework Cocoa -framework WebKit "$SRC" \
  -o "$APP/Contents/MacOS/dsh-web-launcher"
echo "编译完成: $(otool -l "$APP/Contents/MacOS/dsh-web-launcher" | awk '/minos/{print $2; exit}') minos"

# ---------- 3. Info.plist ----------
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# ---------- 3.5 默认插件安装脚本 + 启动界面 logo（app 启动时按需调用/展示）----------
cp "$PROJECT_DIR/assets/install-dsh-better-sidebar.sh" "$APP/Contents/Resources/install-dsh-better-sidebar.sh"
chmod +x "$APP/Contents/Resources/install-dsh-better-sidebar.sh"
cp "$PROJECT_DIR/assets/splash-logo.svg" "$APP/Contents/Resources/splash-logo.svg"
cp "$PROJECT_DIR/assets/splash-logo.png" "$APP/Contents/Resources/splash-logo.png"

# ---------- 4. 图标（DeepSeek logo → sips 多尺寸 → iconutil 出 icns）----------
# 图标源：assets/app-icon.png（用户提供的 DeepSeek logo，712×712 RGBA）。
# 旧的 assets/gen-icon.mjs 自绘生成器不再参与构建，保留备用。
cp "$PROJECT_DIR/assets/app-icon.png" "$BUILD_DIR/master.png"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512"; do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" "$BUILD_DIR/master.png" --out "$BUILD_DIR/icon.iconset/$name.png" >/dev/null
done
cp "$BUILD_DIR/master.png" "$BUILD_DIR/icon.iconset/icon_512x512@2x.png"
iconutil -c icns "$BUILD_DIR/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$BUILD_DIR/icon.iconset"

# ---------- 5. 安装 ----------
if [ "$INSTALL" = "1" ]; then
  rm -rf "$INSTALL_DIR/DeepSeek Harness.app"
  cp -R "$APP" "$INSTALL_DIR/"
  # 改 bundle 后必须重注册 LaunchServices，否则 open 找不到/拒启
  "$LSREG" -f "$INSTALL_DIR/DeepSeek Harness.app"
  echo "已安装: $INSTALL_DIR/DeepSeek Harness.app"
  echo "启动: open \"$INSTALL_DIR/DeepSeek Harness.app\""
else
  echo "已重建(未安装): $APP"
fi
