import Foundation

/// Shopify の Catalog に渡す、エージェントのプロフィール (能力を宣言した JSON) の URL。中身はこのリポジトリの `ucp/agent-profile.json`。
///
/// jsDelivr の URL にしているのは、2026-11-19 の実測で GitHub raw の URL (`https://raw.githubusercontent.com/bannzai/quickbuy/…/ucp/agent-profile.json`) を渡すと
/// HTTP 422・`profile_malformed`「Unable to fetch agent profile: Invalid content type」が返り (GitHub raw は `text/plain` で返す)、
/// 同じファイルを jsDelivr (`Content-Type: application/json`) で渡すと HTTP 200 で検索の結果が返ったため (https://github.com/bannzai/quickbuy/pull/47 )。
/// jsDelivr はブランチを指す URL の写しを持つため、プロフィールを変えた時の反映が遅れる。GitHub Pages を有効にした時に Pages の URL へ移す (documents/DIRECTION.md「決めたこと」)。
let shopifyAgentProfileURLText = "https://cdn.jsdelivr.net/gh/bannzai/quickbuy@main/ucp/agent-profile.json"

/// 店をまたいで商品を探す Global Catalog の入口。
///
/// 出典: https://shopify.dev/docs/agents/catalog の「Endpoint」(documents/research/2026-11-18/search-api-and-amazon-purchase-url.md「入口は 2 つ」)。
let shopifyGlobalCatalogEndpointURL = URL(string: "https://catalog.shopify.com/api/ucp/mcp")!

/// 検索の 1 回で受け取る商品の数。
///
/// 20 は、画面の 2 列の並びで 10 行分になり、続きを読み込む操作を作らずに済む数として agent が決めた値。
/// Shopify の「No bulk harvesting」(必要な分より多く取らない) に沿うよう、上限の 50 (https://shopify.dev/docs/agents/catalog/global-catalog の `limit`) より小さくしている。
let shopifyCatalogSearchLimit = 20

/// Catalog が返した価格を、取得してから持ってよい秒数。
///
/// 出典: Shopify の Catalog の「Caching limits」の「Price and availability: cache up to 10 minutes.」(引用元の URL と全文は documents/research/2026-11-18/search-api-and-amazon-purchase-url.md)。
let shopifyCatalogPriceCacheSeconds: TimeInterval = 10 * 60

/// Catalog が返した名前・説明文・種類の選び方・画像を、取得してから持ってよい秒数。
///
/// 出典: Shopify の Catalog の「Caching limits」の「Product metadata, such as titles, descriptions, and options: cache up to 24 hours.」「Images: images served from Shopify CDN URLs can be cached up to 24 hours.」(引用元の URL と全文は documents/research/2026-11-18/search-api-and-amazon-purchase-url.md)。
let shopifyCatalogContentCacheSeconds: TimeInterval = 24 * 60 * 60

/// Catalog の呼び出しに添える、買い手の国・言語・通貨。
///
/// アプリの対象は日本の利用者で、購入画面の店も日本へ送る店を選ぶため、日本・日本語・円にしている (documents/PROJECT.md「対象にする人」)。
private let shopifyCatalogContext: [String: String] = ["address_country": "JP", "language": "ja", "currency": "JPY"]

/// Catalog が返す金額 (通貨の最小の単位の整数と通貨)。
///
/// 形の出典: https://shopify.dev/docs/agents/catalog/global-catalog の「Like `price`, `list_price` is in minor currency units」。
struct ShopifyCatalogMoney: Decodable, Equatable {
    /// 通貨の最小の単位で数えた金額 (円は補助の単位が無いので 2700 は 2,700 円)。
    let amount: Int
    /// ISO 4217 の通貨のコード (例: `JPY`)。
    let currency: String
}

/// Catalog が返す画像か動画。
///
/// 形の出典: 2026-11-21 の Global Catalog の `search_catalog` の実測 (20 件の商品の `media` の 21 件のうち、`type` は `image` が 20 件、`video` が 1 件で、動画の `url` は `.m3u8` だった)。
struct ShopifyCatalogMedia: Decodable, Equatable {
    /// 種別 (`image`・`video`)。
    let type: String?
    /// 画像か動画の URL の文字列。
    let url: String
}

