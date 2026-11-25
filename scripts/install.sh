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

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

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
