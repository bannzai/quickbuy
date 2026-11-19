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

/// Catalog が返す画像。
struct ShopifyCatalogMedia: Decodable, Equatable {
    /// 画像の URL の文字列。
    let url: String
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
    /// 商品の画像の並び。
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
/// 数字の部分が購入画面の URL (`/cart/{商品バリアントの ID}:{個数}`) に入る ID (documents/research/2026-11-18/search-api-and-amazon-purchase-url.md の表「商品バリアントの ID」)。
func shopifyVariantNumericID(variantGID: String) -> String? {
    let prefix = "gid://shopify/ProductVariant/"
    guard variantGID.hasPrefix(prefix), isASCIIDigits(text: String(variantGID.dropFirst(prefix.count))) else {
        return nil
    }
    return String(variantGID.dropFirst(prefix.count))
}

/// 商品バリアントを売っている店のドメイン (`seller.url` のホスト。小文字) を返す。`seller` が無い時、`https` でない時、ホスト名の形でない時は nil。
func shopifyCatalogShopDomain(variant: ShopifyCatalogVariant) -> String? {
    guard let urlComponents = variant.seller.flatMap({ URLComponents(string: $0.url) }),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil
    else {
        return nil
    }
    return (urlComponents.host?.lowercased()).flatMap { isHostName(text: $0) ? $0 : nil }
}

/// 一覧と追加の画面に出す商品の画像の URL を返す (保存はしない)。最初の画像が `https` で Shopify の CDN か店のドメインのものでない時は nil。
func shopifyCatalogImageURL(product: ShopifyCatalogProduct, shopDomain: String) -> URL? {
    product.media?.first.flatMap { shopifyProductImageURL(text: $0.url, shopDomain: shopDomain) }
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

/// 検索の結果に出している価格を、まだ出してよいかを返す。取得した時刻 `fetchedAt` から `shopifyCatalogPriceCacheSeconds` 秒より前なら true。
func isShopifyCatalogPriceFresh(fetchedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(fetchedAt) < shopifyCatalogPriceCacheSeconds
}

/// Catalog の呼び出しが失敗した理由を、画面に出す文言にして返す。
func shopifyCatalogErrorMessage(error: ShopifyCatalogError) -> String {
    switch error {
    case let .rateLimited(retryAfterSeconds?):
        "混み合っています\n\(retryAfterSeconds) 秒ほど待ってからもう一度お試しください"
    case .rateLimited(nil):
        "混み合っています\n少し待ってからもう一度お試しください"
    case .connectionFailed:
        "通信できませんでした\n電波の良い所でもう一度お試しください"
    case .failed:
        "商品を読み込めませんでした\n少し待ってからもう一度お試しください"
    }
}

/// 検索の結果から開いた追加の画面で選んだ商品バリアント。
struct ShopifyCatalogSelectedVariant: Equatable {
    /// 商品バリアントの ID の数字の部分。
    let variantID: String
    /// 商品バリアントの名前 (店の入口が返した `title`)。
    let title: String
}

/// 検索の結果から開いた追加の画面で選んだ商品バリアントごとに 1 件ずつ、保存するお気に入りを作って返す。保存はしない。
///
/// 店のドメインは `shopDomain` (`seller.url` のホスト。追加の画面で利用者に見せたもの)、名前は `name` (利用者が確かめた名前)、個数は `quantitiesByVariantID` の値。
/// 商品バリアントの名前は、種類の選び方に値が 2 つ以上あるもの (`hasVariantChoices`) がある商品でだけ入れる (1 つだけの商品では店が付けた `Default Title` を見分けに使わないため nil)。
/// Catalog が返した画像の URL と価格は入れない (Shopify の「Caching limits」の時間を超えて持たないため。documents/DIRECTION.md「決めたこと」)。
/// 識別子は `favoriteIDsByVariantID` の値で、無い商品バリアントのお気に入りは作らない。並びは `selectedVariants` の順。
func shopifyCatalogFavorites(
    shopDomain: String,
    name: String,
    hasVariantChoices: Bool,
    selectedVariants: [ShopifyCatalogSelectedVariant],
    quantitiesByVariantID: [String: Int],
    favoriteIDsByVariantID: [String: UUID]
) -> [Favorite] {
    selectedVariants.compactMap { selectedVariant in
        guard let quantity = quantitiesByVariantID[selectedVariant.variantID], let favoriteID = favoriteIDsByVariantID[selectedVariant.variantID] else {
            return nil
        }
        return Favorite(
            id: favoriteID,
            name: name,
            variantName: hasVariantChoices ? selectedVariant.title : nil,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: shopDomain, variantID: selectedVariant.variantID)),
            reminder: nil
        )
    }
}

/// 種類の選び方に、値が 2 つ以上あるものがあるかを返す (商品バリアントが 2 つ以上ある商品か)。
func hasShopifyCatalogVariantChoices(options: [ShopifyCatalogOption]?) -> Bool {
    options?.contains { $0.values.count >= 2 } == true
}