/// Catalog が返す商品の説明文。
///
/// 形の出典: 2026-11-21 の実測。Global Catalog の `search_catalog` は 20 件とも `plain` だけを返し、19 件の値に HTML のタグ (`<p>`・`<br>` など) が入っていた。
/// 店の入口の `get_product` は 7 つの店とも `html` だけを返し、値にタグも改行も無かった。
struct ShopifyCatalogDescription: Decodable, Equatable {
    /// Global Catalog が返す説明文。
    let plain: String?
    /// 店の入口が返す説明文。
    let html: String?
}

/// Catalog が返す商品バリアント (色・大きさなどの違いごとの、カートに入れる単位)。
struct ShopifyCatalogVariant: Decodable, Equatable {
    /// 商品バリアントの ID (`gid://shopify/ProductVariant/{数字}` の形)。
    let id: String
    /// 商品バリアントの名前。Global Catalog は商品の名前と同じ値を、店の入口は種類の名前 (例: `【MILD】コーヒー豆（中深煎り）200g / 粉`) を返す。
    let title: String
    /// 価格。
    let price: ShopifyCatalogMoney?
    /// 今買えるか。
    let availability: Availability?
    /// 売っている店。Global Catalog だけが返し、店の入口は返さない。
    let seller: Seller?

    /// 商品バリアントが今買えるか。
    struct Availability: Decodable, Equatable {
        /// 今買える時は true。
        let available: Bool
    }

    /// 商品バリアントを売っている店。
    struct Seller: Decodable, Equatable {
        /// 店の表のドメインの URL (例: `https://chimney-coffee.com`)。利用者に見せて確かめてもらう店のドメインはこの URL のホスト。
        let url: String
    }
}

/// Catalog が返す、種類の選び方の 1 つ (例: 「内容量」とその値の並び)。
struct ShopifyCatalogOption: Decodable, Equatable {
    /// 種類の選び方の名前 (例: `BITTER・MILD`)。
    let name: String
    /// 選べる値の並び。
    let values: [Value]

    /// 選べる値の 1 つ。
    struct Value: Decodable, Equatable {
        /// 値の名前 (例: `粉`)。
        let label: String
    }
}

/// 種類の選び方ごとに選んである値。`get_product` の `selected` の要素で、応答と要求の両方に使う。
struct ShopifyCatalogSelectedOption: Codable, Equatable, Hashable {
    /// 種類の選び方の名前 (`ShopifyCatalogOption.name`)。
    let name: String
    /// 選んである値の名前 (`ShopifyCatalogOption.Value.label`)。
    let label: String
}

/// Catalog が返す商品。
///
/// 形の出典: 2026-11-18・2026-11-19 の実測の応答 (documents/research/2026-11-18/search-api-and-amazon-purchase-url.md「店をまたぐ検索の実測」「1 つの店の中の検索の実測」)。
struct ShopifyCatalogProduct: Decodable, Equatable {
    /// 商品の ID。Global Catalog は `gid://shopify/p/…`、店の入口は `gid://shopify/Product/{数字}`。
    let id: String
    /// 商品の名前。
    let title: String
    /// 商品の説明文。
    let description: ShopifyCatalogDescription?
    /// 商品の画像と動画の並び。
    let media: [ShopifyCatalogMedia]?
    /// 種類の選び方の並び。
    let options: [ShopifyCatalogOption]?
    /// 今選ばれている値の組 (`get_product` だけが返す)。
    let selected: [ShopifyCatalogSelectedOption]?
    /// 商品バリアントの並び。`search_catalog` も `get_product` も 1 件だけ返す。
    let variants: [ShopifyCatalogVariant]
}

/// Catalog の呼び出しが、結果を返さずに終わった理由。
enum ShopifyCatalogError: Error, Equatable {
    /// HTTP 429 (呼び出しの上限)。`retryAfterSeconds` は応答の `Retry-After` の秒数で、読めなかった時は nil。
    case rateLimited(retryAfterSeconds: Int?)
    /// 通信できなかった (圏外など)。
    case connectionFailed
    /// 応答が失敗を示した (JSON-RPC のエラー・`isError`・HTTP 200 以外) か、読めなかった。
    case failed
}

/// Catalog の JSON-RPC の応答のうち、結果とエラーの部分。
private struct ShopifyCatalogResponse<StructuredContent: Decodable>: Decodable {
    /// 成功した時の結果。
    let result: Result?

    /// `tools/call` の結果。
    struct Result: Decodable {
        /// tool が失敗した時は true。
        let isError: Bool?
        /// 結果の値。
        let structuredContent: StructuredContent?
    }
}

