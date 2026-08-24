#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/轻刷题.app"
CACHE_DIR="$BUILD_DIR/module-cache"

mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

CLANG_MODULE_CACHE_PATH="$CACHE_DIR" SWIFT_MODULECACHE_PATH="$CACHE_DIR" \
swiftc "$PROJECT_DIR"/Sources/QuickQuiz/*.swift \
    -swift-version 5 \
    -O \
    -framework AppKit \
    -framework PDFKit \
    -framework Carbon \
    -o "$APP_DIR/Contents/MacOS/QuickQuiz"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/2020广东县级真题.pdf" "$APP_DIR/Contents/Resources/2020广东县级真题.pdf"
cp "$PROJECT_DIR/Resources/2020广东县级答案解析.pdf" "$APP_DIR/Contents/Resources/2020广东县级答案解析.pdf"
cp "$PROJECT_DIR/Resources/BundledQuestionBank.json" "$APP_DIR/Contents/Resources/BundledQuestionBank.json"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
