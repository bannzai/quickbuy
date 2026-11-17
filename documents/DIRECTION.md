---
status: evaluating        # evaluating | building | launched | pivoting | retiring | retired
decision_date:            # 次の判定日 (YYYY-MM-DD)。公開したら公開日 + cycle_days を入れる
cycle_days: 14            # 判定の周期 (7 または 14)
veto_wait_hours: 12       # 公開後の無人ループの拒否権の待ち時間 (既定 12)
daily_issue_cap: 3        # 1 日に生成してよい改善 issue の上限 (既定 3)
launched_at:              # 公開日 (YYYY-MM-DD)。公開前は空
---

# 方向性: Quick Buy

## 仮説

同じ商品を繰り返し買うが、間隔が決まっておらず定期購入は契約したくない人が、いつもの商品が切れそうな時に、店を開いて商品を探してカートに入れる手間を面倒に感じている。お気に入りにした商品をホーム画面のウィジェットに並べ、タップすると商品がカートに入った状態の購入画面が開くことで、「自分で決めるが、決めた後は 1 タップ」にする。支払いの確定は毎回本人が行う (出典: https://github.com/bannzai/IdeaMemo/issues/398 、評価レポート `documents/research/2026-11-17/report.md`)。

## 判定基準

しきい値は実測の裏付けが無い仮の値 (評価レポートの「撤退・継続の基準」と同じ)。計測元の指標は、計測 (Firebase Analytics) と bannzai/dashboard への収集を入れた後に読めるようになる。

| 指標 | 計測元 (skill / コマンド) | 継続のしきい値 | 打ち切り条件 | 転換の条件 |
| --- | --- | --- | --- | --- |
| 直近 14 日に購入画面を 1 回以上開いた利用者数 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open --field users --days 14 --agg sum` の `VALUE` | >= 10 | < 3 x2 (2 回連続) | 新規の利用者は 10 人以上いるのに開いた利用者が 3 人未満なら、お気に入りを登録する入口を作り直す |
| 直近 14 日の新規の利用者のうち、ウィジェットを置いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric widget_adoption --field rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | ウィジェットは置かれないがアプリの中から開かれているなら、通知・アプリ内の一覧を主な入口に替える |
| 購入画面を開いた利用者のうち、次の 14 日にも開いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open_retention --field d14_rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | 1 回しか開かれないなら、対象を「毎月買う消耗品」に絞った案内に替える |

## 必要な機能

作るかの判断 (https://github.com/bannzai/quickbuy/issues/2 ) で bannzai が過不足を判断する前の下書き。

最初の版 (iOS。お気に入り → ウィジェットのタップ → 購入画面):

- [ ] お気に入りを端末内に保存する。一覧・名前と個数の変更・並べ替え・削除
- [ ] お気に入りの追加: 商品ページの URL か店が配る追加リンクを、貼り付けるか共有メニューから渡す
- [ ] 購入画面を開く: Shopify の店は cart permalink、Amazon はカートに入れる URL
- [ ] ホーム画面のウィジェット: お気に入りを並べ、タップで購入画面を開く
- [ ] 店ごとの「いつものセット」: 同じ店のお気に入りを 1 つの URL にまとめて開く
- [ ] 設定画面: お問い合わせ・利用規約・プライバシーポリシー・アフィリエイトのリンクを含むことの表示
- [ ] 開発者メニュー (DEBUG ビルドだけ): 見本のお気に入りを入れる・消す
- [ ] 計測とクラッシュ収集: 購入画面を開いた・ウィジェットを置いた、を数える (Firebase Analytics・Crashlytics・bannzai/dashboard への収集)
- [ ] 多言語化 (日本語・英語) とストアの素材

その後:

- [ ] 自分のサーバーを経由する URL (ブックマークできる・中身の商品を後から変えられる・経由した回数を数える)
- [ ] アプリ内の検索 (Shopify の Catalog)
- [ ] 相性の良い商品の一覧 (最初の画面) と、店の表示枠
- [ ] 通知から購入画面を開く
- [ ] 店向けの無料 Shopify アプリ (「Quick Buy に入れる」ボタン・追加リンク・QR)
- [ ] Android 版 (Kotlin・Glance)
- [ ] 楽天の商品 (アフィリエイトのリンクで商品ページを開くところまで)

## デザインの方向

未定。主要画面のモックを見てもらって決める。

## 決めたこと

| 日付 | 場面 | 決めたこと | 決めた人 |
| --- | --- | --- | --- |
| 2026-11-16 | 立ち上げ設定 | リポジトリ名は quickbuy、公開設定は public、配信先は iOS (SwiftUI) + Android (Kotlin) のストア配布 (https://github.com/bannzai/IdeaMemo/issues/398#issuecomment-6932881903 ) | bannzai |
| 2026-11-17 | 立ち上げの依頼 | ビルド・simulator・ブラウザの動作確認は作業用の Mac で行わず、外部のマシン (public の間は simtunnel / GitHub Actions、private になったら Devin) で行う | bannzai |
| 2026-11-17 | 立ち上げ | 購入画面は決まった形の URL で開き、支払いの確定は毎回本人が行う。EC サイトのログイン情報を預からない (企画の「採らない方式」を ADR 0003 に記録) | agent |
| 2026-11-17 | 立ち上げ | 最初の版はお気に入りを端末内 (アプリとウィジェットが共有する領域) に持ち、サーバーとログインを持たない (ADR 0001) | agent (変えにくい面) |
| 2026-11-17 | 立ち上げ | Xcode プロジェクトは `QuickBuy.xcodeproj` を直接管理し、XcodeGen を使わない (ADR 0002)。bundle ID は `com.bannzai.QuickBuy` | agent |

## agent に任せること

文書に無い問いはすべて。画面構成・文言・ライブラリの選定・テストの方針を含む。次は任せず、bannzai が決める・行う。

- Amazon アソシエイトへの参加とアプリの承認の申請、Shopify の Dev Dashboard での Catalog の API キーの発行、Firebase のプロジェクトの作成 (外部サービスとの新規の連携)
- 自分のサーバーを持つ時の費用の上限
- 公開に進むか

## 費用

| 項目 | 値 |
| --- | --- |
| 月間売上の取得元 | |
| インフラ費用の取得元 | `echo 0` (最初の版はサーバーを持たないため 0。サーバーを持つ時に取得のコマンドへ書き換える) |
| 固定費の月額上限 (USD) | 0 |

## 用語

| 用語 | 定義 | 使わない言い換え |
| --- | --- | --- |
| お気に入り | 利用者が「また買う」ために登録した 1 つの商品。店・商品・個数を持つ | ブックマーク・ウィッシュリスト・欲しいもの |
| 店 | 商品を売っている Shopify のストアと EC サイト (Amazon 等) | ショップ・マーチャント・ストア |
| 購入画面 | 店の側の画面で、商品がカートに入った状態から支払いの確定までを行う画面。Quick Buy が開くのはここまで | チェックアウト・決済画面・カート画面 |
| いつものセット | 同じ店のお気に入りをまとめて 1 つの URL で購入画面に入れたもの | バンドル・まとめ買いセット |
| 追加リンク | 店が配る、その店の商品を Quick Buy のお気に入りに入れるためのリンクや QR | ディープリンク・招待リンク |
| 経由 URL | 自分のサーバーの URL で、開かれた時に店の購入画面へ送るもの。中身の商品を後から変えられる | 短縮 URL・リダイレクト URL |
