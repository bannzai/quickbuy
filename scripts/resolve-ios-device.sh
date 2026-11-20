#!/bin/bash
# make install-device のインストール先の実機を解決し、devicectl の --device に渡す値を標準出力に 1 行で出す。
#
# 使い方: scripts/resolve-ios-device.sh <DEVICE> <IOS_DEVICE_UDID> <devicectl の JSON の書き出し先>
#   第 1 引数・第 2 引数は空文字でよい。Makefile は make 変数 DEVICE と環境変数 IOS_DEVICE_UDID をそのまま渡す。
#
# 解決順: 第 1 引数 (DEVICE。名前か UDID) > 第 2 引数 (IOS_DEVICE_UDID) > devicectl の JSON から実機を自動解決。
# 自動解決: devicectl は起動中の simulator も一覧に載せるため、先に実機 (hardwareProperties.reality == "physical") に絞る。
# 実機が 1 台ならそれ、複数台なら接続中 (connectionProperties.tunnelState == "connected") の 1 台の identifier を出す。
#
# exit code: 0 = 解決できた / 1 = 実機を決められない (0 台・接続中が 0 台か複数台)。理由は標準エラーに出す。
# 冪等: 引数が同じで devicectl の一覧が同じなら同じ値を出す。JSON の書き出し先は毎回上書きする。
set -euo pipefail

device="${1:-}"
devices_json="${3:?devicectl の JSON の書き出し先を第 3 引数に渡してください}"

if [ -z "$device" ]; then
  device="${2:-}"
fi

if [ -z "$device" ]; then
  mkdir -p "$(dirname "$devices_json")"
  xcrun devicectl list devices --json-output "$devices_json" > /dev/null
  device=$(jq -r '[.result.devices[] | select(.hardwareProperties.reality == "physical")] | if length == 1 then .[0] else (map(select(.connectionProperties.tunnelState == "connected")) | if length == 1 then .[0] else empty end) end | .identifier // empty' "$devices_json")
fi

if [ -z "$device" ]; then
  echo "Error: 実機が見つかりません (IOS_DEVICE_UDID を export するか DEVICE=<名前|UDID> で指定してください)" >&2
  exit 1
fi

echo "$device"
