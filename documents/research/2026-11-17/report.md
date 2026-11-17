# Quick Buy の評価レポート

## 結論

**作る**

決め手は、必須の観点 (需要・マネタイズ) に × が無いこと。ただしどちらも △ で、マネタイズは Amazon のアプリ審査に通ることと、利用者数が未判定であることに依っている。「同じものを買い直す」行動は大手 EC のレビューで確かめられ、複数の店の商品をウィジェットからカートに入った状態で開くアプリは調べた範囲に無かった。一方、同種のアプリは評価 0〜88 件で、ウィジェットから買いたいという利用者の言葉は 1 件も見つかっていない。

- 作り手の目的: 収益 (未確認時の仮定。入力の issue に「収益」の節があるため、evaluation-criteria.md の仮定ルールで「収益」を置いた。目標月間収益は issue の試算に出てくる月 10 万円を使った)
- 判定日: 2026-11-17
- 入力: https://github.com/bannzai/IdeaMemo/issues/398

## 前提と仮説

- 誰の: 同じ商品を繰り返し買うが、間隔が決まっておらず定期購入を契約したくない人。AI に任せて勝手に買われるのは避けたい人
- どの場面の: いつもの商品が切れそうな時に、店を開いて商品を探してカートに入れる場面
- どの痛みを: 毎回探してカートに入れる手間
- 何で解決するか: お気に入りにした商品をホーム画面のウィジェットに並べ、タップすると商品がカートに入った状態の購入画面が開く。支払いの確定は毎回本人
- 今の代替手段: 店・EC のアプリの購入履歴やお気に入りから買い直す (Amazon の「再び購入」、楽天の購入履歴、LOHACO のお気に入り)、定期購入のスキップ、ブラウザのブックマーク、iOS のショートカット App で URL をホーム画面に置く
- 仮定した数値: 目標月間収益 10 万円 (issue の試算の値)、注文 1 回あたり 3,000 円 (仮定。公的な統計は見つからなかった)、購入画面を開いた回のうち購入に至る割合 30% (仮定。実測値は無い)、料率は Amazon アソシエイトの 5%・8% と Shopify の promoted placements の 0.3% (出典は下)

## 観点別の根拠

