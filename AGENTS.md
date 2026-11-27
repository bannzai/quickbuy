# Quick Buy

Shopify の店のいつもの商品を、探さずに買い直すアプリ。

## 概要
@documents/PROJECT.md

仮説・判定基準・必要な機能・決めたこと・用語は `documents/DIRECTION.md` に置く。issue を書く時と読む時は、プロダクト固有の言葉の意味を同文書の「用語」で確かめる。

## Xcode プロジェクト構成の変更

- `QuickBuy.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない (理由: [ADR 0002](documents/adr/0002-manage-xcode-project-directly.md)。機械検査: `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目)
- ターゲット、ファイル、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `QuickBuy.xcodeproj/project.pbxproj`、Scheme を `QuickBuy.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 変更後は `git diff -- QuickBuy.xcodeproj` で意図した差分だけであることを確認し、下記の検証方法でビルドとテストを確かめる

## 検証方法

ビルド・simulator・ブラウザの動作確認は、作業用の Mac (agent が動いているマシン) で実行せず、外部のマシンで行う (owner の指定。立ち上げの依頼 https://github.com/bannzai/IdeaMemo/issues/398 を受けたセッションで 2026-11-17 に決定)。本リポジトリは public のため GitHub Actions の runner (PR の CI・simtunnel・webtunnel) を使い、private / internal に変わった時は Devin (`/devin-macos-e2e` skill) を使う。

- ビルド・ユニットテスト: PR の CI (`.github/workflows/ci-test.yml` の job `test`。macOS runner で `xcodebuild test`) の結果で確かめる。作業用の Mac で `xcodebuild`・`make build-ios`・`make test` を実行しない
  - 確認は `gh pr checks <PR 番号> --watch`。失敗した check は `gh run view <run ID> --log-failed` でログを読み、warning も確認する
  - PR の無いブランチは `gh workflow run ci-test.yml --ref <ブランチ>` で流す (実行場所の判定の SSOT は `/verify` skill「実行場所の判定」)
- 動作確認 (UI・挙動): `/ios-simulator` skill を起点にし、**特別な理由がない限り simtunnel (GitHub Actions macOS Runner 上のリモート iOS Simulator) で行う**。ローカル simulator (sim-boot) は使わない。issue や手順書にローカル前提の記述 (`make ios` 等) があっても、ローカルに倒す理由にしない
  - 手順: 検証対象のブランチを push してから `SIMTUNNEL_REPO=bannzai/quickbuy ~/ghq/github.com/bannzai/simtunnel/local/simtunnel up <セッション名> --ref <ブランチ> --wait` で起動する (`--ref` を省略すると main がビルドされる)。caller workflow は `.github/workflows/simulator-session.yml`、セッション名は `quickbuy-<worktree 名>` (例: `quickbuy-issue-12`。tailnet ホスト名が repo 横断で衝突しないよう worktree 名だけにしない)。操作・スクリーンショットは `/ios-simulator` skill の `scripts/ios-wda.sh --session <セッション名>` (セッション途中から使う場合) か、`.mcp.json` に書き込んだ mobile-mcp 互換ツールで行う。確認が終わったら `SIMTUNNEL_REPO=bannzai/quickbuy ~/ghq/github.com/bannzai/simtunnel/local/simtunnel down <セッション名>` で閉じる (macOS runner の並列上限を CI と共有するため放置しない)
  - 到達困難な状態 (お気に入りが入った状態等) は開発者メニューで作る。リモートでは `xcrun simctl` を使えないため、必要な操作が無ければ開発者メニューに追加してから検証する。ロケールの切り替えのようにアプリ起動前に効かせる設定は、`ios-wda.sh launch` の `--arg` (例: `--arg -AppleLanguages --arg '(ja)'`) で起動引数として渡す
  - simtunnel が使えない時 (Secrets 未登録・macOS Runner の並列上限・Maestro や XCUITest や `xcrun simctl` が検証の本体である手順) は、`/ios-simulator` skill Phase 1 の順で、余った Mac (`remote-mac check bannzai/quickbuy` が exit 0 なら `remote-mac`)、Devin の macOS セッションを試す。どちらも作業用の Mac の外で動く
  - ホーム画面へのウィジェットの配置と「カートイン」も simtunnel の `ios-wda.sh` で確かめる (2026-11-19 に iPhone 17・iOS 26.5 の simulator で、小・中・大サイズの配置、通知の許可の前後の表示、「カートイン」から確認の通知が届き、通知のタップで Safari に店のドメインが開くところまで実測。https://github.com/bannzai/quickbuy/issues/33 )。座標は毎回 `elements` で取り直す
    1. `button home` の後、ホーム画面のアイコンの無い所を `longpress <x> <y> 2000` し、左上の「Edit」、続けて「Add Widget」を `tap` する。長押しから「Edit」の `tap` までに間が空くと編集の状態が解けるので、続けて実行する
    2. ウィジェットの一覧は開いた直後は空のままなので、検索欄を `tap` して `keys Quick` と入れ、出てきた「Quick Buy」の行を `tap` する
    3. 小サイズが最初に出る。中サイズ・大サイズは左へ `swipe` して切り替える。「Add Widget」を `tap` し、`button home` で編集の状態を終える
    4. お気に入りが入った状態は、アプリの開発者メニューの「見本のお気に入りを入れる」で作る。ホーム画面に戻るとウィジェットに並ぶ。通知の許可は、開発者メニューの「先頭のお気に入りの通知を 5 秒後に出す」で出る許可の確認に「Allow」と答えて作る。許可の前のウィジェットは「カートイン」の代わりに「カートインには通知の許可が要ります」を出す
    5. 行の「カートイン」を `tap` すると、アプリが開かずに「購入画面を開きますか？」のバナーが出る。バナーは数秒で消え、消えた後の `tap` はバナーの下のウィジェットに当たってアプリの一覧が開く (購入画面は開かない)。「カートイン」の `tap`、`elements` で `NotificationShortLookView` が出るまで待つ、その `rect` の中心を `tap` する、をモデルの手番を挟まない 1 つのスクリプトで続けて行う。結果は数秒待ってから `shot` で Safari の URL 欄の店のドメインを見る。Safari を開いた直後の `elements` は 60 秒で時間切れになったので、タップの結果は `shot` で確かめる
    6. 通知センターは `swipe 120 1 120 600 500` で開き、`elements` の `NotificationShortLookView` の数で、同じお気に入りの「カートイン」を続けて押しても確認の通知が 1 つのままかを数える。通知センターの通知への `tap` は左へずらす操作になって「Open」が出るだけで、「Open」の `tap` でもアプリは開かなかった (2026-11-19 に、アプリを裏に置いた状態で試した。原因は確かめていない)。通知センターに残った通知のタップで購入画面が開くかは、アプリが裏にある時も起動していない時も simtunnel では未検証。通知のタップの確認はバナーで行う
- ブラウザの動作確認 (`docs/` の紹介ページ・法務ページ、購入画面の URL の遷移): `/webtunnel` skill (GitHub Actions の Linux Runner 上の Chromium) で行う。ローカルのブラウザを起動しない
  - 起動: 検証対象のブランチを push してから `WEBTUNNEL_REPO=bannzai/quickbuy bash ~/.agents/skills/webtunnel/scripts/webtunnel-cli.sh up <セッション名> --ref <ブランチ> --wait` で起動する (`--ref` を省略すると main の HTML が配信される)。caller workflow は `.github/workflows/browser-session.yml`、セッション名は `quickbuy-<worktree 名>` (例: `quickbuy-issue-10`)。対象のブランチが `browser-session.yml` を含まない時は、先に main を取り込む
  - 開く URL: Runner がリポジトリのルートを `http://localhost:8080/` で配信する。紹介ページは `http://localhost:8080/docs/index.html`、デザインのモックは `http://localhost:8080/documents/design/<モックのディレクトリ>/index.html`。`WEBTUNNEL_REPO=bannzai/quickbuy bash ~/.agents/skills/webtunnel/scripts/webtunnel-cli.sh cdp <セッション名>` が出す CDP の URL に `agent-browser --cdp <CDP の URL> open <開く URL>` で接続して開き、`agent-browser --cdp <CDP の URL> screenshot ./tmp/<名前>.png` で撮って Read で見る
  - 閉じる: `WEBTUNNEL_REPO=bannzai/quickbuy bash ~/.agents/skills/webtunnel/scripts/webtunnel-cli.sh down <セッション名>` (確認が終わったら閉じる)
  - 法務ページ (`docs/Terms-ja.md`・`docs/PrivacyPolicy-ja.md`) は GitHub Pages が Markdown から HTML にするため、この配信では HTML にならない。GitHub Pages で公開した後に、公開された URL を同じセッションで開いて確かめる
  - public リポジトリのため、Actions のログと録画は公開される。公開できない内容は開かない
- Android: 未着手。着手する時は、ビルド・ユニットテストを GitHub Actions の Linux runner で行い、emulator での確認も外部のマシンで行う方法を先に確立してこの項に書く (2026-11-17 時点で、`~/.claude/scripts/skill-lookup` で Android の emulator を扱う skill は見つからなかった)
- 外部のマシンがどれも使えない時は、作業用の Mac での実行に黙って切り替えない。その検証を未検証として、何にブロックされたかを完了報告 (PR があれば PR body) に書く。作業用の Mac で実行するのは owner が明示した時だけにする
- `make` (既定 target `ios`) は、人が手元で触って確かめるための入口として残す。agent は実行しない

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