/// `search_catalog` の結果の値。
private struct ShopifyCatalogSearchContent: Decodable {
    /// 見つかった商品の並び。
    let products: [ShopifyCatalogProduct]
}

/// `get_product` の結果の値。
private struct ShopifyCatalogProductContent: Decodable {
    /// 指した商品。
    let product: ShopifyCatalogProduct
}

/// `Retry-After` の値を秒数にして返す。秒数の形 (0 以上の整数) でない時は nil。
///
/// 日時の形 (`Retry-After: Wed, 21 Oct 2015 07:28:00 GMT`) は秒数に直さず nil にする (利用者への文言を「少し待って」にするため)。
func retryAfterSeconds(headerValue: String?) -> Int? {
    headerValue.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 >= 0 ? $0 : nil }
}

/// Catalog の入口へ送る JSON-RPC の `tools/call` の本文を返す。
///
/// 送るのは、`toolName` と、`catalogArguments` に `context` (日本・日本語・円) を足した `catalog`、`meta.ucp-agent.profile` (`shopifyAgentProfileURLText`) だけ。
/// 形の出典: documents/research/2026-11-18/search-api-and-amazon-purchase-url.md の実測の要求と、2026-11-19 の実測 (引数を `catalog` で包まないと「Missing required arguments: catalog」が返り、包むと結果が返った)。
func shopifyCatalogToolCallBody(toolName: String, catalogArguments: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": [
            "name": toolName,
            "arguments": [
                "catalog": catalogArguments.merging(["context": shopifyCatalogContext] as [String: Any]) { argument, _ in argument },
                "meta": ["ucp-agent": ["profile": shopifyAgentProfileURLText]],
            ],
        ],
    ])
}

/// Catalog の入口へ tool を 1 回呼び (本文は `shopifyCatalogToolCallBody`)、結果の値を返す。
///
/// 失敗は `ShopifyCatalogError` で投げる (HTTP 429 は `rateLimited`、通信の失敗は `connectionFailed`、それ以外の失敗と読めない応答は `failed`)。
private func callShopifyCatalogTool<StructuredContent: Decodable>(
    endpointURL: URL,
    toolName: String,
    catalogArguments: [String: Any],
    urlSession: URLSession
) async throws -> StructuredContent {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try shopifyCatalogToolCallBody(toolName: toolName, catalogArguments: catalogArguments)
    guard let (data, response) = try? await urlSession.data(for: request) else {
        throw ShopifyCatalogError.connectionFailed
    }
    let httpResponse = response as? HTTPURLResponse
    guard httpResponse?.statusCode != 429 else {
        throw ShopifyCatalogError.rateLimited(retryAfterSeconds: retryAfterSeconds(headerValue: httpResponse?.value(forHTTPHeaderField: "Retry-After")))
    }
    guard httpResponse?.statusCode == 200,
          let result = (try? JSONDecoder().decode(ShopifyCatalogResponse<StructuredContent>.self, from: data))?.result,
          result.isError != true,
          let structuredContent = result.structuredContent
    else {
        throw ShopifyCatalogError.failed
    }
    return structuredContent
}

/// 検索語で、日本へ送る日本の店の商品を Global Catalog の `search_catalog` で探し、見つかった商品を返す (最大 `shopifyCatalogSearchLimit` 件)。
///
/// `endpointURL` は Global Catalog の入口 (`shopifyGlobalCatalogEndpointURL`。テストでは差し替える)。送るのは検索語・絞り込み・件数・`context`・プロフィールの URL だけ。
/// 商品バリアントの店 (`seller.url`) がホスト名の形でない商品と、商品バリアントの ID が数字で終わらない商品は、お気に入りにできないので返さない。
func searchShopifyCatalog(query: String, endpointURL: URL, urlSession: URLSession) async throws -> [ShopifyCatalogProduct] {
    try await (callShopifyCatalogTool(
        endpointURL: endpointURL,
        toolName: "search_catalog",
        catalogArguments: [
            "query": query,
            "filters": ["ships_to": ["country": "JP"], "ships_from": [["country": "JP"]]],
            "pagination": ["limit": shopifyCatalogSearchLimit],
        ],
        urlSession: urlSession
    ) as ShopifyCatalogSearchContent).products.filter { product in
        product.variants.first.map { shopifyCatalogShopDomain(variant: $0) != nil && shopifyVariantNumericID(variantGID: $0.id) != nil } == true
    }
}

