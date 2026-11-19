#!/bin/bash
# scripts/restore-google-service-info-plist.sh のテスト。
# スクリプトを一時ディレクトリの scripts/ に写して実行し、書き出し先 (一時ディレクトリの QuickBuy/GoogleService-Info.plist) を確かめる。
# リポジトリの QuickBuy/GoogleService-Info.plist には触れない。
set -uo pipefail

script_path="$(cd "$(dirname "$0")/.." && pwd)/restore-google-service-info-plist.sh"
failures=0

# 新しい一時ディレクトリに scripts/ と QuickBuy/ を作り、スクリプトを写したパスを返す。
make_workdir() {
  local workdir
  workdir="$(mktemp -d)"
  mkdir -p "$workdir/scripts" "$workdir/QuickBuy"
  cp "$script_path" "$workdir/scripts/"
  echo "$workdir"
}

# 条件が真なら PASS、偽なら FAIL を出して数える。
check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

valid_plist='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>GOOGLE_APP_ID</key><string>1:0:ios:0</string><key>PROJECT_ID</key><string>marker-project-id-7f3a</string></dict></plist>'

# 正常系: plist の base64 を渡すと、同じ中身を書き出して exit 0。中身はログに出さない
workdir="$(make_workdir)"
output="$(GOOGLE_SERVICE_INFO_PLIST_BASE64="$(printf '%s' "$valid_plist" | base64)" bash "$workdir/scripts/restore-google-service-info-plist.sh" 2>&1)"
status=$?
check "正しい plist は exit 0" test "$status" -eq 0
check "正しい plist は同じ中身を書き出す" test "$(cat "$workdir/QuickBuy/GoogleService-Info.plist")" = "$valid_plist"
check "正しい plist の中身をログに出さない" bash -c '! grep -q marker-project-id-7f3a <<<"$1"' _ "$output"

# 冪等: 同じ入力で 2 回目を実行しても同じ中身で exit 0
GOOGLE_SERVICE_INFO_PLIST_BASE64="$(printf '%s' "$valid_plist" | base64)" bash "$workdir/scripts/restore-google-service-info-plist.sh" >/dev/null 2>&1
status=$?
check "2 回目も exit 0" test "$status" -eq 0
check "2 回目も同じ中身" test "$(cat "$workdir/QuickBuy/GoogleService-Info.plist")" = "$valid_plist"

# 異常系: secret が未設定
workdir="$(make_workdir)"
output="$(env -u GOOGLE_SERVICE_INFO_PLIST_BASE64 bash "$workdir/scripts/restore-google-service-info-plist.sh" 2>&1)"
status=$?
check "secret が未設定なら exit 1" test "$status" -eq 1
check "secret が未設定なら理由を出す" bash -c 'grep -q "GOOGLE_SERVICE_INFO_PLIST_BASE64 が空" <<<"$1"' _ "$output"
check "secret が未設定なら書き出さない" test ! -e "$workdir/QuickBuy/GoogleService-Info.plist"

# 異常系 (境界値): secret が空文字
workdir="$(make_workdir)"
GOOGLE_SERVICE_INFO_PLIST_BASE64="" bash "$workdir/scripts/restore-google-service-info-plist.sh" >/dev/null 2>&1
status=$?
check "secret が空文字なら exit 1" test "$status" -eq 1

# 異常系: base64 で戻せるが plist ではない中身
workdir="$(make_workdir)"
output="$(GOOGLE_SERVICE_INFO_PLIST_BASE64="$(printf 'not-a-plist-marker-91c2' | base64)" bash "$workdir/scripts/restore-google-service-info-plist.sh" 2>&1)"
status=$?
check "plist でない中身なら exit 1" test "$status" -eq 1
check "plist でない中身なら理由を出す" bash -c 'grep -q "plist として読めない" <<<"$1"' _ "$output"
check "plist でない中身をログに出さない" bash -c '! grep -q not-a-plist-marker-91c2 <<<"$1"' _ "$output"

# 異常系 (境界値): plist として読めるが GOOGLE_APP_ID を持たない
workdir="$(make_workdir)"
plist_without_app_id='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>PROJECT_ID</key><string>marker-project-id-7f3a</string></dict></plist>'
output="$(GOOGLE_SERVICE_INFO_PLIST_BASE64="$(printf '%s' "$plist_without_app_id" | base64)" bash "$workdir/scripts/restore-google-service-info-plist.sh" 2>&1)"
status=$?
check "GOOGLE_APP_ID を持たない plist なら exit 1" test "$status" -eq 1
check "GOOGLE_APP_ID を持たない plist なら理由を出す" bash -c 'grep -q "GOOGLE_APP_ID を持たない" <<<"$1"' _ "$output"
check "GOOGLE_APP_ID を持たない plist の中身をログに出さない" bash -c '! grep -q marker-project-id-7f3a <<<"$1"' _ "$output"

# 異常系: base64 として戻せない文字列
workdir="$(make_workdir)"
GOOGLE_SERVICE_INFO_PLIST_BASE64='!!!not base64!!!' bash "$workdir/scripts/restore-google-service-info-plist.sh" >/dev/null 2>&1
status=$?
check "base64 として戻せない secret なら exit 1" test "$status" -eq 1

if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures"
  exit 1
fi
echo "ALL PASS"
