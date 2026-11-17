# Quick Buy の実現性・制約 (取得日: 2026-11-17)

「原文」と書いた引用は、ページの文をそのまま写したもの。それ以外は WebFetch の要約。

## Shopify の cart permalink

### 従来の cart permalink (/cart)

出典: https://shopify.dev/docs/apps/build/checkout/create-cart-permalinks

- 原文: 「Cart permalinks are a legacy feature. Use their successor, Cart and Checkout Permalinks」。サポートは続くが新機能は足さない
- 形: 「https://{shop}.myshopify.com/cart/#{variant_id}:#{quantity}(,...)」
- 定期購入: 原文「Selling plans don't work with cart permalinks」
- `discount`・`ref`・`attributes`・`note` を付けられる。`ref` は注文の詳細の Conversion summary に紹介コードとして出る
- 在庫切れの時の動き・既存カートを置き換えるか・有効期限: このページにも、ヘルプ https://help.shopify.com/en/manual/checkout-settings/cart-permalink にも記載が無い (未確認)。ヘルプの原文: 「The same link is reusable, and creates a new checkout for each customer.」

### 後継の Cart and Checkout Permalinks (/buy)

出典: https://shopify.dev/docs/agents/carts-and-checkout/permalinks 、変更履歴 https://shopify.dev/changelog/cart-and-checkout-permalinks-now-support-ucp-at-buy (2026-10-28)

- 形: `{variant_id}:{quantity}` をカンマで並べて endpoint の後ろに付ける。例 `https://{shop}.example.com/buy/70881412:1,70881382:2`
- endpoint は自分で組み立てず、店の `/.well-known/ucp` のプロフィールの `config.endpoint` から読む。変更履歴でも、自分で /buy を組み立てずに店のプロフィールから得るよう求めている。UCP の 2026-08-25 版から
- 既存カート: 原文「The new cart replaces any cart that the buyer already had on the store.」
- 在庫切れ: 原文「Shopify adds only the quantity that's available, or leaves the item out.」。ほかの理由で入れられない商品があると、原文「If Shopify can't add an item for any other reason, then it doesn't create the cart, even for the other items.」。その時は `continue_to` のパスかトップページへ送る
- 定期購入: 原文「Shopify adds every item as a one-time purchase, and ignores `line_items/{index}/selling_plan`.」定期購入が必須の商品はカートを作れない
- 有効期限: 記載なし。カートはリンクを開いた時に作られる (要約)
- 割引コードは `discounts/codes/{index}`。適用できなくてもカートは作られる
- 流入元: UTM・referrer・click ID・activity ID だけ。cart notes・cart attributes・line item properties・`ref`・sales channel の帰属は非対応で、それらが要る時は従来の /cart を使う
- 店のプロフィールに `dev.ucp.shopping.permalink` が無い店は /buy を受け付けない
- 作る・開くのに API キーやエージェントのプロフィールが要るという記載は無い

### 案への当てはめ (この調査の読み)

- 案の「URL を組み立てるだけ」は従来の /cart では成り立つ。/buy に移るなら、店ごとに `/.well-known/ucp` を 1 回読む必要がある
- 店向けの表示枠を成果報酬にする時の「経由の注文の数え方」に、`ref` (従来の /cart だけ) か UTM (/buy) のどちらを使うかが効く。Shopify の側でどう集計できるかは未確認

## Shopify の Global Catalog / Checkout MCP

出典: https://shopify.dev/docs/agents 、https://shopify.dev/docs/agents/get-started/authentication 、https://shopify.dev/docs/agents/profiles/auth-and-rate-limiting 、https://shopify.dev/docs/agents/catalog/global-catalog 、https://shopify.dev/docs/agents/carts-and-checkout/checkout-mcp