| 観点 | 事実 (出典付き) | 判定 | 判定が変わる条件 |
| --- | --- | --- | --- |
| 需要 | 大手 EC は評価件数が大きい (Amazon JP 718,642 件、楽天市場 5,205,075 件、Shop は US 7,256,260 件・JP 10,547 件)。再購入に絞った同種アプリは 0〜88 件 (リピかご 0 件・2026-07 公開、リピコ 0 件・2026-08 公開、ショッピングリズム 48 件・2026-10 公開、Stockn 88 件・2019 公開)。レビューでは「履歴・お気に入りから買い直す」使い方と、その動線が消えた時の不満が確かめられた (LOHACO 2021〜2023、Amazon US 2026-11)。「ウィジェットから買いたい」という要望は取得したレビューに 0 件。出典: appstore-research の実測 (`demand-appstore.md`) | △ | 公開後 28 日で、購入画面を 1 回以上開いた利用者が 10 人に届けば ○。ショッピングリズムのように公開 1 か月で数十件の評価が付く同種アプリが増えれば ○。公開後 28 日で 3 人未満が 2 回続けば × |
| 競合・代替 | 1 社の中の再購入は埋まっている (Amazon の Buy Again、Instacart の Buy it again、Shopify の店の Buy again ボタン、Shopify App Store の再注文アプリ多数)。汎用の手段でも、cart permalink は使い回せる URL で、iOS のショートカット App でホーム画面に置ける。物理の Amazon Dash Button は 2019-08-31 に終了し、Amazon は再注文を自社アプリの中と定期購入に移した。複数の店の商品をウィジェットからカートに入った状態で開くアプリは、調べた範囲 (iTunes Search の日米・各語の上位 10 件、Web 検索) では見つからなかった (競合がいないことの証明ではない)。Shopify は Shop アプリのお気に入り・Global Catalog・Product Network を持ち、同じ機能を足せる。出典: `competitors.md` | △ | Shop アプリか Amazon アプリが再購入のウィジェットを出したら ×。Shop アプリに再購入の動線があるかは食い違う情報があり未確認 |
| マネタイズ | 払う主体は、紹介料を払う Amazon (食品・飲料 8%、ドラッグストア・ビューティー・ペット用品 5%、生活雑貨・キッチン用品 3%) と Shopify (promoted placements 0.3%、招待制の Developer Preview)、将来は表示枠を買う店。消費者は払わない。試算 (estimate-monetization.sh、注文 3,000 円・開いた回の 30% が購入の仮定): 5% なら 1 回開くごとに 45 円で月 10 万円に 2,223 回・667 件の購入、8% なら 1,389 回・417 件、0.3% なら 37,038 回・11,112 件。Amazon のリンクをアプリに置くには Amazon の審査での承認が要り、条件に「Amazon のショッピングアプリの機能を模倣しない」がある。承認が無いアプリのリンクは禁止で、紹介料も対象外。到達可能性は未判定 (月間の利用回数を示す絶対の数値が無い)。出典: `monetization.md` | △ | Amazon のアプリの承認が得られ、月 667 件の購入に届く利用者数 (1 人が月 2 回買うなら約 330 人) が見えれば ○。承認が得られず、Shopify の招待も来なければ、紹介料の経路が無くなり × |
| 実現性・制約 | 最初の版 (端末内に保存し、決まった形の URL を開く) はサーバー無しで作れる。制約: (1) iOS のウィジェットのタップは自分のアプリに渡り、アプリが店の URL を開く経路になる (Apple の文書からの推論。実機では未確認) (2) Shopify の従来の cart permalink は legacy で、後継の `/buy` は店の `/.well-known/ucp` から endpoint を読む (3) Amazon は WebView での表示・リダイレクトのリンク・印刷物での利用・価格の追跡を規約で禁じ、運営者本人と近しい人がリンク経由で買うことも禁じている (4) Amazon の商品情報の API は過去 30 日に 10 件以上の売上が要る (5) Shopify の Global Catalog に日本の店が入っているかは未確認。出典: `feasibility.md` | △ | ウィジェットから購入画面まで 2 タップ以内で開けることを実機で確かめられれば、最初の版は ○。Amazon の審査が「模倣」を理由に通らなければ、Amazon を対象から外す |
| 作り手の文脈 | bannzai の既存の案「Shopify Dash Button」(IdeaMemo #67) と同じ方向で、ウィジェットを持つ iOS アプリ (mementomorning・Alarmify) を出している。自分が対象の人に当たる | ○ | - |

需要とマネタイズはつながっている。紹介料は利用者の購入額に比例し、Shopify の 0.3% だけでは月 10 万円に月 3,300 万円の経由の購入が要る。Amazon の 5〜8% が現実的な柱だが、Amazon の審査と規約が設計を縛る。知見文書 (`~/.claude/documents/guides/product-lessons.md`) の「打ち切った試作と理由」に、同じ仮説・同じ市場の打ち切りは無かった。

## 撤退・継続の基準

公開後の判定基準の下書き。しきい値は実測の裏付けが無い仮の値で、作るかの判断の時に直してもらう。計測元の指標は、計測 (Firebase Analytics) と bannzai/dashboard への収集を入れた後に読めるようになる。

判定日の周期: 14 日

| 指標 | 計測元 (skill / コマンド) | 継続のしきい値 | 打ち切り条件 | 転換の条件 |
| --- | --- | --- | --- | --- |
| 直近 14 日に購入画面を 1 回以上開いた利用者数 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open --field users --days 14 --agg sum` の `VALUE` | >= 10 | < 3 x2 (2 回連続) | 新規の利用者は 10 人以上いるのに開いた利用者が 3 人未満なら、お気に入りを登録する入口を作り直す |
| 直近 14 日の新規の利用者のうち、ウィジェットを置いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric widget_adoption --field rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | ウィジェットは置かれないがアプリの中から開かれているなら、通知・アプリ内の一覧を主な入口に替える |
| 購入画面を開いた利用者のうち、次の 14 日にも開いた人の割合 | `bash ~/.agents/skills/product-loop/scripts/read-dashboard-metric.sh --repo bannzai/quickbuy --metric purchase_open_retention --field d14_rate --days 14 --agg avg` の `VALUE` | >= 0.3 | < 0.1 x2 | 1 回しか開かれないなら、対象を「毎月買う消耗品」に絞った案内に替える |

## 最安の検証実験

| 実験 | 測るもの | 合格ライン | 費用・期間 |
| --- | --- | --- | --- |
| iOS のショートカット App で、いつも買う商品の cart permalink と Amazon のカートに入れる URL を開くショートカットを自分のホーム画面に置いて使う | 2 週間で、そこから開いて購入を確定した回数。在庫切れ・既存のカートがある時の動き | 2 回以上買い、探してカートに入れるより楽だと感じる | 0 円・2 週間 |
| Shopify の Dev Dashboard で Catalog の API キーを発行し、日本の店の商品を検索する (issue の「最初に作る範囲」の 1) | 日本の店の商品が結果に出るか | いつも買う店の商品が 1 つ以上出る | 0 円・1 日 |
| Amazon アソシエイトに、ウィジェットから add-to-cart の URL を開くアプリが「承認モバイル・アプリ」になり得るかを問い合わせる | 「模倣しない」「独自のコンテンツ」の条件に当たるかの回答 | 承認の見込みがあるという回答 | 0 円・回答待ち |

## 数値の単位と出典

- 評価件数は App Store の累積の評価件数 (iTunes Lookup API の `userRatingCount`)。月間の利用者数ではない。取得日 2026-11-17、ストアの国は表に書いた。レビューは RSS の直近最大 500 件で、全期間ではない。Google Play は調べていない
- Amazon アソシエイトの紹介料率: 「アソシエイト・プログラム紹介料率表 別紙」 https://affiliate.amazon.co.jp/help/node/topic/GRXPHT8U84RAYDXZ (2026-11-17 取得)
- Amazon のモバイルアプリの条件・クライアント側のソフトウェアの禁止・運営者本人の購入の禁止: プログラム・ポリシー https://affiliate.amazon.co.jp/help/operating/policies (2026-11-17 に原文を 2 回取得して照合。「Amazonのショッピングアプリの機能を模倣（エミュレート）しないこと」「甲は、乙のアプリケーションを審査し、参加の可否を通知します。」)
- Shopify の promoted placements: https://shopify.dev/docs/agents/catalog/promoted-placement (「0.3% (30 bps) on attributed purchases of eligible products.」「Access to promoted placements is limited and invite-led during Developer Preview.」)
- Shopify の cart permalink: https://shopify.dev/docs/apps/build/checkout/create-cart-permalinks (「Cart permalinks are a legacy feature.」)。後継: https://shopify.dev/docs/agents/carts-and-checkout/permalinks
- iOS のウィジェットのタップ: https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity (「the system activates the containing app and passes the URL」)。ウィジェットから Safari を直接開けないことは文書からの推論で、実機では確かめていない
- 物理の Amazon Dash Button の終了: https://www.watch.impress.co.jp/docs/news/1199661.html (2019-08-02 の報道)
- 注文 1 回あたり 3,000 円と、開いた回の 30% が購入に至るという値は仮定。公的な統計・実測値は無い。ネットショッピングを利用した世帯の割合は 54.6% (総務省 家計消費状況調査、2026 年 9 月分、二人以上の世帯)
- 試算は `estimate-monetization.sh affiliate --rate <5|8|0.3> --unit-price 3000 --cvr 30 --target 100000` の出力
- 調査の全文: 同じディレクトリの `competitors.md`・`monetization.md`・`feasibility.md`・`demand-appstore.md`

## ユーザーが判断する事項

- 作るか (作る / 作らない)。元の案のほかに、懸念を小さくする選択肢として、Amazon の審査の結果が出るまで Amazon を対象から外して Shopify の店だけで始める、がある
- 費用の許容: 最初の版はサーバー無しで費用は発生しない。自分のサーバーを経由する URL を作る段階でホスティングの費用が出る
- 外部サービスとの新規連携の可否: Amazon アソシエイト (アプリの承認の申請)、Shopify の Dev Dashboard (Catalog の API キー)、Firebase (計測)
- このレポートを元 issue (IdeaMemo #398) へコメントとして記録してよいか
