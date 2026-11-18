# Quick Buy の商品の検索に使う API と、Amazon で開く URL (取得日: 2026-11-18)

https://github.com/bannzai/quickbuy/issues/27 の調査。2026-11-17 の調査 (`documents/research/2026-11-17/feasibility.md`・`monetization.md`・`report.md`) の続きで、アプリ内の検索を最初の版に入れる前提で足りなかった所を調べた。

この文書の読み方:

- 「」で引いた英文・和文は、出典の URL のページの原文。取得日は 2026-11-18
- 「実測」は、2026-11-18 に agent が `curl` で呼んだ結果。鍵 (API キー・アソシエイトの ID) は使っていない
- 「この調査の読み」と書いた節と文は、調査した agent の解釈で、提供元 (Shopify・Amazon) に確かめていない
- 「未確認」は、鍵が無い・ログインが要る・提供元の判断による、のどれかで確かめられなかった点

## 結論

| 調べること | 結論 |
| --- | --- |
| Shopify の商品を検索する API | Shopify の Catalog を使う。店をまたぐ検索は Global Catalog (`https://catalog.shopify.com/api/ucp/mcp`)、1 つの店の中の検索は店ごとの Storefront Catalog (`https://{店のドメイン}/api/ucp/mcp`)。どちらも鍵なしで呼べ、商品バリアントの ID・名前・画像・価格・店のドメインが返る (実測)。日本の店の商品も出る (実測) |
| Amazon の商品を検索する API | Creators API の SearchItems (Product Advertising API 5 は廃止)。使うには、アソシエイトのアカウントの最終の承認・過去 30 日に 10 件の適格販売・Amazon が承認したモバイルアプリ・鍵を置く自分のサーバー、の 4 つが要る。公開の前にはどれも満たせないため、最初の版では使えない |
| Amazon のカートに入れる URL | 現行の公式文書に無い (2009 年版の文書だけが残る)。アソシエイトの ID を付けないと空のカートへ送られる (2026-11-15 の bannzai の実測)。最初の版では使わず、商品ページ `https://www.amazon.co.jp/dp/{ASIN}` を開く |
| Amazon アソシエイトのアプリの承認 | ストアで公開したアプリを Amazon が審査する。ヘルプに「ショッピングや購買機能がメインとなっているアプリは、参加が承認されない可能性があります」とあり、検索した Amazon の商品を画像つきで並べる画面は、条件「Amazonのショッピングアプリの機能をエミュレート、偽装またはその機能と競合しないこと」に当たる読みが強い。「カートイン」の確認の後に外部のブラウザか Amazon のアプリで開く形は、開き方の禁止事項には当たらない読み |
| 鍵をアプリに埋め込めるか | Amazon は埋め込めない (文書に「Never expose your clientid and clientsecret in client-side code」)。Shopify の client secret も埋め込めない読みだが、Catalog には鍵なしの入口があり、最初の版はサーバーなしで検索できる |
| トップページに並べる商品の候補 | 最初の版 (サーバーなし・鍵なし) で出せるのは、買い直す物の検索語の候補と、選んだ店の商品 (Global Catalog の `filters.shops`)。人気の順に並べる方法は Shopify の Catalog の文書に見つからなかった |

最初の版への当てはめ (この調査の読み。`documents/DIRECTION.md` の「必要な機能」「決めたこと」に書いた):

- Shopify の検索は、Catalog を鍵なしでアプリから直接呼ぶ
- Amazon は、アプリ内の検索と Amazon が持つ名前・画像・価格の表示を最初の版に入れない。Amazon の商品は商品ページの URL を渡して登録し、「カートイン」の確認の後に商品ページを外部で開く。アソシエイトの ID は、Amazon がアプリを承認するまで付けない

## 1. Shopify: 商品を検索する API

### 入口は 2 つ

出典: https://shopify.dev/docs/agents/catalog

| | Global Catalog | Storefront Catalog |
| --- | --- | --- |
| 範囲 (原文の Scope) | 「All Shopify merchants」 | 「Single merchant store」 |
| Endpoint | `https://catalog.shopify.com/api/ucp/mcp` | `https://{storeDomain}/api/ucp/mcp` |
| 認証 (原文の Auth) | 「Agent profile (no API key needed)」 | 「Agent profile (no API key needed)」 |

どちらも JSON-RPC の `tools/call` で、次の 3 つの tool を呼ぶ。

- `search_catalog`: 検索語で探す
- `lookup_catalog`: ID から引く。「A single Global Catalog request resolves up to 50 identifiers, while Storefront Catalog supports up to 10.」
- `get_product`: 1 つの商品の、選べる種類と購入のリンクを返す

