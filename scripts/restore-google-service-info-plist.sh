#!/bin/bash
# GitHub Actions の secret GOOGLE_SERVICE_INFO_PLIST_BASE64 (base64 にした Firebase の設定ファイル) を、
# アプリ本体が読む QuickBuy/GoogleService-Info.plist に書き出す。
#
# 設定ファイルは API キーを含むため、リポジトリに入れず (.gitignore)、CI と simtunnel のビルドの前にこのスクリプトで書き出す
# (手順: ~/.claude/skills/firebase-project-setup/SKILL.md「アプリの Firebase 設定ファイル」)。
# 書き出し先は QuickBuy.xcodeproj の file reference (QuickBuy/GoogleService-Info.plist) と同じパス。
#
# 入力: 環境変数 GOOGLE_SERVICE_INFO_PLIST_BASE64
# 終了コード: 0 = 書き出した / 1 = secret が空 (未登録・fork からの PR) か、書き出した中身が plist として読めない
# (「plist として読めない」には、Firebase の SDK が読むキー GOOGLE_APP_ID を持たない時を含む)
# fork からの PR では secret が渡らず exit 1 になり、CI のテストとビルドは走らない。設定ファイルが無いとアプリのビルドが
# Resources の参照で失敗するため、ダミーの設定ファイルで続けず、ここで理由を出して止める
# テスト: scripts/test/test-restore-google-service-info-plist.sh
# 何度実行しても同じ中身で上書きするだけで、結果は変わらない。
# public リポジトリの run ログに中身を出さないよう、中身を表示するコマンドを使わない。
set -euo pipefail

: "${GOOGLE_SERVICE_INFO_PLIST_BASE64:?secret GOOGLE_SERVICE_INFO_PLIST_BASE64 が空 (未登録か、fork からの PR のため渡されていない)}"

output_path="$(cd "$(dirname "$0")/.." && pwd)/QuickBuy/GoogleService-Info.plist"
printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$output_path"
# plutil -lint は 1 行の文字列も (OpenStep 形式の) plist として通すため、Firebase の SDK が読むキー GOOGLE_APP_ID を取り出せるかで確かめる
plutil -extract GOOGLE_APP_ID raw -o /dev/null "$output_path" >/dev/null 2>&1 || {
  echo "secret GOOGLE_SERVICE_INFO_PLIST_BASE64 を base64 で戻した中身が plist として読めないか、GOOGLE_APP_ID を持たない" >&2
  exit 1
}
echo "QuickBuy/GoogleService-Info.plist を書き出した"
