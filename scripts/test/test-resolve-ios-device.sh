#!/bin/bash
# scripts/resolve-ios-device.sh のテスト。
# PATH の先頭に偽の xcrun を置き、`devicectl list devices --json-output <パス>` の呼び出しでフィクスチャの JSON を書き出させる。
# フィクスチャは devicectl の実際の JSON と同じキー (result.devices[].identifier・hardwareProperties.reality・
# connectionProperties.tunnelState) を持つ合成値で、identifier と hardwareProperties.udid は別の値にする (出すのは identifier)。
set -uo pipefail

script_path="$(cd "$(dirname "$0")/.." && pwd)/resolve-ios-device.sh"
failures=0

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

# 新しい一時ディレクトリに偽の xcrun と、xcrun の呼び出しの記録先を用意してパスを返す。
# 偽の xcrun は環境変数 FIXTURE_JSON のファイルを --json-output の先へ写す。
# 環境変数 XCRUN_FAIL=1 の時は、何も書き出さずに devicectl の失敗として exit 1 する。
make_workdir() {
  local workdir
  workdir="$(mktemp -d)"
  mkdir -p "$workdir/bin"
  cat > "$workdir/bin/xcrun" <<'FAKE'
#!/bin/bash
echo "$*" >> "$XCRUN_CALLS"
if [ "${XCRUN_FAIL:-}" = "1" ]; then
  echo "ERROR: devicectl failed" >&2
  exit 1
fi
while [ $# -gt 0 ]; do
  if [ "$1" = "--json-output" ]; then
    cp "$FIXTURE_JSON" "$2"
    exit 0
  fi
  shift
done
exit 0
FAKE
  chmod +x "$workdir/bin/xcrun"
  : > "$workdir/xcrun-calls"
  echo "$workdir"
}

# devicectl の 1 台分の JSON を出す。引数: identifier udid reality tunnelState
device_entry() {
  printf '{"identifier":"%s","hardwareProperties":{"udid":"%s","reality":"%s"},"connectionProperties":{"tunnelState":"%s"}}' "$1" "$2" "$3" "$4"
}

# 引数の各台を並べた devicectl の JSON をファイルに書いてパスを返す。
write_fixture() {
  local workdir="$1"
  shift
  printf '{"info":{"outcome":"success"},"result":{"devices":[%s]}}' "$(IFS=,; echo "$*")" > "$workdir/fixture.json"
  echo "$workdir/fixture.json"
}

# スクリプトを実行し、stdout を $workdir/out、stderr を $workdir/err に置いて exit code を返す。引数: workdir DEVICE IOS_DEVICE_UDID
run_resolve() {
  local workdir="$1"
  PATH="$workdir/bin:$PATH" XCRUN_CALLS="$workdir/xcrun-calls" FIXTURE_JSON="${FIXTURE_JSON:-}" \
    bash "$script_path" "$2" "$3" "$workdir/tmp/devices.json" > "$workdir/out" 2> "$workdir/err"
}

physical_a=$(device_entry "AAAAAAAA-0000-0000-0000-00000000000A" "00000000-000000000000000A" physical disconnected)
physical_b_connected=$(device_entry "BBBBBBBB-0000-0000-0000-00000000000B" "00000000-000000000000000B" physical connected)
simulator_connected=$(device_entry "55555555-0000-0000-0000-000000000005" "55555555-0000-0000-0000-000000000005" simulated connected)
missing_message="Error: 実機が見つかりません"

# 優先順: DEVICE が指定されたら、それを出して devicectl を呼ばない
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_a")" run_resolve "$workdir" "My iPhone" "UDID-FROM-ENV"
status=$?
check "DEVICE 指定は exit 0" test "$status" -eq 0
check "DEVICE 指定は DEVICE の値を出す (IOS_DEVICE_UDID より優先)" test "$(cat "$workdir/out")" = "My iPhone"
check "DEVICE 指定は devicectl を呼ばない" test ! -s "$workdir/xcrun-calls"

# 優先順: DEVICE が空なら IOS_DEVICE_UDID を出して devicectl を呼ばない
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_a")" run_resolve "$workdir" "" "UDID-FROM-ENV"
status=$?
check "IOS_DEVICE_UDID 指定は exit 0" test "$status" -eq 0
check "IOS_DEVICE_UDID 指定はその値を出す" test "$(cat "$workdir/out")" = "UDID-FROM-ENV"
check "IOS_DEVICE_UDID 指定は devicectl を呼ばない" test ! -s "$workdir/xcrun-calls"

# 自動解決: 実機 1 台 (未接続でも) を選び、hardwareProperties.udid ではなく identifier を出す
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_a")" run_resolve "$workdir" "" ""
status=$?
check "実機 1 台は exit 0" test "$status" -eq 0
check "実機 1 台はその identifier を出す" test "$(cat "$workdir/out")" = "AAAAAAAA-0000-0000-0000-00000000000A"
check "自動解決は devicectl list devices を呼ぶ" grep -q "^devicectl list devices --json-output $workdir/tmp/devices.json" "$workdir/xcrun-calls"

# 自動解決: 実機 1 台 + 接続中の simulator は、接続中でも simulator を選ばず実機を選ぶ
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$simulator_connected" "$physical_a")" run_resolve "$workdir" "" ""
status=$?
check "実機 1 台 + 接続中の simulator は exit 0" test "$status" -eq 0
check "実機 1 台 + 接続中の simulator は実機を出す" test "$(cat "$workdir/out")" = "AAAAAAAA-0000-0000-0000-00000000000A"

# 自動解決: 実機 2 台で接続中が 1 台なら、その 1 台を選ぶ
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_a" "$physical_b_connected" "$(device_entry "66666666-0000-0000-0000-000000000006" "66666666-0000-0000-0000-000000000006" simulated disconnected)")" run_resolve "$workdir" "" ""
status=$?
check "実機 2 台で接続中 1 台は exit 0" test "$status" -eq 0
check "実機 2 台で接続中 1 台は接続中の実機を出す" test "$(cat "$workdir/out")" = "BBBBBBBB-0000-0000-0000-00000000000B"

# 異常系: 実機 2 台とも接続中なら決められず exit 1
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_b_connected" "$(device_entry "CCCCCCCC-0000-0000-0000-00000000000C" "00000000-000000000000000C" physical connected)")" run_resolve "$workdir" "" ""
status=$?
check "実機 2 台とも接続中は exit 1" test "$status" -eq 1
check "実機 2 台とも接続中は何も出さない" test ! -s "$workdir/out"
check "実機 2 台とも接続中は指定を求める" grep -q "$missing_message" "$workdir/err"

# 異常系: 実機 2 台とも未接続で、接続中の simulator があっても simulator を選ばず exit 1
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$physical_a" "$(device_entry "DDDDDDDD-0000-0000-0000-00000000000D" "00000000-000000000000000D" physical disconnected)" "$simulator_connected")" run_resolve "$workdir" "" ""
status=$?
check "実機 2 台とも未接続 + 接続中の simulator は exit 1" test "$status" -eq 1
check "実機 2 台とも未接続 + 接続中の simulator は simulator を出さない" test ! -s "$workdir/out"

# 異常系 (境界値 0 台): simulator だけなら、接続中でも選ばず exit 1
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir" "$simulator_connected")" run_resolve "$workdir" "" ""
status=$?
check "simulator だけは exit 1" test "$status" -eq 1
check "simulator だけは何も出さない" test ! -s "$workdir/out"
check "simulator だけは指定を求める" grep -q "$missing_message" "$workdir/err"

# 異常系 (境界値 0 台): 一覧が空なら exit 1
workdir="$(make_workdir)"
FIXTURE_JSON="$(write_fixture "$workdir")" run_resolve "$workdir" "" ""
status=$?
check "一覧が空は exit 1" test "$status" -eq 1
check "一覧が空は指定を求める" grep -q "$missing_message" "$workdir/err"

# 異常系 (外部呼び出しの失敗): devicectl が失敗したら、前回の書き出し先に残った JSON の実機を出さずに非 0 で止まる
workdir="$(make_workdir)"
mkdir -p "$workdir/tmp"
cp "$(write_fixture "$workdir" "$physical_a")" "$workdir/tmp/devices.json"
XCRUN_FAIL=1 run_resolve "$workdir" "" ""
status=$?
check "devicectl の失敗は非 0" test "$status" -ne 0
check "devicectl の失敗は何も出さない" test ! -s "$workdir/out"
check "devicectl の失敗は devicectl のエラーを出す" grep -q "ERROR: devicectl failed" "$workdir/err"

# 異常系 (不正な入力): devicectl の JSON が壊れていたら、実機を出さずに非 0 で止まる
workdir="$(make_workdir)"
printf '{"result": {"devices": [' > "$workdir/broken.json"
FIXTURE_JSON="$workdir/broken.json" run_resolve "$workdir" "" ""
status=$?
check "壊れた JSON は非 0" test "$status" -ne 0
check "壊れた JSON は何も出さない" test ! -s "$workdir/out"

# 異常系 (不正な入力): result.devices を持たない JSON も、実機を出さずに非 0 で止まる
workdir="$(make_workdir)"
printf '{"info":{"outcome":"failed"},"result":{}}' > "$workdir/no-devices.json"
FIXTURE_JSON="$workdir/no-devices.json" run_resolve "$workdir" "" ""
status=$?
check "result.devices の無い JSON は非 0" test "$status" -ne 0
check "result.devices の無い JSON は何も出さない" test ! -s "$workdir/out"

# 異常系 (引数の欠落): JSON の書き出し先が無いと、DEVICE があっても理由を出して非 0 で止まる
workdir="$(make_workdir)"
PATH="$workdir/bin:$PATH" XCRUN_CALLS="$workdir/xcrun-calls" bash "$script_path" "My iPhone" "" > "$workdir/out" 2> "$workdir/err"
status=$?
check "第 3 引数が無いと非 0" test "$status" -ne 0
check "第 3 引数が無いと何も出さない" test ! -s "$workdir/out"
check "第 3 引数が無いと理由を出す" grep -q "devicectl の JSON の書き出し先を第 3 引数に渡してください" "$workdir/err"

# 冪等: 書き出し先の JSON が既にあっても上書きし、同じ一覧なら同じ値を出す
workdir="$(make_workdir)"
fixture="$(write_fixture "$workdir" "$physical_a")"
FIXTURE_JSON="$fixture" run_resolve "$workdir" "" ""
FIXTURE_JSON="$fixture" run_resolve "$workdir" "" ""
status=$?
check "2 回目も exit 0" test "$status" -eq 0
check "2 回目も同じ実機を出す" test "$(cat "$workdir/out")" = "AAAAAAAA-0000-0000-0000-00000000000A"

if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures"
  exit 1
fi
echo "ALL PASS"
