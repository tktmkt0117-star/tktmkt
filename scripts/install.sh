#!/usr/bin/env bash
# 人物補正エフェクトを Mac に導入する。使い方:
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/install.sh
# Team ID は Xcode › Settings › Accounts、または developer.apple.com の Membership で確認できる。
set -euo pipefail
cd "$(dirname "$0")/../PersonRetouch"

[[ "$(uname)" == "Darwin" ]] || { echo "macOS 上で実行してください"; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode が必要です(App Store から導入)"; exit 1; }
[[ -d /Library/Developer/Frameworks/FxPlug.framework ]] || {
  echo "FxPlug SDK が見つかりません。https://developer.apple.com/final-cut-pro/ から導入してください"; exit 1; }
[[ -n "${DEVELOPMENT_TEAM:-}" ]] || { echo "DEVELOPMENT_TEAM=<Team ID> を指定してください"; exit 1; }

# Homebrew 版は古い macOS で入らないことがあるため、配布済みバイナリを直接取得する
if command -v xcodegen >/dev/null; then
  XCODEGEN=xcodegen
else
  TOOLS="$PWD/.tools"
  if [[ ! -x "$TOOLS/xcodegen/bin/xcodegen" ]]; then
    mkdir -p "$TOOLS"
    curl -fL "https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip" -o "$TOOLS/xcodegen.zip"
    unzip -q -o "$TOOLS/xcodegen.zip" -d "$TOOLS"
  fi
  XCODEGEN="$TOOLS/xcodegen/bin/xcodegen"
fi
"$XCODEGEN" generate

xcodebuild -project PersonRetouch.xcodeproj -scheme PersonRetouch -configuration Release \
  -derivedDataPath build DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates build

APP="build/Build/Products/Release/PersonRetouch.app"
rm -rf /Applications/PersonRetouch.app
cp -R "$APP" /Applications/
open /Applications/PersonRetouch.app     # 初回起動でプラグインが登録される

if pgrep -x "Final Cut Pro" >/dev/null; then
  echo "Final Cut Pro を再起動してください"
fi
echo "完了: エフェクト › 人物補正 から使えます"
