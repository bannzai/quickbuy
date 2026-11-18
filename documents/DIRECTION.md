---
status: building          # evaluating | building | launched | pivoting | retiring | retired
decision_date:            # 次の判定日 (YYYY-MM-DD)。公開したら公開日 + cycle_days を入れる
cycle_days: 14            # 判定の周期 (7 または 14)
veto_wait_hours: 12       # 公開後の無人ループの拒否権の待ち時間 (既定 12)
daily_issue_cap: 3        # 1 日に生成してよい改善 issue の上限 (既定 3)
launched_at:              # 公開日 (YYYY-MM-DD)。公開前は空
---

# 方向性: Quick Buy

## 仮説

同じ商品を定期的に買いたいが、定期便や AI による自動購入には、購入の時に不安がある人が、いつもの商品が切れそうな時に、店を開いて商品を探してカートに入れる手間を面倒に感じている。お気に入りにした商品をアプリの一覧とホーム画面のウィジェットに並べ、「カートイン」を押して確認に答えると商品がカートに入った状態の購入画面が開くことで、「自分で決めるが、決めた後は探さずに買える」にする (「カートイン」と確認を挟む流れは 2026-11-18 の bannzai の判断。それに合わせた言い直しは agent)。リマインドが、買うことを思い出すきっかけになる。支払いの確定は毎回本人が行う (出典: https://github.com/bannzai/IdeaMemo/issues/398 、評価レポート `documents/research/2026-11-17/report.md`。対象の人の言い方とリマインドは 2026-11-17 の bannzai の判断)。

## 判定基準

しきい値は実測の裏付けが無い仮の値 (評価レポートの「撤退・継続の基準」と同じ)。計測元の指標は、計測と bannzai/dashboard への収集を入れた後に読めるようになる。

| 指標 | 計測元 (skill / コマンド) | 継続のしきい値 | 打ち切り条件 | 転換の条件 |
| --- | --- | --- | --- | --- |
| 直近 14 日に購入画面を 1 回以上開いた利用者数 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open --field users --days 14 --agg sum` の `VALUE` | >= 10 | < 3 x2 (2 回連続) | 新規の利用者は 10 人以上いるのに開いた利用者が 3 人未満なら、お気に入りを登録する入口を作り直す |
| 直近 14 日の新規の利用者のうち、ウィジェットを置いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric widget_adoption --field rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | ウィジェットは置かれないがアプリの中から開かれているなら、通知・アプリ内の一覧を主な入口に替える |
| 購入画面を開いた利用者のうち、次の 14 日にも開いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open_retention --field d14_rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | 1 回しか開かれないなら、対象を「毎月買う消耗品」に絞った案内に替える |

## 必要な機能

作るかの判断 (https://github.com/bannzai/quickbuy/issues/2 ) で、2026-11-17 に bannzai が決めたのは、作ること・お気に入りの型・「いつものセット」を作らないこと・リマインドを入れること (下の「決めたこと」)。2026-11-18 に、Amazon を最初の版に入れること・計測に Firebase を使うこと・体験の流れ (トップページの検索から「お気に入り追加」、一覧の「カートイン」、確認の後に購入画面) を決めた。

最初の版 (iOS。検索 → お気に入り → カートイン (アプリとウィジェット) → 購入画面):

- [ ] お気に入りを端末内に保存する。一覧・名前と個数の変更・並べ替え・削除。型は `documents/data-structure/favorite-2026-11-17.html`
- [ ] トップページ: 通常の EC のように、検索窓と画像つきの商品を並べる。検索した商品から「お気に入り追加」に進む。検索するのは Shopify の店の商品で、Shopify の Catalog (店をまたぐ検索は Global Catalog `https://catalog.shopify.com/api/ucp/mcp`、選んだ商品の種類の一覧は店ごとの入口 `https://{店のドメイン}/api/ucp/mcp`) を、鍵なしでアプリから直接呼ぶ。最初の版では API キーの発行は要らない。Amazon の商品は、最初の版では検索にもトップページにも出さない (Amazon の検索の API の Creators API は、Amazon が承認したモバイルアプリと、鍵を置く自分のサーバーが要り、公開の前には満たせない)。検索の前に並べる物の候補は、買い直す物の検索語・選んだ店の商品・決まった検索語の結果で、人気の順を返す API は Shopify の Catalog の文書に見つからなかった。どれを並べるかはトップページの実装の issue で決める (出典・実測・未確認の点: `documents/research/2026-11-18/search-api-and-amazon-purchase-url.md`)
- [ ] お気に入りの追加: 種類 (商品バリアント) と個数を選ぶ。種類ごとにお気に入りの行を 1 つ作る。商品ページの URL か店が配る追加リンクを、貼り付けるか共有メニューから渡すこともできる。登録の画面で店のドメインを目立つ形で見せ、利用者が確かめて登録の操作をしたものだけを保存する (ADR 0003)
- [ ] 購入画面を開く: Shopify の店は cart permalink。組み立ての関数 (`Shared/ShopifyCartPermalink.swift`) は商品バリアントの ID を文字列で受け取り、数字だけでない ID では URL を組み立てない。Amazon は最初の版に入れる (アソシエイトのアカウントは bannzai が持っている。アプリにリンクを置くための承認の条件は `documents/research/2026-11-17/monetization.md`)。Amazon で「カートイン」の確認の後に開くのは商品ページ `https://www.amazon.co.jp/dp/{ASIN}` で、アプリの中の WebView を使わず、アプリの外 (Safari か Amazon のアプリ) で開く。開いた時に商品はカートに入っておらず、利用者が Amazon の画面でカートに入れる。最初の版では、カートに入れる URL (`/gp/aws/cart/add.html`) を使わない (現行の公式文書に無く、アソシエイトの ID を付けないと空のカートへ送られる)。アソシエイトの ID は、Amazon がアプリを承認するまで付けない (承認の申請にはストアの URL が要り、申請は公開の後になる)。Amazon の商品は、商品ページの URL を貼り付けるか共有メニューから渡して登録する。Amazon の商品を検索して画像つきで並べる画面は、承認の条件「Amazonのショッピングアプリの機能をエミュレート、偽装またはその機能と競合しないこと」に当たる読みが強く、検索の API も公開の前には使えないため、最初の版に入れない。承認の前のアプリに Amazon へのリンクを置いてよいかは Amazon に確かめておらず、bannzai が公開の前に問い合わせる (出典・未確認の点・問い合わせる内容: `documents/research/2026-11-18/search-api-and-amazon-purchase-url.md`)。一覧の「カートイン」を押すと「購入画面を開きますか？」のトーストを出し、利用者が開く操作をした時に購入画面を開く
- [ ] ホーム画面のウィジェット: お気に入りを種類ごとの行で並べ、行の「カートイン」を押すと「購入画面を開きますか？」の通知を出す。通知をタップすると購入画面を開く
- [ ] 通知の許可: 最初のお気に入りを追加した後に、なぜ通知が要るのか (ウィジェットからの確認・買う頃の知らせ) を説明してから許可を求める (出す時機は agent の案)
- [ ] リマインド: お気に入りごとに「何日ごとに知らせるか」を設定し、端末の通知で知らせる。通知をタップすると、その商品の購入画面が開く。日数は購入画面を開いた時刻から数え直す (数え方と通知をタップした時の動きは agent の案)
- [ ] 設定画面: お問い合わせ・利用規約・プライバシーポリシー・アフィリエイトのリンクを含むことの表示
- [ ] 開発者メニュー (DEBUG ビルドだけ): 見本のお気に入りを入れる・消す
- [ ] 計測とクラッシュ収集: 購入画面を開いた・ウィジェットを置いた、を数える (Firebase Analytics・Crashlytics・bannzai/dashboard への収集)
- [ ] 多言語化 (日本語・英語) とストアの素材

その後:

- [ ] 自分のサーバーを経由する URL (ブックマークできる・中身の商品を後から変えられる・経由した回数を数える)
- [ ] 相性の良い商品の一覧 (トップページに足す) と、店の表示枠
- [ ] 店向けの無料 Shopify アプリ (「Quick Buy に入れる」ボタン・追加リンク・QR)
- [ ] Android 版 (Kotlin・Glance)
- [ ] 楽天の商品 (アフィリエイトのリンクで商品ページを開くところまで)

## デザインの方向

bannzai の返答 (2026-11-18。https://github.com/bannzai/quickbuy/issues/8#issuecomment-6966345862 ): 通常の EC のようなトップページにする。商品の画像を出し、タイトルをのっぺりさせない。トップページに検索窓を置く。

この返答で作り直したモックは `documents/design/mock-2026-11-18/`。色・余白・書体はこのモックを bannzai に見てもらって決める (https://github.com/bannzai/quickbuy/issues/8 )。1 つ前の `documents/design/mock-2026-11-17/` は採らない。

## 決めたこと

| 日付 | 場面 | 決めたこと | 決めた人 |
| --- | --- | --- | --- |
| 2026-11-16 | 立ち上げ設定 | リポジトリ名は quickbuy、公開設定は public、配信先は iOS (SwiftUI) + Android (Kotlin) のストア配布 (https://github.com/bannzai/IdeaMemo/issues/398#issuecomment-6932881903 ) | bannzai |
| 2026-11-17 | 立ち上げの依頼 | ビルド・simulator・ブラウザの動作確認は作業用の Mac で行わず、外部のマシン (public の間は simtunnel / GitHub Actions、private になったら Devin) で行う | bannzai |
| 2026-11-17 | 立ち上げ | 購入画面は決まった形の URL で開き、支払いの確定は毎回本人が行う。EC サイトのログイン情報を預からない (企画の「採らない方式」を ADR 0003 に記録) | agent |
| 2026-11-17 | 立ち上げ | 最初の版はお気に入りを端末内 (アプリとウィジェットが共有する領域) に持ち、サーバーとログインを持たない (ADR 0001) | agent (変えにくい面) |
| 2026-11-17 | 立ち上げ | Xcode プロジェクトは `QuickBuy.xcodeproj` を直接管理し、XcodeGen を使わない (ADR 0002)。bundle ID は `com.bannzai.QuickBuy` | agent |
| 2026-11-17 | 作るかの判断 (お気に入りの型) | 商品バリアントの ID は文字列で持つ。`Product` の各 case は、struct で定義した型 (`ShopifyProduct`・`AmazonProduct`) を持つ | bannzai |
| 2026-11-17 | 作るかの判断 (必要な機能) | 店ごとの「いつものセット」は作らない。同じ店でも同じタイミングで買いたいとは限らず、商品ごとに購入画面を開けば足りるため | bannzai |
| 2026-11-17 | 作るかの判断 (必要な機能) | リマインドを入れる。対象は、定期便や AI による自動購入には購入の時に不安があるが、定期的に買いたい人で、リマインドが買うことを思い出すきっかけになるため | bannzai |
| 2026-11-17 | 作るかの判断 (リマインドの型) | リマインドは「何日ごと」と「日数を数え始めた日時」を持ち、購入画面を開いた時刻から数え直す。通知をタップすると購入画面を直接開く。通知は端末の中だけで予約する | agent (変えにくい面) |
| 2026-11-17 | 作るかの判断 | 作る (https://github.com/bannzai/quickbuy/issues/2#issuecomment-6947809876 ) | bannzai |
| 2026-11-17 | お気に入りの保存の実装 (https://github.com/bannzai/quickbuy/issues/9 ) | お気に入りは App Group `group.com.bannzai.QuickBuy` の領域の `favorites.json` に、`[Favorite]` を Swift の `Codable` の自動合成の形の JSON で保存する (`Product` は `{"shopify":{"_0":{…}}}` の入れ子、日時は 2001-01-01 00:00:00 UTC からの秒数)。形は `QuickBuyTests/FavoriteStoreTests.swift` の「保存済みのJSONの形を読める」で固定する。公開前なので、形を変える時は移行を書かずに変えられる | agent (変えにくい面) |
| 2026-11-18 | 作るかの判断 (上の 2026-11-17 の 4 つの確認) | お気に入りの型・「いつものセット」を作らない・リマインドを入れる・対象の人の言い方でよい (https://github.com/bannzai/quickbuy/issues/2#issuecomment-6966340254 ) | bannzai |
| 2026-11-18 | 作るかの判断 (Amazon の扱い) | Amazon を最初の版に入れる。アソシエイトのアカウントは持っている (https://github.com/bannzai/quickbuy/issues/2#issuecomment-6966342865 ) | bannzai |
| 2026-11-18 | 作るかの判断 (計測) | 計測に Firebase を使い、agent が Firebase のプロジェクトを作る。agent の問いは「計測に Firebase を使い、agent が Firebase のプロジェクトを作ってよいか」で、同じ返答の「入れる」を、Amazon と並べて聞いたこの問いにもかかると agent が読んだ (https://github.com/bannzai/quickbuy/issues/2#issuecomment-6966342865 ) | bannzai (Firebase にもかかるという読みは agent) |
| 2026-11-18 | 見た目と体験の方向の判断 | トップページは通常の EC のようにし、検索窓を置く。検索から「お気に入り追加」、お気に入り一覧に「カートイン」ボタン、トーストの「購入画面を開きますか？」の後に購入画面。ウィジェットからは通知で確かめる。通知の許可をこの流れの中で求め、なぜ要るのかを説明する。お気に入りは個数と種類 (商品バリアント) を決められ、種類ごとに行を分ける (https://github.com/bannzai/quickbuy/issues/8#issuecomment-6966345862 ) | bannzai |
| 2026-11-18 | 見た目と体験の方向の判断 (ウィジェット) | 「Widgetからならプッシュ通知」は、ウィジェットからはトーストを出せないため、同じ確認を通知で出すことと読む。通知の許可の説明は、最初のお気に入りを追加した後に出す | agent |
| 2026-11-18 | 検索の API と Amazon で開く URL の調査 (https://github.com/bannzai/quickbuy/issues/27 ) | Shopify の商品の検索は、Shopify の Catalog を鍵なしでアプリから直接呼ぶ。最初の版はサーバーを持たず、client secret はアプリに埋め込めないため。鍵なしの上限に当たった時は、自分のサーバーに鍵を置く形へ移る (根拠: `documents/research/2026-11-18/search-api-and-amazon-purchase-url.md`) | agent |
| 2026-11-18 | 検索の API と Amazon で開く URL の調査 (https://github.com/bannzai/quickbuy/issues/27 ) | 最初の版の Amazon は、商品ページの URL から登録し、「カートイン」の確認の後に商品ページ `https://www.amazon.co.jp/dp/{ASIN}` をアプリの外で開く。開いた時に商品はカートに入っていない。カートに入れる URL と、Amazon の商品の検索・Amazon が持つ名前・画像・価格の表示は入れない。アソシエイトの ID は、Amazon がアプリを承認するまで付けない。承認の前のアプリにリンクを置けないと Amazon が答えた時は、Amazon を入れる時期を bannzai が決め直す (根拠: 同じ文書) | agent (変えにくい面) |

## agent に任せること

文書に無い問いはすべて。画面構成・文言・ライブラリの選定・テストの方針を含む。次は任せず、bannzai が決める・行う。

- Amazon アソシエイトのアプリの承認の申請、Shopify・Amazon の商品を検索する API のキーの発行 (外部サービスとの新規の連携)。Firebase のプロジェクトの作成は 2026-11-18 の返答で agent が行う
- 自分のサーバーを持つ時の費用の上限
- 公開に進むか

## 費用

| 項目 | 値 |
| --- | --- |
| 月間売上の取得元 | |
| インフラ費用の取得元 | `echo 0` |
| 固定費の月額上限 (USD) | 0 |

最初の版はサーバーを持たないため、インフラ費用は 0 で、固定費の上限も 0 にしている。サーバーを持つ時に、取得元を費用を取るコマンドへ書き換え、上限を bannzai が決める。

## 用語

| 用語 | 定義 | 使わない言い換え |
| --- | --- | --- |
| お気に入り | 利用者が「また買う」ために登録した 1 つの商品。店・商品・個数を持つ | ブックマーク・ウィッシュリスト・欲しいもの |
| 店 | 商品を売っている Shopify のストアと EC サイト (Amazon 等) | ショップ・マーチャント・ストア |
| 購入画面 | 店の側の画面で、商品がカートに入った状態から支払いの確定までを行う画面。Quick Buy が開くのはここまで | チェックアウト・決済画面・カート画面 |
| リマインド | お気に入りごとに設定した日数が過ぎた時に、買う頃だと端末の通知で知らせること | リマインダー・アラート・定期通知 |
| 追加リンク | 店が配る、その店の商品を Quick Buy のお気に入りに入れるためのリンクや QR | ディープリンク・招待リンク |
| 経由 URL | 自分のサーバーの URL で、開かれた時に店の購入画面へ送るもの。中身の商品を後から変えられる | 短縮 URL・リダイレクト URL |
