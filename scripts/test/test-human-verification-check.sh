#!/bin/bash
# .github/workflows/human-verification-check.yml の「## 人間が確認」の判定のテスト。
# workflow の step の run: を Ruby の YAML で取り出し、GitHub Actions が shell 未指定の run: を実行するのと同じ
# `bash -e` (出典: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax の
# jobs.<job_id>.steps[*].shell の表) で、PR_BODY を変えて実行する。workflow のファイルは変えない。
set -uo pipefail

workflow="$(cd "$(dirname "$0")/../.." && pwd)/.github/workflows/human-verification-check.yml"
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

workdir="$(mktemp -d)"
step_script="$workdir/step.sh"
ruby -ryaml -e '
  workflow = YAML.load_file(ARGV[0])
  step = workflow["jobs"]["human-verification"]["steps"].find { |s| s["name"] == "「## 人間が確認」の未チェック項目を検出する" }
  print step["run"] if step
' "$workflow" > "$step_script"

# 取り出しに失敗して空のスクリプトを実行すると、どの body も exit 0 で「通る側」が全部通ってしまうため、先に止める。
if ! grep -q 'PR_BODY' "$step_script"; then
  echo "FAIL workflow から判定の run: を取り出せない ($workflow)"
  exit 1
fi

# PR_BODY を渡して判定を実行し、出力を $workdir/out に置いて exit code を返す。
run_check() {
  PR_BODY="$1" bash -e "$step_script" > "$workdir/out" 2>&1
}

# 止まる側: 節の中の未チェック項目は exit 1。引数: ケース名 body
expect_block() {
  run_check "$2"
  local status=$?
  check "$1 は exit 1" test "$status" -eq 1
  check "$1 は未チェック項目のエラーを出す" grep -q '::error::「## 人間が確認」に未チェック項目が' "$workdir/out"
}

# 通る側: exit 0 で、期待する文言を出す。引数: ケース名 body 期待する文言
expect_pass() {
  run_check "$2"
  local status=$?
  check "$1 は exit 0" test "$status" -eq 0
  check "$1 は「$3」を出す" grep -qF "$3" "$workdir/out"
}

no_section_message="「## 人間が確認」セクションが無いためチェック対象外です"
all_checked_message="「## 人間が確認」の項目はすべてチェック済みです"

# 止まる側: 箇条書きの記号ごとの未チェック項目
expect_block "- の未チェック項目" $'## 概要\n\n本文\n\n## 人間が確認\n\n- [ ] Secrets を登録する\n'
expect_block "* の未チェック項目" $'## 人間が確認\n* [ ] Secrets を登録する\n'
expect_block "+ の未チェック項目" $'## 人間が確認\n+ [ ] Secrets を登録する\n'
expect_block "番号付き (1.) の未チェック項目" $'## 人間が確認\n1. [ ] Secrets を登録する\n'
expect_block "番号付き (12)) の未チェック項目" $'## 人間が確認\n12) [ ] Secrets を登録する\n'
expect_block "字下げした未チェック項目" $'## 人間が確認\n- [x] 済み\n  - [ ] 字下げした未チェック\n'
expect_block "節の中の ### 小見出しの下の未チェック項目" $'## 人間が確認\n### マージ前\n- [ ] Secrets を登録する\n'
expect_block "見出しの行末に空白がある節の未チェック項目" $'## 人間が確認  \n- [ ] Secrets を登録する\n'
# CRLF: CR を除かないと見出しの行が「## 人間が確認\r」になり節が見つからず、通ってしまう
expect_block "CRLF の body の未チェック項目" $'## 概要\r\n本文\r\n## 人間が確認\r\n- [ ] Secrets を登録する\r\n'

# 件数: チェック済みと未チェックが混ざる時は、未チェックだけを数えて行を出す
run_check $'## 人間が確認\n- [x] 済み\n- [ ] 未チェック 1\n- [X] 済み (大文字)\n1. [ ] 未チェック 2\n'
status=$?
check "混在は exit 1" test "$status" -eq 1
check "混在は未チェックの 2 件を数える" grep -qF '未チェック項目が 2 件あります' "$workdir/out"
check "混在は未チェックの行を出す" grep -qF -- '- [ ] 未チェック 1' "$workdir/out"
check "混在はチェック済みの行を出さない" bash -c '! grep -qF -- "- [x] 済み" "$1"' _ "$workdir/out"

# 通る側: 節が無い・空
expect_pass "節が無い body" $'## 概要\n\n本文\n' "$no_section_message"
expect_pass "空の body" "" "$no_section_message"
expect_pass "見出しだけで中身が空行の節" $'## 人間が確認\n\n\n' "$no_section_message"
expect_pass "別の見出し (## 人間が確認する手順) の下の未チェック項目" $'## 人間が確認する手順\n- [ ] 手順\n' "$no_section_message"

# 通る側: 節の中身がチェック済み・未チェックの形でない
expect_pass "節の中身が「なし」" $'## 人間が確認\n\nなし\n\n## 検証\n- 済み\n' "$all_checked_message"
expect_pass "チェック済みだけの節" $'## 人間が確認\n- [x] Secrets を登録した\n1. [X] 実機で確かめた\n' "$all_checked_message"
expect_pass "節の地の文の中の [ ]" $'## 人間が確認\n未チェックは - [ ] の形で書く\n' "$all_checked_message"
expect_pass "記号と [ ] の間に空白が無い行" $'## 人間が確認\n-[ ] 箇条書きではない\n' "$all_checked_message"

# 通る側: 別の ## 節の未チェック項目 (節の前と後)
expect_pass "前の ## 節の未チェック項目" $'## やること\n- [ ] 後で\n\n## 人間が確認\n- [x] 済み\n' "$all_checked_message"
expect_pass "後の ## 節の未チェック項目" $'## 人間が確認\n- [x] 済み\n\n## 未達の完了条件\n- [ ] マージ後に行う\n' "$all_checked_message"

if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures"
  exit 1
fi
echo "ALL PASS"