- 概要: 原文「Search products across every Shopify merchant from a single endpoint.」「Search across hundreds of millions of Shopify listings.」
- API キーの取得: Dev Dashboard の「Catalogs」→「Get an API key」で client ID と client secret を得る。前提は「Access to Shopify's Dev Dashboard」。審査・順番待ちの記載は無い。トークンは 60 分で切れる
- 認証の段階: Token (Dev Dashboard の資格情報)、Signed (UCP の HTTP 署名)、Anonymous の 3 段階。Global Catalog の既定の上限は原文「The default limit is 5 requests each second for each API client」。認証なしの利用は原文「Don't use unauthenticated requests for production traffic.」。上限を上げるには Shopify の担当者かヘルプセンターに、想定の通信量と理由を添えて連絡する
- Token の段階で店の endpoint を呼ぶ時は `Shopify-Buyer-IP` ヘッダーが要る。`complete_checkout` は購入完了の許可が付いたトークンだけ
- Checkout MCP: 一般の利用では `continue_url` に購入者を送り、`complete_checkout` は呼ばない。原文「continue_url gives access to the buyer's checkout, so share it only with that buyer, and don't log it.」。`create_checkout` は `currency`・`line_items`・`buyer` が必須で、buyer にはメールアドレスか電話番号が要る (店の設定による)
- Global Catalog の endpoint `/api/ucp/mcp` はエージェントのプロフィール (UCP profile の URL) が必須
- 対象の店の範囲: 日本の店が含まれるかの記載は見つからなかった (未確認)。`ships_to` に国コード (ISO 3166-1 alpha-2) を、`ships_from` に店の国を指定するフィルターはある
- 料金: どのページにも記載が無い (未確認)
- Catalog 専用の規約: 取得したページから規約へのリンクは無かった。Partner Program Agreement と API License and Terms of Use は 2026-01-29 に「to support the launch of agentic commerce」として改定が告知され、2026-02-27 に発効 (https://help.shopify.com/en/partners/ppa-api-faq)。その FAQ に Catalog の言及は無い。店向けの「Agentic Storefronts Supplemental Terms of Service」(https://www.shopify.com/legal/terms-agentic-storefronts) は存在を検索で確認したが本文は未取得で、これは店が守る規約。開発者向けの Catalog 専用の規約は見つからなかった (存在しないとは確かめていない)

### 案への当てはめ (この調査の読み)

- `create_checkout` を使うと、利用者のメールアドレスか電話番号と IP アドレスを自分のサーバーから Shopify に渡すことになり、個人情報を扱う
- 日本の店が入っているかは、案の「最初に作る範囲」の 1 番のとおり、API キーを発行して試すまで分からない

## Shopify API License and Terms of Use

出典: https://www.shopify.com/legal/api-terms (最終更新 2026-10-07)。以下は原文 (分けて取得した断片を順に並べた)

- 2.3.10: 「not, except as authorized by Shopify in writing, use Shopify Confidential Information or access to the Shopify API」「to substantially replicate products or services offered by Shopify or any Shopify Related Entity,」「including the Shopify API and Services.」「Subject to the preceding sentence and the parties' other rights and obligations under the Terms」「(including confidentiality obligations and any restrictions on use of Merchant Data),」「each party agrees that the other party may develop and publish applications」「that are similar to or otherwise compete with such party's applications;」
- 2.3.14: 「not use the Shopify API to conduct any systematic or automated data collection activities」「(including scraping, data mining, data extraction and data harvesting)」「or to build any commerce or product index, and, in any event, not request more than the minimum amount of data」「from a Shopify API needed by your Application to provide the intended Application functionality,」「or any data outside any permissions granted by the Merchant or Shopify;」

この調査の読み: 2.3.10 は Shop アプリに似たアプリを作ることを、「Shopify API へのアクセスを使って Shopify の製品を実質的に複製する」場合に禁じ、同時に「互いに競合するアプリを作ってよい」とも書いている。2.3.14 は、Global Catalog を使わずに各店の API を巡回して商品の索引を作る設計に当たる。

## 商品情報 (名前・画像・価格) の取得

- Shopify: Ajax Product API `GET /{locale}/products/{product-handle}.js` で、任意の商品の JSON (タイトル・価格・在庫の有無・バリアント・画像等) を取れる。原文「You can make a `GET` request for the information of any product using the Ajax Product API.」バリアントは 250 個まで。ページはテーマ・ストアフロント向けの文脈で、第三者の利用の条件や上限の記載は無い (未確認)。https://shopify.dev/docs/api/ajax/reference/product 。多数の店を自動で取りに行くと、上の 2.3.14 の「product index」に当たるかが論点 (Ajax API が「Shopify API」に含まれるかは未確認)
- Amazon: PA-API 5 は廃止され、呼び出しは HTTP 403。後継の Creators API の条件は原文「Have at least 10 qualifying sales within the past 30 days to access the PA API through the Creators API」。操作は SearchItems・GetItems・GetVariations・GetBrowseNodes。https://affiliate-program.amazon.com/creatorsapi/docs/en-us/introduction 。始めたばかりで売上が無い間は使えない
- Amazon の価格表示: プログラム・ポリシーの参加要件 第 2 条(b) で、価格・在庫を出せるのは Amazon が提供するデータを表示するリンクを使う場合か Creators API で取得した場合に限られ、日時の注記が要る (要約。原文の一部「価格および在庫状況は表示された日付/時刻の時点のものであり、変更される場合があります。」)。https://affiliate.amazon.co.jp/help/operating/policies

## iOS のウィジェットの技術上の制約

Apple の文書の HTML ページは本文が取れなかったため、同じ文書の JSON 版 (https://developer.apple.com/tutorials/data/documentation/... .json) を WebFetch で取得した。

- `widgetURL` と `Link` (https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity): 原文「By default, tapping or clicking your widget or Live Activity opens its corresponding app.」`widgetURL(_:)` の説明は原文「Sets the URL to open in the containing app when the user clicks the widget.」。原文「When the widget or Live Activity receives an interaction, the system activates the containing app and passes the URL to onOpenURL, application(_:open:options:), or application(_:open:)」。`Link` は原文「accessoryRectangular, systemSmall, and larger system family sizes」で 1 つ以上置ける
- インタラクティブウィジェット (https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities): 原文「Widgets and Live Activities can include buttons and toggles to offer specific app functionality without launching the app.」既定では App Intent はウィジェットの拡張のプロセスで動く。原文「An interaction with a button or toggle should do more than open the app. If you want to offer an interaction that opens the app, use Link and View.widgetURL(_:)」。ロック中はボタンが動かない。サンプルは iOS 17 の判定の中でボタンを置いている
- `OpenURLIntent` (https://developer.apple.com/documentation/appintents/openurlintent): 原文「An app intent that opens one of your universal links and displays its contents.」「You can also place the app intent on a button in an interactive widget or Live Activity.」「The system automatically brings your app to the foreground to run an app intent of this type.」iOS 18.0 から
- ウィジェットから Safari や他社の URL を直接開けるか: 文書が書いているのは「URL は containing app に渡る」と「OpenURLIntent は自分の universal link を開く」だけで、他のアプリや Safari を直接開く方法は書かれていない。このため、ウィジェットのタップ → 自分のアプリが起動 → アプリが店の URL を開く、の経路になると読める (文書からの推論。実機では確かめていない)
- Android (Glance): `actionStartActivity` に「The target activity class」「The ComponentName」「An Intent」のどれかを渡せる (https://developer.android.com/develop/ui/compose/glance/user-interaction)。Intent を渡せるので、ブラウザを開く Intent を直接起動できると読める (文書からの推論。実機では確かめていない)。ラムダのコールバックからはアクティビティを起動できない (Android 12 以降の trampoline の制限) と注記がある

## App Store Review Guidelines (https://developer.apple.com/app-store/review/guidelines/)

原文:

- 3.1.3(e): 「If your app enables people to purchase physical goods or services that will be consumed outside of the app, you must use purchase methods other than in-app purchase to collect those payments, such as Apple Pay or traditional credit card entry.」
- 3.2.2(iii): 「Artificially increasing the number of impressions or click-throughs of ads, as well as apps that are designed predominantly for the display of ads.」
- 4.2: 「Your app should include features, content, and UI that elevate it beyond a repackaged website. If your app is not particularly useful, unique, or 'app-like,' it doesn't belong on the App Store.」
- 4.2.2: 「Other than catalogs, apps shouldn't primarily be marketing materials, advertisements, web clippings, content aggregators, or a collection of links.」
- 4.1(c): 「You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval from the developer.」
- 5.2.1: 「Don't use protected third-party material such as trademarks, copyrighted works, or patented ideas in your app without permission, ...」
- 5.2.2: 「If your app uses, accesses, monetizes access to, or displays content from a third-party service, ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request.」
- 「affiliate」という語はガイドラインの前半 10 万文字に無い (残り約 1.4 万文字は未読)

この調査の読み: 物理的な商品なので IAP の対象外。4.2.2 の「a collection of links」に見られないよう、ウィジェット・お気に入りの管理などアプリとしての機能が要る。5.2.2 により、Amazon・Shopify の規約で認められていることを求められれば示す必要があり、Amazon はアプリの承認がその根拠になる。

## 日本の法規制

- ステルスマーケティング (景品表示法、2023-10-01 施行): 消費者庁のページ https://www.caa.go.jp/policies/policy/representation/fair_labeling/stealth_marketing/ に原文「企業から広告・宣伝の依頼を受けたインフルエンサー等の第三者は規制の対象とはなりません。」。Q&A https://www.caa.go.jp/policies/policy/representation/fair_labeling/faq/stealth_marketing/ では、規制の対象は内容の決定に関与した事業者 (広告主) で、アフィリエイターは原則対象外 (Q1、要約)。アフィリエイトサイトの冒頭の「このサイトはアフィリエイト広告を利用しています。」の記載は、文字の大きさ・色を含め明瞭に伝わるかで判断し、一般の表示に見える部分の近くにも記載が要る (Q13、要約)。表示の例は「広告」「宣伝」「プロモーション」「PR」(Q11、要約)。運用基準の PDF は取得したがテキストを読めなかった
- この調査の読み: 店向けの表示枠は、広告主 (店) が対価を払って出すため、表示枠に「広告」「PR」等の表示を置く。規制の対象は店だが、店に違反をさせないために Quick Buy の側で表示が要る。Amazon のアソシエイトのリンクについても、ポリシーの参加要件 第 3 条(b) が適用法令に沿った開示を求めている
- 特定商取引法: 通信販売の定義は原文「「通信販売」とは、販売業者又は役務提供事業者（※１）が「郵便等」（※２）によって売買契約又は役務提供契約の申込みを受けて行う商品、権利の販売又は役務の提供のことをいいます。」。広告の表示義務 (価格・支払い・引渡し・返品・事業者の名称等) は販売業者に課される。https://www.no-trouble.caa.go.jp/what/mailorder/ 。この調査の読み: Quick Buy は売買の当事者ではなく、決済も店・Amazon の画面で行うため、販売業者には当たらないと読める (法律家の確認はしていない)。表示枠の価格表示が、店の広告の一部として表示義務の対象になるかは未確認
- 個人情報 (個人情報保護委員会 ガイドライン 通則編、令和8年6月一部改正 https://www.ppc.go.jp/personalinfo/legal/guidelines_tsusoku/): 個人情報は原文「他の情報と容易に照合することができ、それにより特定の個人を識別することができるものを含む。」。個人関連情報の例に原文「ある個人の商品購買履歴・サービス利用履歴」。この調査の読み: お気に入りの商品一覧をアカウント (メールアドレス等) と結び付けてサーバーに持つと個人情報になりうるため、利用目的の特定・公表が要る。Checkout MCP でメールアドレス・電話番号・IP を扱うなら確実に個人情報を扱う

## 取得できなかった・未確認のまま残した点

- 従来の cart permalink の在庫切れ・既存カート・有効期限 (文書に記載なし)
- Global Catalog の日本の店の有無・料金・開発者向けの専用規約
- Ajax Product API の第三者利用の条件
- ウィジェットから外部 URL を直接開けるか (iOS・Android とも文書からの推論。実機での確認なし)
- Amazon のアプリの承認でウィジェットが含まれるか、Buy Again に似た機能が「(d) 模倣」に当たるか
- PA-API 5 版の add-to-cart 文書 (403)
- 消費者庁の運用基準 PDF の本文 (テキスト抽出できず)