/// 店の入口 (`https://{店のドメイン}/api/ucp/mcp`) を返す。店のドメインがホスト名の形でない時は nil。
///
/// 出典: https://shopify.dev/docs/agents/catalog の Storefront Catalog の「Endpoint」`https://{storeDomain}/api/ucp/mcp`。
func shopifyStorefrontCatalogEndpointURL(shopDomain: String) -> URL? {
    isHostName(text: shopDomain) ? URL(string: "https://\(shopDomain)/api/ucp/mcp") : nil
}

/// 店の入口の `get_product` で、商品の種類の選び方と、選んだ値の組の商品バリアントを返す。
///
/// `productID` は商品か商品バリアントの ID (Global Catalog の検索の結果の商品バリアントの ID をそのまま渡せる)。`selected` は選んだ値の組で、nil の時は店が選ぶ組を返す。
/// 返る商品の `variants` は、選ばれた組の 1 件だけ (2026-11-18 の実測。documents/research/2026-11-18/search-api-and-amazon-purchase-url.md「1 つの店の中の検索の実測」)。
/// 店のドメインがホスト名の形でない時と、商品バリアントが 1 件も返らない時は `ShopifyCatalogError.failed` を投げる。
func loadShopifyStorefrontProduct(
    shopDomain: String,
    productID: String,
    selected: [ShopifyCatalogSelectedOption]?,
    urlSession: URLSession
) async throws -> ShopifyCatalogProduct {
    guard let endpointURL = shopifyStorefrontCatalogEndpointURL(shopDomain: shopDomain) else {
        throw ShopifyCatalogError.failed
    }
    let productContent: ShopifyCatalogProductContent = try await callShopifyCatalogTool(
        endpointURL: endpointURL,
        toolName: "get_product",
        catalogArguments: (["id": productID] as [String: Any])
            .merging(selected.map { ["selected": $0.map { ["name": $0.name, "label": $0.label] }] as [String: Any] } ?? [:]) { id, _ in id },
        urlSession: urlSession
    )
    guard !productContent.product.variants.isEmpty else {
        throw ShopifyCatalogError.failed
    }
    return productContent.product
}

/// 商品バリアントの ID (`gid://shopify/ProductVariant/{数字}`) から数字の部分を返す。この形でない時は nil。
///
/// 数字の部分が購入画面の URL (`/cart/add?id={商品バリアントの ID}&quantity={個数}`) に入る ID (documents/research/2026-11-18/search-api-and-amazon-purchase-url.md の表「商品バリアントの ID」)。
func shopifyVariantNumericID(variantGID: String) -> String? {
    let prefix = "gid://shopify/ProductVariant/"
    guard variantGID.hasPrefix(prefix), isASCIIDigits(text: String(variantGID.dropFirst(prefix.count))) else {
        return nil
    }
    return String(variantGID.dropFirst(prefix.count))
}

/// 商品バリアントを売っている店のドメイン (`seller.url` のホスト。小文字) を返す。`seller` が無い時、`https` でない時、ホスト名の形でない時は nil。
/// Amazon が持つホスト (`amazonOwnedHost(host:)`) も nil にする。検索の結果から Amazon のドメインのお気に入りを作らないため
/// (https://github.com/bannzai/quickbuy/pull/50 。最初の公開では Amazon の対応を外した。https://github.com/bannzai/quickbuy/issues/88 )。
func shopifyCatalogShopDomain(variant: ShopifyCatalogVariant) -> String? {
    guard let urlComponents = variant.seller.flatMap({ URLComponents(string: $0.url) }),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil
    else {
        return nil
    }
    return (urlComponents.host?.lowercased()).flatMap { isHostName(text: $0) && !amazonOwnedHost(host: $0) ? $0 : nil }
}

/// 一覧と追加の画面に出す商品の画像の URL を返す (保存はしない)。`shopifyCatalogImageURLs(product:shopDomain:)` の最初の 1 件で、出せる画像が無い時は nil。
func shopifyCatalogImageURL(product: ShopifyCatalogProduct, shopDomain: String) -> URL? {
    shopifyCatalogImageURLs(product: product, shopDomain: shopDomain).first
}

/// 商品の詳細ページに出す商品の画像の URL を、Catalog が返した並びの順で返す (保存はしない)。
///
/// 返すのは、種別が `image` で、`https` で Shopify の CDN か店のドメインのもの (`shopifyProductImageURL(text:shopDomain:)`) だけ。動画 (`video`) は返さない。
/// 種別の無いものは画像として扱う (種別を見ていなかった時に出ていた画像を、応答から種別が欠けただけで出さなくしないため。2026-11-21 の実測の 21 件にはどれも種別があった)。
func shopifyCatalogImageURLs(product: ShopifyCatalogProduct, shopDomain: String) -> [URL] {
    (product.media ?? [])
        .filter { $0.type.map { $0 == "image" } ?? true }
        .compactMap { shopifyProductImageURL(text: $0.url, shopDomain: shopDomain) }
}