使い分け (出典: https://shopify.dev/docs/agents/catalog/storefront-catalog ): 「Use Storefront Catalog MCP whenever buyer intent and query are scoped to a single merchant.」「For cross-merchant product discovery, use Global Catalog MCP」

### エージェントのプロフィール

どちらの入口も、リクエストごとに `meta.ucp-agent.profile` へプロフィールの URL を入れる。

- 出典 https://shopify.dev/docs/agents/catalog/global-catalog : 「The `/api/ucp/mcp` endpoint requires an agent profile. Every request must include a `meta.ucp-agent.profile` URL pointing to your agent's UCP profile.」
- 同じページ: 「If you host your own profile, declare both the base UCP capabilities and Shopify's extensions」「For the Catalog, that means `dev.ucp.shopping.catalog.search` and `dev.ucp.shopping.catalog.lookup` plus `dev.shopify.catalog.global` (or `dev.shopify.catalog` on a merchant storefront).」
- 置き場所 (出典: https://shopify.dev/docs/agents/get-started/profile ): 「Copy and host the file above at a public URL.」「Use a static host (for example, GitHub raw, or your own domain).」
- 出典 https://shopify.dev/docs/agents/profiles : 「If the profile cannot be loaded, is invalid, or yields no compatible capabilities, you get an error path instead of a successful negotiation.」

実測: プロフィールの URL を付けずに Global Catalog の `search_catalog` を呼ぶと、JSON-RPC のエラー `-32001`「UCP discovery failed」(`data.code` は `invalid_profile_url`、`data.content` は「Unable to fetch agent profile: Missing profile uri」) が返った。

### 店をまたぐ検索の実測 (Global Catalog)

呼び方: `POST https://catalog.shopify.com/api/ucp/mcp`。`Authorization` ヘッダーなし。プロフィールは Shopify の見本 (`https://shopify.dev/ucp/agent-profiles/examples/2026-08-25/valid-with-capabilities.json`)。`search_catalog` に検索語「コーヒー豆」、`filters.ships_to.country` = `JP`、`filters.ships_from` = `[{"country":"JP"}]`、`context` = `{"address_country":"JP","language":"ja","currency":"JPY"}`、`pagination.limit` = 10。

結果: HTTP 200、`ucp.status` = `success`、商品 10 件、`pagination.total_count` = 986、`has_next_page` = true。10 件とも日本の店の商品だった (先頭 6 件の店は chimney-coffee.com・www.sotcoffee.com・galitebecoffee.com・driptrip.net・shop.kotarocoffee.com・lightupcoffee.com)。

返る値 (1 件目):

| 要る値 | 返る場所 | 実測の値 |
| --- | --- | --- |
| 商品バリアントの ID | `variants[].id` | `gid://shopify/ProductVariant/45476745412786`。末尾の数字が cart permalink に使う ID |
| 名前 | `title` (商品)、`variants[].options[].label` (種類) | 「コーヒー豆 200gセット」。`variants[].title` は商品の名前と同じ値だった |
| 画像 | `media[].url` | `https://cdn.shopify.com/s/files/1/0580/1692/3826/files/….jpg` |
| 価格 | `variants[].price`、`price_range` | `{"amount":2700,"currency":"JPY"}` |
| 店のドメイン | `variants[].seller.url` | `https://chimney-coffee.com`。`seller.domain` は `shibuyachimneycoffee.myshopify.com`、`seller.name` は店の名前、`seller.id` は `gid://shopify/Shop/58016923826` |
| 購入のリンク | `variants[].checkout_url` | `https://chimney-coffee.com/buy/45476745412786:1?ucp/version=2026-08-25&attribution/utm_source=shopify&attribution/utm_medium=catalog&attribution/click_id_tag=_gsid&attribution/click_id_value=…&_gsid=…` |

- 商品の ID (`id`) は `gid://shopify/p/3ubf9RoIBRkbf6xqPbL2nd` の形で、店の商品の ID ではない。検索の結果は「clustered by Universal Product ID (UPID) and include offers from multiple merchants」(出典: https://shopify.dev/docs/agents/catalog/global-catalog )
- 価格の単位は通貨の最小の単位 (同じページ: 「Like `price`, `list_price` is in minor currency units」。例は「`{"min": 5000, "max": 20000}`」が 50〜200 米ドル)。円は補助の単位が無いので 2700 は 2,700 円
- `checkout_url` の `_gsid` の値は、呼ぶたびに違う値が返った
- 検索の結果の 6 件目は「コーヒー豆の定期便」だった。定期購入が必須の商品は、購入画面の URL でカートを作れない (下の「購入画面の URL」)
- 1 回に返る件数は「`limit` (integer, min `1`, default `10`, max `50`)」、全体は「You can paginate up to 1,000 results.」、`total_count` は「an estimate」(同じページ)

種類の一覧の取り方 (実測): Global Catalog の `get_product` に商品の ID を渡すと、`product.options` に選べる種類 (例: `Bitter・mild` に 3 つ、`Coffee product form` に「粉」「豆」) と、`product.selected` に今選ばれている組が返り、`variants` は選ばれている 1 件だけだった。全部の商品バリアントは 1 回では返らず、種類を選ぶたびに `selected` を付けて呼び直す形になる。Global Catalog の `options` は Shopify が補った値で (同じページ: 「Treat them as discovery and merchandising signals, not as merchant-authored source text.」)、店が付けた名前 (下の実測の「BITTER・MILD」「豆・粉」) と違った。

ID からの引き直し (実測): Global Catalog の `lookup_catalog` に `gid://shopify/ProductVariant/45476745445554` を渡すと、名前・画像・価格・店 (`seller.url`)・`checkout_url` が返った。保存した商品バリアントの ID から、表示する時に名前と画像と価格を取り直せる。

### 1 つの店の中の検索の実測 (Storefront Catalog)

呼び方: `POST https://chimney-coffee.com/api/ucp/mcp`。`Authorization` ヘッダーなし。プロフィールは同じ見本。`search_catalog` に検索語「コーヒー」、`pagination.limit` = 5。

結果: HTTP 200、`ucp.status` = `success`、商品 5 件、`pagination.has_next_page` = true (`total_count` は無い)。kinto.co.jp でも同じ呼び方で 5 件が返った。

- 商品の ID は `gid://shopify/Product/8503532617906` (その店の商品の ID)、`url` は `https://chimney-coffee.com/products/coffee-beans`
- `variants` に全部の商品バリアントが 1 回で返った (3 × 2 の 6 件)。`variants[].title` に種類の名前が入る (「【BITTER】コーヒー豆（深煎り）200g / 豆」)
- `variants[].checkout_url` は `https://shibuyachimneycoffee.myshopify.com/cart/45476745412786:1` (従来の cart permalink の形で、myshopify.com のドメイン。流入元の引数は無い)
- `variants[].seller` は無い (店は呼び先のドメインで決まる)
- 1 回に返る件数は「min `1`, default `10`, max `250`」(出典: https://shopify.dev/docs/agents/catalog/storefront-catalog )
- 検索の結果に定期購入の商品 (「【定期購入｜5％OFF】コーヒー豆 200gセット」) も出た

店がこの入口に対応しているかは、店の `/.well-known/ucp` で分かる。実測で、chimney-coffee.com・kinto.co.jp・mini-mal.tokyo・tsuchiya-kaban.jp・lightupcoffee.com の 5 店は JSON が返り、`dev.ucp.shopping.catalog.search`・`dev.ucp.shopping.catalog.lookup`・`dev.ucp.shopping.permalink` (`config.endpoint` は `https://{店のドメイン}/buy`) があった。shop.basefood.co.jp と allbirds.jp は HTML が返った (Shopify の店でないのか、店の画面を独自に作っている店なのかは未確認)。

### 鍵の発行の手順・費用・上限

鍵 (client ID と client secret) の発行 (出典: https://shopify.dev/docs/agents/get-started/authentication ):

1. 「Access to Shopify's Dev Dashboard」( https://dev.shopify.com/dashboard )
2. 「In Dev Dashboard click **Catalogs** from the sidebar.」
3. 「Click **Get an API key**. Name your key, then click **Create**.」
4. 「Copy your client ID and client secret」
5. `POST https://api.shopify.com/auth/access_token` に `client_id`・`client_secret`・`grant_type=client_credentials` を送ってトークンを得る。「The token expires after 60 minutes」

Partner の組織では本人確認を求められることがある (出典: https://shopify.dev/docs/apps/build/dev-dashboard/catalogs ): 「In a Partner organization, Shopify might ask you to verify your identity first. Until you do, the page shows **Catalog search is locked**, and you can't create an API key or preview searches. Click **Verify to unlock** to start.」

費用: Catalog の文書 (上の各ページと https://shopify.dev/docs/agents ・ https://shopify.dev/docs/agents/profiles/auth-and-rate-limiting ) に、料金の記載は見つからなかった。無料と明記した文も見つからなかった。API の規約 ( https://www.shopify.com/legal/api-terms 、「Last updated on: October 7, 2026」) には「Such changes may include removal of features, or the requirements of fees for previously free features.」とある。

上限 (出典: https://shopify.dev/docs/agents/profiles/auth-and-rate-limiting ):

- 段階は 3 つ (Token = 鍵で得たトークン、Signed = 署名、Anonymous = どちらも無し)。「Rate limits scale with identification. The Token tier gets the highest limits, Signed gets lower limits, and Anonymous gets the lowest.」Catalog の tool は 3 つの段階のどれでも使える
- 鍵あり: 「Authenticated requests to the Global Catalog endpoint, `https://catalog.shopify.com/api/ucp/mcp`, are rate limited for each API client. The default limit is 5 requests each second for each API client.」
- 鍵なし: 「Unauthenticated requests are rate limited for each IP address and also share a single limit with all other unauthenticated traffic, so their throughput isn't guaranteed. Don't use unauthenticated requests for production traffic.」(「Global Catalog rate limits」の節の文)
- 店ごとの入口: 「Storefront Catalog requests to a store's `/api/ucp/mcp` endpoint use the same tool names, but they're rate limited separately for each store.」「allowances differ by tier and by tool and can change, so read `Retry-After` from each `429` response instead of hard-coding a request budget.」
- 上限を上げる (出典: https://shopify.dev/docs/agents/catalog ): 「Keyless catalog access doesn't support rate limit increases. To request a rate limit increase, go to the Shopify Help Center, select **Chat with us**, log in, and choose your Partner organization to contact us.」

実測の応答のヘッダーに、上限の残りを示すものは無かった。鍵なしの上限の数は文書に無く、未確認。

### 表示と保存の決まり

出典: https://shopify.dev/docs/agents/catalog の「Usage guidelines」。「By using either API, you agree to the Shopify API License and Terms of Use」「The following guidelines apply to both APIs and to every product they return」。

- 「**Use Catalog data only for shopper experiences**: Catalog results are provided to show products to buyers directly in your own agent or application and to help them buy.」
- 「**Caching limits**」: 「Cache results only when necessary, and only within the following limits:」「**Product metadata**, such as titles, descriptions, and options: cache up to 24 hours.」「**Images**: images served from Shopify CDN URLs can be cached up to 24 hours. You can use Shopify CDN resize and padding parameters.」「**Price and availability**: cache up to 10 minutes.」
- 「**Use images only with their product listing**: Images may only be used in connection with the related merchant's product listing.」
- 「**Keep attribution intact**: Don't remove or change attribution parameters (`shcgid` and `shclid`), checkout URLs, or merchant attribution in Catalog results.」
- 「**No bulk harvesting**: Don't conduct any systematic or automated data collection activities, or request more than the minimum amount of data necessary.」
- 「**No use for training purposes**: Don't use Catalog results to develop, train, or fine-tune any ML or AI models, or to build a standing product database or commerce index, without Shopify's or the merchant's consent.」
- 「**No redistribution, resale, or bulk export**: Don't aggregate, rehost, redistribute, resell, syndicate, or bulk export Catalog results to third parties.」

### 購入画面の URL

出典: https://shopify.dev/docs/agents/carts-and-checkout/permalinks (従来の形と後継の形の違いは `documents/research/2026-11-17/feasibility.md` にある)。

- 「Get the product variant IDs for the items that you want to sell. Global Catalog and Storefront Catalog return them for each product.」
- 「Use the endpoint exactly as the profile lists it, instead of building it yourself.」「If the profile doesn't list `dev.ucp.shopping.permalink`, then the store doesn't accept Cart and Checkout Permalinks. Use legacy cart permalinks instead.」
- 「**Selling plans:** Shopify adds every item as a one-time purchase」「If an item requires a selling plan, such as a subscription-only product, then Shopify can't create the cart.」
- 「If the link is invalid or Shopify can't create the cart, then Shopify sends the buyer to a valid `continue_to` path or the store's home page.」

### 使わない方法

- 店の予測検索 (`/search/suggest.json`。出典: https://shopify.dev/docs/api/ajax/reference/predictive-search ): 「Predictive search is supported when the customer's online store session (`buyer locale`) is in one of the following supported languages」の一覧に日本語が無い。HTTP 417 は「**Expectation failed** - The buyer isn't using one of the supported languages.」。実測でも、chimney-coffee.com は `Accept-Language` の有無にかかわらず HTTP 417 (`{"status":417,"message":"Expectation Failed","description":"Unsupported buyer locale"}`) を返した。日本語の店では使えない
- 店の `/products.json`: 実測で chimney-coffee.com は商品の ID・名前・商品バリアントの ID・価格・画像を返した。検索語で絞る引数があるかと、第三者が使う時の条件は、この調査では確かめていない。Catalog で足りるため使わない
- Global Catalog の Shopify の外の店の商品 (出典: https://shopify.dev/docs/agents/catalog/global-catalog-extension ): 既定では返らず、「External offers currently cover merchants selling to the United States.」
- 個人に合わせた検索 (Shop の利用者のログインが要る)

### この調査の読み

- 検索の API は Catalog で足りる。要る値 (商品バリアントの ID・名前・画像・価格・店のドメイン) は全部返り、日本の店の商品も出る。企画 ( https://github.com/bannzai/IdeaMemo/issues/398 ) の未確認の点「日本の店が Shopify の横断カタログの対象に入っているか」は、入っている
- 流れは、Global Catalog の `search_catalog` で店をまたいで探し、選んだ商品の種類は、その店の入口 (`seller.url` のドメインの `/api/ucp/mcp`) の `lookup_catalog` か `search_catalog` で全部の商品バリアントを取る形が、呼ぶ回数が少ない。Global Catalog だけで作ると、種類を選ぶたびに `get_product` を呼び直す
- 最初の版はサーバーを持たない (`documents/adr/0001-device-local-storage-and-no-backend-for-first-version.md`) ので、鍵なしで呼ぶ。鍵なしは Shopify が用意した入口だが、Global Catalog は「Don't use unauthenticated requests for production traffic」と書かれ、上限も上げられない。HTTP 429 が増えた時は、自分のサーバーに鍵を置く形 (下の「4. 鍵をアプリに埋め込めるか」) へ移る。移す時の費用の上限は bannzai が決める (`documents/DIRECTION.md`「agent に任せること」)
- 利用者に確かめてもらう店のドメイン (`documents/adr/0003-open-purchase-screen-by-fixed-url-and-user-confirms-payment.md`) は、`seller.url` のドメインを見せる。`seller.domain` (myshopify.com) は利用者が知らない名前
- 保存の決まりは、お気に入りの型 (`Shared/Favorite.swift`) に効く。今の型は、名前 (`name`) と画像の URL (`imageURL`) を端末に保存する。Catalog が返した名前と画像の URL を 24 時間を超えて持ち続けることは「Caching limits」に触れうる。保存するのは店のドメイン・商品バリアントの ID・個数・利用者が付けた名前にし、Catalog が返した名前・画像・価格は、表示する時に `lookup_catalog` で取り直して 24 時間 (価格は 10 分) を超えて持たない形が、決まりに沿う。利用者が登録の操作で保存した名前が「cache」に当たるかは、決まりの文からは決まらない
- 「Keep attribution intact」と、購入画面の URL を決まった形で組み立て直す決まり (ADR 0003) がぶつかる。今の組み立ての関数 (`Shared/ShopifyCartPermalink.swift`) は、店のドメイン・商品バリアントの ID・個数だけで `/cart/{ID}:{個数}` を作り、Catalog が返した `checkout_url` と流入元の引数を使わない。実測で、店の入口が返した `checkout_url` は流入元の引数の無い `/cart/` の形で、今の関数が作る形と同じだった。Global Catalog が返した `checkout_url` は流入元の引数つきの `/buy/` の形だった。種類の一覧を店の入口から取る流れなら、店の入口が返した形と同じ URL を開くことになる。それで「Keep attribution intact」を満たすかは Shopify に確かめていない
- 定期購入が必須の商品は、検索の結果に出るが購入画面を開けない。実測の応答では見分けられなかった (店の入口の `variants[].requires` は、定期購入の商品も通常の商品も `{"shipping":true}`。Global Catalog の `variants[].eligible` は 10 件とも `{"native_checkout":false}`)。購入画面を開けなかった時は店のトップページへ送られる (上の「購入画面の URL」) ので、開けない商品があることを利用者に伝える表示が要る

### 未確認の点

- 鍵なしの上限の数 (文書に無い)
- 自分で置いたプロフィール (GitHub Pages か GitHub raw) で Catalog が通るか → 下の「4. 鍵をアプリに埋め込めるか」の実測
- 鍵ありで返る値が鍵なしと同じか (流入元の引数が `shcgid`・`shclid` になるか)。鍵が無いので確かめていない
- 利用者が保存した名前が「Caching limits」の対象か、決まった形で組み立てた URL が「Keep attribution intact」を満たすか (Shopify の判断)
- 従来の cart permalink (`/cart/`) を、店の表のドメインと myshopify.com のドメインのどちらで開くべきか。店の入口が返した `checkout_url` は myshopify.com だった
- 定期購入が必須の商品を、応答のどの値で見分けられるか (上の 2 つの値では見分けられなかった。`get_product` の応答は確かめていない)

## 2. Amazon: 商品を検索する API と、カートに入れる URL

### 検索の公式の API は Creators API

Product Advertising API 5 は廃止された (出典: https://affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation 。「The Amazon Product Advertising API 5.0 (PA-API 5) has been deprecated and is being replaced by the Creators API.」)。`documents/research/2026-11-17/` が PA-API と書いた所は、Creators API が後継になる。

Creators API の文書は、日本のアソシエイトのサイトに英語で置かれている (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/introduction )。

- 「The Creators API is a REST-based API that provides programmatic access to Amazon's product catalog data」
- 操作は 4 つ: SearchItems (「Search for products using keywords, filters, and browse nodes」)、GetItems (「Retrieve detailed information for specific products by ASIN or other identifiers」)、GetVariations (「Get all variations of a parent product」)、GetBrowseNodes

SearchItems (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/api-reference/operations/search-items ):

- 「The SearchItems operation searches for items on Amazon based on a search query. The Amazon Creators API returns up to ten items per search request.」
- 引数: `keywords` (検索語)、`partnerTag` (アソシエイトの ID。必須)、`marketplace` (日本は `www.amazon.co.jp`)、`itemCount` (1〜10)、`itemPage` (1〜10)、`searchIndex`・`browseNodeId` (分類)、`sortBy`、`resources` (返す値の指定)
- 文書の見本の応答にある値: `asin`、`itemInfo.title.displayValue` (名前)、`images.primary.medium.url` (画像。`https://m.media-amazon.com/images/I/….jpg`)、`offersV2.listings[].price.money` (価格。`amount`・`currency`・`displayAmount`)、`detailPageURL` (アソシエイトの ID つきの商品ページ。見本は `https://www.amazon.com/dp/0545162076?tag=dgfd&linkCode=osi`)

種類 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/api-reference/operations/get-variations ): 「A variation is a child ASIN. The parent ASIN is an abstraction of the children items.」「parent ASINs cannot be sold.」Amazon の種類は子の ASIN で、お気に入りが持つのは子の ASIN と個数になる。

呼び方 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/get-started/using-curl ): 日本は `POST https://api.amazon.co.jp/auth/o2/token` に `client_id`・`client_secret`・`grant_type=client_credentials`・`scope=creatorsapi::default` を送ってトークン (1 時間有効) を得て、`https://creatorsapi.amazon` (「The API endpoint for all regions is: https://creatorsapi.amazon」) の各操作を `Authorization: Bearer …` と `x-marketplace` のヘッダーつきで呼ぶ。文書の例は GetItems の `POST https://creatorsapi.amazon/catalog/v1/getItems`。

### 使える条件

アカウントと実績:

- 出典 https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/introduction : 「To use the Creators API, you must:」「Be enrolled in the Amazon Associates program for your target marketplace」「Have at least 10 qualifying sales within the past 30 days to access the PA API through the Creators API」「Register for API access through Associates Central」「Generate API credentials」
- 出典 https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/onboarding/register-for-creators-api : 「Before you register for the Creators API, you must have an Amazon Associates account that has been reviewed and received final acceptance into the Amazon Associates Program.」「Creators API sign up is available only to associates who have referred qualified sales and have been accepted into the program.」
- アカウントの最終の承認 (出典: https://affiliate.amazon.co.jp/help/node/topic/G8TW5AE9XL2VX9VM ): 「サインアップ後、一定の適格販売が発生すると、アソシエイト・チームがあなたの申請を確認します (サインアップから 180 日以内に 3 回以上の適格販売の発生が必要です)。 あなた自身による注文は審査対象となりませんのでご注意ください。」
- 続けるための実績 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/concepts/api-rates ): 「Note that your account will lose access to Creators API if it has not generated qualified referring sales for a consecutive 30-day period.」「You will regain access to Creators API within two days after your referred sales are shipped.」

鍵の発行の手順 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/onboarding/register-for-creators-api ): 「After you sign-in to your Amazon Associates account, in the Amazon Associates page, choose **Tools** and then choose **Creators API**.」「Only the primary account owner of the Amazon Associates account can sign up for the Creators API.」「Choose **Create Application**.」「copy your Credential ID, Secret, and Version or download them to CSV.」

費用: アソシエイトへの参加は無料 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/onboarding 。「The Associates Program is free to join」)。Creators API の料金の記載は、読んだページに見つからなかった。

上限 (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/concepts/api-rates ):

- 「As soon as you create your Creators API credentials, you are allowed an initial usage limit up to a maximum of one request per second (one TPS) and a cumulative daily maximum of 8640 requests per day (8640 TPD) for the first 30-day period.」
- 「Your account will earn a usage limit of one TPD for every five cents or one TPS (up to a maximum of ten TPS) for every $4320 of shipped item revenue generated via the use of Creators API for shipments in the previous 30-day period」

モバイルアプリで使う条件 (出典: https://affiliate.amazon.co.jp/help/operating/policies の「アソシエイト・プログラムIPライセンスおよび利用要件」):

- 「乙は、甲の事前の書面による明確な承諾なしに、携帯電話その他携帯端末での使用を目的としたもしくは意図したサイトもしくはアプリケーション上でまたはこれらに関連して、プロダクト広告コンテンツを使用しないものとします。」ただし、モバイル・アプリケーション・ポリシーで定義される承認されたモバイル・アプリケーションには適用されない、と続く
- 「乙は、アマゾン・サイトの宣伝およびマーケティングならびにアマゾン・サイト上の商品およびサービスの販売促進を主要な目的としないサイト、アプリケーションまたはそれ以外の方法で、Creators API、PA API、データフィードまたはプロダクト広告コンテンツを使用しないものとします。」

表示と保存の決まり (同じ「アソシエイト・プログラムIPライセンスおよび利用要件」):

- 保存: 「乙は、画像で構成されるプロダクト広告コンテンツを保存またはキャッシュしてはいけませんが、画像で構成されるプロダクト広告コンテンツへのリンクについては最長24時間保存することができます。」「乙は、個別のAmazon Standard Identification Number（以下「ASIN」といいます。）を、本ライセンスの終了まで、期間の制限なく保存することができます。前記にかかわらず、乙のアプリケーションがクライアントアプリケーションを含む場合、これらのクライアントアプリケーションは、プロダクト広告コンテンツを保存またはキャッシュしてはいけません。」
- 価格: 取り直しが 1 時間に 1 回以下なら、価格の隣に日付か時刻を出す。免責の文言は「価格および在庫状況は表示された日付/時刻の時点のものであり、変更される場合があります。本商品の購入においては、購入の時点で（該当するアマゾン・サイト）に表示されている価格および在庫状況に関する情報が適用されます。」
- 価格と在庫を出せる場合 (同じページの参加要件): 「(a)甲が価格および在庫のデータを表示しているリンクを提供する場合、または(b)乙がCreators APIを経由して商品の価格および在庫のデータを取得し、本ライセンスに定めるCreators APIの使用に関する要件を遵守する場合。」
- 表示する文言: 「［「本アプリケーション内」／「本サイト上」］で表示されるコンテンツの一部は、アマゾンにより提供されたものです。これらのコンテンツは「現状有姿」で提供されており、随時変更または削除される場合があります。」
- リンク (出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/concepts/best-programming-practices ): 「Important: Alterations of any kind to vended links will lead to missing attribution and loss of Associate fees.」(出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/concepts/api-rates ): 「You are using the links provided by Creators API when linking back to Amazon. Do not edit any of the URL parameters.」
- Amazon 以外の店の商品 (同じページの参加要件): 「乙は、アマゾン・サイトではないサイト上で提供される商品（例えば、その他の小売業者が提供する商品）を宣伝またはプロモーションするために、プログラム・コンテンツを乙のサイトに表示したり、その他の利用をしないものとします。」

Creators API の文書 ( https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/license-agreement ) は、日本のライセンスとして https://affiliate.amazon.co.jp/help/operating/paapilicenseagreement (条文は Product Advertising API の語のまま) を指している。保存・価格・モバイルの条は、上のポリシーのページの条と同じ趣旨だった。

### カートに入れる URL

- 形 (企画 https://github.com/bannzai/IdeaMemo/issues/398 の記載): `https://www.amazon.co.jp/gp/aws/cart/add.html?ASIN.1={ASIN}&Quantity.1={個数}&AssociateTag={アソシエイトの ID}`
- 動き (同じ企画の記載。2026-11-15 に bannzai がログイン済みのブラウザで試した結果): 「アソシエイトのタグを付けないと空のカートへ送られる。タグを付けると「カートに入れる」の確認画面 (商品名・数量・価格) が出て、ボタンを押すと入る。開いただけではカートに入らない」
- 文書: 2009 年版の「「ショッピングカートに入れる」フォーム」( https://images-na.ssl-images-amazon.com/images/G/09/associates/paapi/dg/AddToCartForm.html ) は今も取得できる。「「ショッピングカートに入れる」フォームを使用すると、任意の数の商品をカスタマーのショッピングカートに追加し、カスタマーをAmazonリテールWeb サイトに誘導することができます。」引数は `ASIN.x`・`Quantity.x`・`AWSAccessKeyId` (必須と書かれている)・`AssociateTag` (オプションと書かれている)
- 現行の文書には無い: Creators API の文書の操作は上の 4 つだけで、カートの語は移行の文書 ( https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/migrating-to-creatorsapi-from-paapi ) にも無かった。`https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/add-to-cart-form` は HTTP 404、PA-API 5 版の `https://webservices.amazon.co.jp/paapi5/documentation/add-to-cart-form.html` は HTTP 403、`https://webservices.amazon.com/paapi5/documentation/add-to-cart-form.html` は廃止の告知のページに変わっていた
- 今回、agent は動きを実測していない。アソシエイトの ID を持たないので ID つきの形を試せず、`curl` では amazon.co.jp が「下のボタンをクリックしてショッピングを続けてください」の画面を返して中身を取れなかった

使える条件 (出典: https://affiliate.amazon.co.jp/help/operating/policies ):

- アソシエイトの ID を付けたリンクをアプリに置けるのは、承認されたモバイルアプリだけ (下の「3.」)
- 紹介料の対象から外れる購入 (紹介料率表の 2(h)): 「承認モバイル・アプリ以外のモバイル・アプリ内の特別リンクまたはCreators API（本ライセンスで定義します。）もしくは甲が乙に提供する他のリンクツールにより提供されたものではない承認モバイル・アプリ内の特別リンク経由で購入された商品」
- カートに入れた後の紹介料 (紹介料率表の 1(b)): 「お客様が商品をショッピングカートに入れ、最初の特別リンクのクリックスルーから89日以内に当該商品の注文を完了することにより、商品を購入する」。ヘルプ ( https://affiliate.amazon.co.jp/help/node/topic/G2UYW4E8U6RVX22S ) は「カートに商品が入れられた時点で、ユーザーがAmazonにサインインしている状態でなければなりません。」

### この調査の読み

- 検索して名前・画像・価格・ASIN を得る公式の API は Creators API の SearchItems で、4 つの値は文書の見本の応答にある
- 最初の版の公開の時点では、Creators API を使えない。条件が 4 つ重なる: (1) アソシエイトのアカウントの最終の承認 (サインアップから 180 日以内に 3 回以上の適格販売)、(2) 過去 30 日に 10 件の適格販売 (30 日続けて売上が無いと失う)、(3) Amazon が承認したモバイルアプリ (審査はストアで公開した後)、(4) 鍵を置く自分のサーバー (下の「4.」)。運営者本人と近しい人の購入は適格販売に数えられない (`documents/research/2026-11-17/monetization.md`)
- 上限はアソシエイトのアカウントごとで、最初の 30 日は 1 秒に 1 回・1 日に 8,640 回。アプリの全部の利用者の検索がこの枠を分け合う。上限は Creators API 経由の売上に応じて増える
- 承認されたアプリでも、アプリは Amazon が返した名前・画像・価格を保存もキャッシュもできない。端末に保存できるのは ASIN と個数と、利用者が自分で付けた名前。お気に入りの型 (`Shared/Favorite.swift`) の `imageURL` に Amazon の画像の URL を保存し続ける形は、この条に触れる
- カートに入れる URL は、最初の版では使わない。理由は 3 つ: アソシエイトの ID が無いと空のカートへ送られ、ID を付けたリンクは承認の前のアプリに置けない / 現行の公式文書に無く、予告なく止まりうる / 承認の後でも、Creators API か Amazon のリンクツールが出したリンクでないと紹介料の対象から外れる (2(h)) ため、自分で組み立てたこの URL は対象から外れる読みになる
- 承認の後に紹介料を得るには、Creators API が返した `detailPageURL` を変えずに開くことになる。これは、購入画面の URL を決まった形で組み立て直す決まり (`documents/adr/0003-open-purchase-screen-by-fixed-url-and-user-confirms-payment.md`) とぶつかる。Creators API を入れる時に、ADR 0003 の扱いを決める

### 未確認の点

- bannzai のアソシエイトのアカウントが最終の承認を受けているか、過去 30 日の適格販売が何件か (bannzai が管理画面で見る)
- SearchItems の実際の応答 (鍵が無い)
- カートに入れる URL の今の動き (今回は実測していない)。Amazon のアプリが入った端末でこの URL がアプリで開くか
- 自分で組み立てた `https://www.amazon.co.jp/dp/{ASIN}?tag={アソシエイトの ID}` の形のリンクが、承認されたアプリの中で紹介料の対象になるか (2(h) の「甲が乙に提供する他のリンクツール」に何が入るか。Amazon の判断)
- Shopify の店と Amazon の両方を扱う Quick Buy が、「アマゾン・サイト上の商品およびサービスの販売促進を主要な目的」とするアプリと扱われるか (Amazon の判断)

## 3. Amazon アソシエイトのアプリの承認の条件と、Quick Buy の画面

`documents/research/2026-11-17/monetization.md` に、モバイル・アプリケーション・ポリシー・承認の無いアプリの禁止・自己購入の禁止の原文がある。ここには、検索の画面と「カートイン」の後の開き方に効く条と、2026-11-17 に読んでいなかったヘルプのページを足す。

### 承認の条件 (原文)

ポリシーのページ ( https://affiliate.amazon.co.jp/help/operating/policies ) の「モバイル・アプリケーション・ポリシー」は 5 項目: 「(a) Google Play、AppleまたはAmazonアプリストアのいずれかで提供されること、」「(b) 無料でダウンロードでき、Amazonへの全てのリンクに無料でアクセスできること、」「(c) 独自のコンテンツを有するものであること、」「(d) Amazonのショッピングアプリの機能を模倣（エミュレート）しないこと、」「(e) WebViewでAmazonのウェブページをホストまたはレンダリングしないこと。」「甲は、乙のアプリケーションを審査し、参加の可否を通知します。」

ヘルプの「モバイルアプリの開始方法とポリシーについて」( https://affiliate.amazon.co.jp/help/node/topic/GHBY6W8UPTEFD3ZX ) に載っているモバイル・アプリケーション・ポリシーは 6 項目で、文言が違う:

- 「a) Google Play、AppleまたはAmazonアプリストアのいずれかで提供されること。」
- 「b) 無料でダウンロードでき、Amazonへの全てのリンクに無料でアクセスできること。」
- 「c) 独自のコンテンツを有するものであること。」
- 「d) Amazonのショッピングアプリの機能をエミュレート、偽装またはその機能と競合しないこと。」
- 「e) 価格のトラッキングおよび価格のアラートの機能を有しないこと。」
- 「f) WebViewでAmazonのウェブページをホストまたはレンダリングしないこと。」

同じヘルプのページの、承認の対象の説明:

- 「Amazonの既存のモバイルショッピングウェブサイトや、Amazonの一連のモバイルアプリによって提供されるものとは大幅に異なるエクスペリエンスを生み出すアプリが、承認対象となります。既に存在するAmazonアプリを模倣する機能が含まれたアプリは、承認されない可能性があります。ショッピングや購買機能がメインとなっているアプリは、参加が承認されない可能性があります。」

申請の経路 (同じヘルプのページ):

- 「新規のアソシエイトIDを登録を推奨します。既存のアカウントに統合する場合は、アソシエイト・セントラルのアカウント管理にある「ウェブサイトとモバイルアプリの変更」から追加をしてください。」
- 「登録するアプリのURLは、アプリストアのURLを登録します。URLは常に最新の状態を保つようにしてください。」
- 審査 (出典: https://affiliate.amazon.co.jp/help/node/topic/G8TW5AE9XL2VX9VM ): 「審査では、あなたから提出されたすべてのサイト (ウェブサイト、モバイルアプリ、SNS ページ) がチェックされ」「アプリは、モバイル・アプリケーション・ポリシーの要件に準拠している必要があります。」「基準を満たしていないと判断された場合、申請が却下されることになります。申し訳ありませんが、一度却下された申請を再度審査することはできません。」

承認が無いアプリ:

- ポリシーのページの参加要件: 「乙は、以下の媒体上で、またはそれに関連して、プログラム・コンテンツもしくは特別リンクを使用、またはアマゾン・サイトにリンクさせてはなりません。」「あらゆるクライアント・サイド・ソフトウェアアプリケーション」「ただし、承認モバイル・アプリは除きます。」
- ヘルプの「モバイルアプリにPA-APIを組み込む方法」( https://affiliate.amazon.co.jp/help/node/topic/GFP8AD2UDZDQTJPP ): 「モバイルアプリは現在、改定条項に署名せずにAmazonへの広告リンクを設置することは承認されていません。承認を得ずにモバイルアプリでAmazonにリンクを設置することは詐欺行為となり、違反しているアソシエイトアカウントはPA-APIにアクセスできなくなります。」

### 開き方と表示の決まり (原文)

開き方:

- ヘルプの「モバイルアプリでのトラッキング方法」( https://affiliate.amazon.co.jp/help/node/topic/GBVXM9ANVYTMVQPW ): 「リンクの設置については、PC用サイトに設置するものと同じもので構いません。」「Webview でのAmazonサイトの表示は禁止されていますので、必ず外部ブラウザでURLを開くように設定をしてください。」
- ヘルプの「モバイルアプリの開始方法とポリシーについて」: 「アプリ内でのリダイレクトURLを避け、Amazonショッピングアプリへのディープリンクを活用するようにしてください。iOS9以降では、Amazonショッピングアプリへのディープリンク機能はデフォルトで有効になっています。Appleのユニバーサルリンク技術により、Amazonショッピングアプリを利用しているお客様はディープリンク機能により自動的にアプリ内の該当ページへと遷移されます。」
- ポリシーのページの参加要件 (n): 「乙は、モバイル・アプリ内に組み込まれたアプリ内ウェブブラウザ（WebView等）内に表示することを含め、アマゾン・サイトまたはその一部を、乙のサイトの中でフレーム化してはなりません。」
- 同 (q): 「乙は、お客様が乙のサイト上の特別リンクをクリックする方法以外で、当該お客様のブラウザでアマゾン・サイトのページが開くようにしてはなりません。」
- ヘルプ ( https://affiliate.amazon.co.jp/help/node/topic/GVFBVT6N73NTC933 ): 「訪問者が自動的にAmazonサイトにリダイレクトされたり、フレームや新たなブラウザウィンドウで Amazonサイトのページが自動的に開かれたりするような設定は認めていません。」
- 紹介料率表の 2(e) (紹介料の対象から外れる購入): 「お客様がリンクをクリックまたは仲介ウェブページ上でその他の能動的行為をすることを必要とせずに、仲介サイト経由でユーザを間接的にアマゾン・サイトに送るリンク（「リダイレクト・リンク」）を経由して、アマゾン・サイトに紹介されたお客様が購入した商品」
- 参加要件 (v): 特別リンクを置いたサイトの URL やアプリのユーザーエージェントを「（リダイレクトページの利用によるものも含め）クローク（覆う）、ハイド（隠す）、スプーフ（偽装）その他不明瞭にしてはなりません。」
- リンクの置き場所 (参加要件): 「乙は、乙の特別リンクをブックマークすることをお客様に奨励してはなりません。全ての特別リンクは、乙のサイトから直接アクセスしなければなりません。」
- 連絡に載せるリンク (参加要件): 「乙は、電子メール、SMSおよび自身のソーシャルメディアサイトのダイレクトメールに特別リンクを含めることができるものとします。」受け取る人が求めた連絡であることが条件。プッシュ通知は挙げられていない

表示:

- 参加要件 (w): 「乙はアマゾン・サイトへのリンクであることが不明瞭になる方法で、ショートカットリンク作成サービス、ボタン、ハイパーリンクまたはその他の広告プレースメントを使用してはなりません。」
- 同 (l): 「乙は、甲と乙との関係について、または何らかの機能もしくは取引活動（検索、ブラウズまたは注文等）が生じるサイトについて、お客様を混乱させる合理的可能性のある行為を行ってはなりません。」
- 同 (y): 「甲が別途合意しない限り、乙のサイトは、価格のトラッキングおよび/または価格のアラートの機能を備えてはなりません。」
- 同 (i): 「乙は、アマゾン・サイトに関連して甲のお客様が使用するアカウント情報（アマゾン・サイトのお客様のユーザ名またはパスワードを含みます。）を要請、収集、取得、保存、キャッシュ、もしくは使用してはなりません。」
- 同 (k): 「乙は、他の個人または団体を代理して、アマゾン・サイトにおいて注文またはその他の取引に関与してはなりません。」

### 検索した商品を画像つきで並べる画面への当てはめ (この調査の読み)

- 承認の条件に当たる読みが強い。Amazon の商品を検索し、画像と価格つきで並べ、押すと Amazon で買える画面は、Amazon のショッピングアプリの検索と商品の一覧と同じ働きをする。ヘルプの条件は「エミュレート、偽装またはその機能と競合しないこと」で、承認の対象の説明は「ショッピングや購買機能がメインとなっているアプリは、参加が承認されない可能性があります」と書く。Quick Buy は買い直しが主な機能のアプリで、Amazon のアプリにも買い直しの機能がある (`documents/research/2026-11-17/monetization.md`)
- 承認されるかは Amazon の審査の判断で、条文からは決まらない。「可能性があります」と書かれており、承認されない、とは書かれていない
- 承認された場合でも、画面には次が要る: Amazon が提供したコンテンツであることの文言と、価格の日時の注記 (上の「2.」)。Amazon の商品だと分かる表示 ((w))。Amazon の名前・画像・価格を、Shopify の店の商品の宣伝に使わない (上の「2.」の「Amazon 以外の店の商品」)。同じ一覧に Amazon の商品と Shopify の店の商品を混ぜて並べると、この条に触れると読まれうるので、店の種類で分けて並べる方が安全
- 最初の版には入れられない。Amazon が持つ名前・画像・価格を得る手段は Creators API だけで、公開の時点では使えない (上の「2.」)

### 「カートイン」の確認の後に開く形への当てはめ (この調査の読み)

- 開き方の決まりには当たらない読み。利用者が「カートイン」を押し、「購入画面を開きますか？」に答えた後に開くので、利用者のクリックで開く形になる ((q)・自動のリダイレクトの禁止に当たらない)。条件は、アプリの中の WebView で開かず、外部のブラウザか Amazon のアプリで開くこと
- アプリの中のブラウザ (SFSafariViewController) が「WebView等」に入るかは条文に無い。ヘルプは「必ず外部ブラウザでURLを開く」と書くので、Amazon のリンクはアプリの外で開く
- 開く物は商品ページにする。カートに入れる URL を使わない理由は上の「2.」。ヘルプが勧める開き方 (Amazon のアプリへのディープリンク) は、商品ページの URL をアプリの外で開く形と合う
- ウィジェットの「カートイン」→ 通知 → 通知をタップ、リマインドの通知 → タップ、も利用者の操作の後に開く。ただし (q) は「乙のサイト上の特別リンクをクリックする方法」と書き、通知をタップして開く形がそれに当たるかは書かれていない。連絡に載せてよいリンクの列挙にプッシュ通知は無い。アソシエイトの ID を付けたリンクを開く時は、通知からアプリを開き、アプリの中の確認の後に開く形の方が、条文に沿う
- 経由 URL (自分のサーバーの URL で、開かれた時に店の購入画面へ送るもの) は、Amazon には使わない。利用者の操作なしに仲介のサイトから Amazon へ送る形は紹介料の対象から外れ (2(e))、リンクを置いた場所を隠す形にも当たりうる ((v))
- お気に入りは、利用者が商品を保存し、押すたびにアプリが Amazon へのリンクを開く。利用者に特別リンクを保存させる形ではないが、「特別リンクをブックマークすることをお客様に奨励してはなりません」に当たるかは Amazon の判断
- リマインドは日数で知らせる機能で、価格のアラートではない。価格が下がった時に知らせる機能は作らない

### 最初の版 (承認の前) への当てはめ (この調査の読み)

- アプリの承認の申請には、ストアの URL が要る。申請は公開の後になり、最初の版は承認の無いアプリとして公開される
- 承認の前は、Amazon へのリンクにアソシエイトの ID を付けない。ヘルプは、承認を得ずにアプリに広告リンクを置くことを「詐欺行為」と書く
- アソシエイトの ID を付けない、ただの商品ページへのリンク (`https://www.amazon.co.jp/dp/{ASIN}`) を、承認の無いアプリに置いてよいかは、条文からは決まらない。参加要件は「プログラム・コンテンツもしくは特別リンクを使用、またはアマゾン・サイトにリンクさせてはなりません」と書き、文字どおりに読むと ID の無いリンクも含む。ヘルプは「広告リンク」と書き、ID を付けたリンクを指す読みもできる。bannzai はアソシエイトの参加者なので、公開の前に Amazon に確かめる (下の「bannzai が行う作業」)
- 一度却下された申請は再び審査されない。申請の前に、検索の画面を入れるかどうかを含めて、Amazon に問い合わせて見込みを確かめる (`documents/research/2026-11-17/report.md` の「最安の検証実験」にも同じ問い合わせがある)

### 未確認の点

- Quick Buy が承認されるか (Amazon の審査)
- ポリシーのページの 5 項目と、ヘルプのページの 6 項目の、どちらが審査で使われるか
- アソシエイトの ID の無いリンクを、承認の無いアプリに置いてよいか
- ウィジェット・通知から開く形が、承認されたアプリの中のリンクとして扱われるか (`documents/research/2026-11-17/monetization.md` にも未確認として残っている)
- お気に入りに保存して繰り返し開く形が「ブックマークの奨励」に当たるか