/// 商品の詳細ページに出す説明文を返す (保存はしない)。説明文が無い時と、タグを除くと文字が残らない時は nil。
///
/// 店の入口の値 (`html`) と Global Catalog の値 (`plain`) のうち、タグを除いて文字が残る最初のものを使う (店の入口の値が空の時は Global Catalog の値を使う)。
/// どちらの値にも HTML のタグが入りうるため (`ShopifyCatalogDescription` の実測)、`<style>` と `<script>` は中身ごと除き (閉じタグが無い時は、ほかのタグと同じにタグだけを除く)、`<br>` と段落・見出し・箇条書きの閉じタグを改行に替え、残りのタグ (`<` から `>` まで。属性の引用符の中の `>` はタグの終わりにしない) を除く。
/// 行ごとに前後の空白を除き、空の行は詰める。タグでない `<` と `>` に挟まれた文字も除かれる (説明文を HTML として描かず、文字としてだけ出すため)。
func shopifyCatalogDescriptionText(product: ShopifyCatalogProduct) -> String? {
    [product.description?.html, product.description?.plain]
        .compactMap { $0 }
        .map {
            $0.replacing(#/<(style|script)\b.*?</\1\s*>/#.ignoresCase().dotMatchesNewlines(), with: "")
                .replacing(#/<br\s*/?>|</(p|div|h[1-6]|li|tr)>/#.ignoresCase(), with: "\n")
                .replacing(#/<(?:"[^"]*"|'[^']*'|[^>"'])*>/#, with: "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        .first { !$0.isEmpty }
}

/// 画面に出している名前・説明文・種類の選び方・画像を、まだ出してよいかを返す。取得した時刻 `fetchedAt` から `shopifyCatalogContentCacheSeconds` 秒より前なら true。
func isShopifyCatalogContentFresh(fetchedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(fetchedAt) < shopifyCatalogContentCacheSeconds
}

/// 取得した時刻 `fetchedAt` の名前・説明文・種類の選び方・画像を出してよい残りの秒数を返す。もう出してはいけない時は 0。
func shopifyCatalogContentRemainingSeconds(fetchedAt: Date, now: Date) -> TimeInterval {
    max(0, shopifyCatalogContentCacheSeconds - now.timeIntervalSince(fetchedAt))
}

/// 商品の詳細ページに、名前・説明文・画像を出してよい商品が残っているかを返す。false の時、画面は閉じる。
///
/// 検索の結果 (取得した時刻 `searchFetchedAt`) か、店の入口の商品 (取得した時刻 `storefrontFetchedAt`。1 回も読み込めていない時は nil) の
/// どちらかが `isShopifyCatalogContentFresh` なら true。
func hasShopifyCatalogDetailFreshContent(searchFetchedAt: Date, storefrontFetchedAt: Date?, now: Date) -> Bool {
    isShopifyCatalogContentFresh(fetchedAt: searchFetchedAt, now: now)
        || storefrontFetchedAt.map { isShopifyCatalogContentFresh(fetchedAt: $0, now: now) } == true
}

/// 商品の詳細ページに出す商品の名前を返す。出してよい商品が無い時は nil。
///
/// 検索の結果の商品 `searchedProduct` (取得した時刻 `searchFetchedAt`) が `isShopifyCatalogContentFresh` の間は、その名前を返す (押したカードと同じ名前を出すため)。
/// 過ぎた後は、店の入口の商品 `storefrontProduct` (1 回も読み込めていない時は nil) が `isShopifyCatalogContentFresh` の時だけ、その名前を返す。
func shopifyCatalogDetailTitle(
    searchedProduct: ShopifyCatalogProduct,
    searchFetchedAt: Date,
    storefrontProduct: (product: ShopifyCatalogProduct, fetchedAt: Date)?,
    now: Date
) -> String? {
    if isShopifyCatalogContentFresh(fetchedAt: searchFetchedAt, now: now) {
        return searchedProduct.title
    }
    return storefrontProduct.flatMap { isShopifyCatalogContentFresh(fetchedAt: $0.fetchedAt, now: now) ? $0.product.title : nil }
}

/// 商品の詳細ページの価格の下に出す、その価格の商品バリアント `priceVariant` の名前を返す。出さない時は nil。
///
/// 店の入口の商品 `storefrontProduct` を読み込んだ後で、その商品に種類がある (`hasShopifyCatalogVariantChoices`) 時だけ返す (どの種類の価格かを示すため)。
/// 読み込む前は出さない (検索の結果の商品バリアントの名前は商品の名前と同じ値のため)。種類が無い商品でも出さない (店が付けた `Default Title` を出さないため)。
func shopifyCatalogDetailPriceVariantName(priceVariant: ShopifyCatalogVariant, storefrontProduct: ShopifyCatalogProduct?) -> String? {
    hasShopifyCatalogVariantChoices(options: storefrontProduct?.options) ? priceVariant.title : nil
}

/// 商品の詳細ページに出す説明文を返す。`products` (先に使う順に並べた、出してよい商品) のうち、説明文に文字がある最初の商品のものを返す。どれにも無ければ nil。
func shopifyCatalogDetailDescriptionText(products: [ShopifyCatalogProduct]) -> String? {
    products.lazy.compactMap { shopifyCatalogDescriptionText(product: $0) }.first
}

/// 商品の詳細ページに出す画像の URL の並びを返す。`products` (先に使う順に並べた、出してよい商品) のうち、出せる画像 (`shopifyCatalogImageURLs`) がある最初の商品のものを返す。どれにも無ければ空。
func shopifyCatalogDetailImageURLs(products: [ShopifyCatalogProduct], shopDomain: String) -> [URL] {
    products.lazy.map { shopifyCatalogImageURLs(product: $0, shopDomain: shopDomain) }.first { !$0.isEmpty } ?? []
}

/// 種類の選び方のうち、商品の詳細ページに並べるもの (選べる値が 2 つ以上あるもの) を返す。値が 1 つだけの選び方は、選ぶものが無いので並べない。
func shopifyCatalogChoiceOptions(options: [ShopifyCatalogOption]?) -> [ShopifyCatalogOption] {
    (options ?? []).filter { $0.values.count >= 2 }
}

/// 店の入口の呼び出しの結果 `result` を受けた後に、商品の詳細ページが持つ店の入口の商品と、出す失敗の理由を返す。
///
/// 読み込めた時は、返った商品を時刻 `now` に取得したものとして持ち、失敗の理由は無い。
/// 読み込めなかった時は、前に持っていた商品 `previous` (取得した時刻も) をそのまま持ち、失敗の理由を返す。
/// 前の商品の取得の時刻を進めないので、期限を過ぎた価格と在庫は `shopifyCatalogDetailPriceVariant` が出さないままになる。
func shopifyCatalogDetailLoaded(
    previous: (product: ShopifyCatalogProduct, fetchedAt: Date)?,
    result: Result<ShopifyCatalogProduct, ShopifyCatalogError>,
    now: Date
) -> (storefrontProduct: (product: ShopifyCatalogProduct, fetchedAt: Date)?, error: ShopifyCatalogError?) {
    switch result {
    case let .success(product):
        return ((product, now), nil)
    case let .failure(error):
        return (previous, error)
    }
}

/// 商品の詳細ページに価格と在庫を出してよい商品バリアントを返す。出してよいものが無い時は nil (価格と在庫を出さない)。
///
/// 店の入口の商品 (`storefrontProduct`) を読み込んだ後は、その商品バリアントを、取得した時刻 `storefrontFetchedAt` から `shopifyCatalogPriceCacheSeconds` 秒より前の時だけ返す。
/// 期限を過ぎた店の入口の値の代わりに、それより前に取得した検索の結果の値へは戻らない。
/// 読み込む前 (`storefrontProduct` か `storefrontFetchedAt` が nil) は、検索の結果の商品バリアント `searchedVariant` を、検索の結果を取得した時刻 `searchFetchedAt` から同じ秒数より前の時だけ返す。
func shopifyCatalogDetailPriceVariant(
    searchedVariant: ShopifyCatalogVariant,
    searchFetchedAt: Date,
    storefrontProduct: ShopifyCatalogProduct?,
    storefrontFetchedAt: Date?,
    now: Date
) -> ShopifyCatalogVariant? {
    guard let storefrontProduct, let storefrontFetchedAt else {
        return isShopifyCatalogPriceFresh(fetchedAt: searchFetchedAt, now: now) ? searchedVariant : nil
    }
    return isShopifyCatalogPriceFresh(fetchedAt: storefrontFetchedAt, now: now) ? storefrontProduct.variants.first : nil
}

/// 価格を画面に出す文字列にして返す (例: `¥2,700`)。通貨の最小の単位の整数を、その通貨の小数の桁で割って書く。
func shopifyCatalogPriceText(money: ShopifyCatalogMoney) -> String {
    (Decimal(money.amount) / pow(10, currencyFractionDigits(currencyCode: money.currency)))
        .formatted(.currency(code: money.currency).locale(Locale(identifier: "ja_JP")))
}

/// 通貨の小数の桁数 (JPY は 0、USD は 2) を返す。
private func currencyFractionDigits(currencyCode: String) -> Int {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .currency
    numberFormatter.currencyCode = currencyCode
    return numberFormatter.maximumFractionDigits
}

/// 画面に出している価格を、まだ出してよいかを返す。取得した時刻 `fetchedAt` から `shopifyCatalogPriceCacheSeconds` 秒より前なら true。
func isShopifyCatalogPriceFresh(fetchedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(fetchedAt) < shopifyCatalogPriceCacheSeconds
}

/// 取得した時刻 `fetchedAt` の価格を出してよい残りの秒数を返す。もう出してはいけない時は 0。
func shopifyCatalogPriceRemainingSeconds(fetchedAt: Date, now: Date) -> TimeInterval {
    max(0, shopifyCatalogPriceCacheSeconds - now.timeIntervalSince(fetchedAt))
}

/// Catalog の呼び出しが失敗した理由を、画面に出す文言にして `locale` の言語で返す。
func shopifyCatalogErrorMessage(error: ShopifyCatalogError, locale: Locale) -> String {
    switch error {
    case let .rateLimited(retryAfterSeconds?):
        String(localized: LocalizedStringResource("混み合っています\n\(retryAfterSeconds) 秒ほど待ってからもう一度お試しください", locale: locale))
    case .rateLimited(nil):
        String(localized: LocalizedStringResource("混み合っています\n少し待ってからもう一度お試しください", locale: locale))
    case .connectionFailed:
        String(localized: LocalizedStringResource("通信できませんでした\n電波の良い所でもう一度お試しください", locale: locale))
    case .failed:
        String(localized: LocalizedStringResource("商品を読み込めませんでした\n少し待ってからもう一度お試しください", locale: locale))
    }
}

/// 店 `shopDomain` の商品バリアント `variant` (店の入口が返したもの) を、お気に入りが持つ商品の指し方にして返す。商品バリアントの ID が数字で終わらない時は nil (購入画面の URL を組み立てられず、お気に入りにできない)。
func shopifyCatalogShopifyProduct(shopDomain: String, variant: ShopifyCatalogVariant) -> ShopifyProduct? {
    shopifyVariantNumericID(variantGID: variant.id).map { ShopifyProduct(shopDomain: shopDomain, variantID: $0) }
}

/// 検索の結果から開いた追加の画面で、今選んでいる値の組の商品バリアント `variant` (店の入口が返したもの) から、保存するお気に入りを作って返す。保存はしない。
///
/// 店のドメインは `shopDomain` (`seller.url` のホスト。追加の画面で利用者に見せたもの)、名前は `name` (利用者が確かめた名前)、個数は `quantity`、識別子は `favoriteID`。
/// 商品バリアントの ID が数字で終わらない時は nil (`shopifyCatalogShopifyProduct`)。
/// 商品バリアントの名前は、種類の選び方に値が 2 つ以上あるもの (`hasVariantChoices`) がある商品でだけ入れる (1 つだけの商品では店が付けた `Default Title` を見分けに使わないため nil)。
/// Catalog が返した画像の URL と価格は入れない (Shopify の「Caching limits」の時間を超えて持たないため。documents/DIRECTION.md「決めたこと」)。
func shopifyCatalogFavorite(
    shopDomain: String,
    name: String,
    hasVariantChoices: Bool,
    variant: ShopifyCatalogVariant,
    quantity: Int,
    favoriteID: UUID
) -> Favorite? {
    shopifyCatalogShopifyProduct(shopDomain: shopDomain, variant: variant).map {
        Favorite(
            id: favoriteID,
            name: name,
            variantName: hasVariantChoices ? variant.title : nil,
            imageURL: nil,
            quantity: quantity,
            product: .shopify($0),
            reminder: nil
        )
    }
}

/// 検索の結果から開いた追加の画面で、今選んでいる値の組の商品バリアント `variant` と同じ店・同じ種類の、保存済みのお気に入りを返す。無い時と、`variant` が nil (読み込む前) の時は nil。
///
/// `savedFavorites` は追加の画面を開いた時に読んだ保存済みのお気に入り。
func shopifyCatalogSavedFavorite(savedFavorites: [Favorite], shopDomain: String, variant: ShopifyCatalogVariant?) -> Favorite? {
    variant
        .flatMap { shopifyCatalogShopifyProduct(shopDomain: shopDomain, variant: $0) }
        .flatMap { shopifyFavorite(favorites: savedFavorites, shopifyProduct: $0) }
}

/// 検索の結果から開いた追加の画面で、店の入口が商品バリアント `loadedVariant` を返した後の個数を返す。
///
/// 前に出していた商品バリアント (ID が `shownVariantID`。読み込む前は nil) と同じ時は、利用者が決めた個数 `quantity` のまま (価格の期限の読み直しで個数を戻さない)。
/// 違う時は、同じ店・同じ種類の保存済みのお気に入り (`shopifyCatalogSavedFavorite`) の個数から始め、保存済みでなければ `initialVariantQuantity` から始める。
func shopifyCatalogAdditionQuantity(
    shownVariantID: String?,
    quantity: Int,
    loadedVariant: ShopifyCatalogVariant,
    shopDomain: String,
    savedFavorites: [Favorite]
) -> Int {
    shownVariantID == loadedVariant.id
        ? quantity
        : shopifyCatalogSavedFavorite(savedFavorites: savedFavorites, shopDomain: shopDomain, variant: loadedVariant)?.quantity ?? initialVariantQuantity
}

/// 検索の結果から開いた追加の画面の、保存するボタンを押せるかを返す。
///
/// 押せるのは、名前が保存できて (`isFavoriteNameSavable(name:)`)、店の入口を呼んでいる間 (`isLoading`) でなく、今選んでいる値の組の商品バリアント `variant` が読み込めていて (nil でない)、
/// お気に入りにできる (`shopifyCatalogShopifyProduct` が nil でない) 時だけ。読み込み中は、選び直した値の組と違う種類を保存しないために押せない。
func isShopifyCatalogAdditionSavable(name: String, shopDomain: String, variant: ShopifyCatalogVariant?, isLoading: Bool) -> Bool {
    isFavoriteNameSavable(name: name) && !isLoading && variant.flatMap { shopifyCatalogShopifyProduct(shopDomain: shopDomain, variant: $0) } != nil
}

/// 検索の結果から開いた追加の画面の、保存するボタンの文言を `locale` の言語で返す。
///
/// 今選んでいる種類が保存済み (`isSaved`) の時は、押すと行を足さずに個数を書き換えるので `お気に入りの個数を変更`、保存済みでない時は `お気に入りに追加`。
func shopifyCatalogAdditionButtonTitle(isSaved: Bool, locale: Locale) -> String {
    isSaved
        ? String(localized: LocalizedStringResource("お気に入りの個数を変更", locale: locale))
        : String(localized: LocalizedStringResource("お気に入りに追加", locale: locale))
}

/// 検索窓の文字列から、検索に使う語 (前後の空白と改行を除いたもの) を返す。空になる時は検索しないので nil。
func shopifyCatalogSearchQuery(text: String) -> String? {
    Optional(text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
}

/// 検索の結果を自動で取り直すかを返す。検索中と、前の検索が失敗して文言を出している間 (`isShowingError`) は取り直さない。
/// それ以外で、まだ結果が無い (`fetchedAt` が nil) 時と、価格を出してよい時間を過ぎた時は取り直す。
/// 失敗の後は、利用者の「もう一度検索する」か検索し直しを待つ (HTTP 429 の間に呼ぶ回数を増やさず、`Retry-After` の文言と合わせるため)。
func shouldRefreshShopifyCatalogSearch(fetchedAt: Date?, isSearching: Bool, isShowingError: Bool, now: Date) -> Bool {
    !isSearching && !isShowingError && fetchedAt.map { !isShopifyCatalogPriceFresh(fetchedAt: $0, now: now) } ?? true
}

/// 種類の選び方に、値が 2 つ以上あるものがあるかを返す (商品バリアントが 2 つ以上ある商品か)。
func hasShopifyCatalogVariantChoices(options: [ShopifyCatalogOption]?) -> Bool {
    options?.contains { $0.values.count >= 2 } == true
}
