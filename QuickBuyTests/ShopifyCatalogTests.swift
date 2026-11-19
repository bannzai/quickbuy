import Foundation
import Testing
@testable import QuickBuy

/// Shopify の Catalog の検索と、検索の結果からのお気に入りの追加のテスト。
///
/// 通信は `StubURLProtocol` (AddFavoriteTests.swift) で差し替え、実際の Catalog には出ない。
/// `StubURLProtocol` の登録は URL ごとで、テストが並んで動くため、テストごとに別の入口の URL を使う。
@Suite struct ShopifyCatalogTests {
    /// 2026-11-19 の Global Catalog の `search_catalog` の実測の応答を縮めたもの。
    /// 1 件目は chimney-coffee.com の商品、2 件目は店の URL が `http` の商品、3 件目は商品バリアントの ID の形が違う商品。
    static let searchResponseJSON = Data(#"""
    {"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"products":[
      {"id":"gid://shopify/p/abc","title":"コーヒー豆 200gセット",
       "media":[{"url":"https://cdn.shopify.com/s/files/1/0580/1692/3826/files/20.jpg"}],
       "options":[{"name":"BITTER・MILD","values":[{"label":"【BITTER】"},{"label":"【MILD】"}]}],
       "variants":[{"id":"gid://shopify/ProductVariant/45476745412786","title":"コーヒー豆 200gセット",
                    "price":{"amount":2700,"currency":"JPY"},"availability":{"available":true},
                    "seller":{"url":"https://Chimney-Coffee.com"}}]},
      {"id":"gid://shopify/p/def","title":"店の URL が http の商品",
       "variants":[{"id":"gid://shopify/ProductVariant/1","title":"x","seller":{"url":"http://example.com"}}]},
      {"id":"gid://shopify/p/ghi","title":"商品バリアントの ID の形が違う商品",
       "variants":[{"id":"gid://shopify/p/ghi/v1","title":"x","seller":{"url":"https://example.com"}}]}
    ]}}}
    """#.utf8)

    /// 店の入口の `get_product` の実測の応答 (2026-11-19、chimney-coffee.com、MILD・粉を選んだ時) を縮めたもの。
    static let storefrontProductJSON = Data(#"""
    {"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"product":{
      "id":"gid://shopify/Product/8503532617906","title":"コーヒー豆 200gセット",
      "options":[{"name":"BITTER・MILD","values":[{"label":"【BITTER】コーヒー豆（深煎り）200g"},{"label":"【MILD】コーヒー豆（中深煎り）200g"}]},
                 {"name":"豆・粉","values":[{"label":"豆"},{"label":"粉"}]}],
      "selected":[{"name":"BITTER・MILD","label":"【MILD】コーヒー豆（中深煎り）200g"},{"name":"豆・粉","label":"粉"}],
      "variants":[{"id":"gid://shopify/ProductVariant/45476749770930","title":"【MILD】コーヒー豆（中深煎り）200g / 粉",
                   "price":{"amount":2700,"currency":"JPY"}}]}}}}
    """#.utf8)

    /// テストごとに別の Global Catalog の入口の URL を返す (`StubURLProtocol` の登録が URL ごとのため)。
    static func endpointURL(name: String) -> URL {
        URL(string: "https://catalog.test/\(name)")!
    }

    /// Catalog へ送る本文は、検索語・日本の context・自分のプロフィールの URL だけを持つ。
    @Test func 検索の本文にプロフィールのURLと日本の文脈と検索語だけが入る() throws {
        let json = try #require(try JSONSerialization.jsonObject(
            with: shopifyCatalogToolCallBody(toolName: "search_catalog", catalogArguments: ["query": "コーヒー豆"])
        ) as? [String: Any])
        let params = try #require(json["params"] as? [String: Any])
        let arguments = try #require(params["arguments"] as? [String: Any])
        let catalog = try #require(arguments["catalog"] as? [String: Any])
        #expect(json["method"] as? String == "tools/call")
        #expect(params["name"] as? String == "search_catalog")
        #expect(catalog["query"] as? String == "コーヒー豆")
        #expect(catalog["context"] as? [String: String] == ["address_country": "JP", "language": "ja", "currency": "JPY"])
        #expect((arguments["meta"] as? [String: [String: String]])?["ucp-agent"]?["profile"] == "https://cdn.jsdelivr.net/gh/bannzai/quickbuy@main/ucp/agent-profile.json")
        // 送るのは検索語・context・プロフィールの URL だけ (プライバシーポリシーの記載と合わせる)。
        #expect(Set(catalog.keys) == ["query", "context"])
        #expect(Set(arguments.keys) == ["catalog", "meta"])
    }

    /// 店の URL が https でない商品と、商品バリアントの ID が数字で終わらない商品は検索の結果から外れる。
    @Test func 検索はお気に入りにできる商品だけを返す() async throws {
        let endpointURL = Self.endpointURL(name: "search-ok")
        StubURLProtocol.stubResponses.withLock { $0[endpointURL.absoluteString] = .http(statusCode: 200, body: Self.searchResponseJSON) }
        let products = try await searchShopifyCatalog(query: "コーヒー豆", endpointURL: endpointURL, urlSession: StubURLProtocol.urlSession())
        #expect(products.map(\.title) == ["コーヒー豆 200gセット"])
        #expect(products.first?.variants.first.flatMap(shopifyCatalogShopDomain(variant:)) == "chimney-coffee.com")
        #expect(products.first?.variants.first?.price == ShopifyCatalogMoney(amount: 2700, currency: "JPY"))
    }

    /// HTTP 429・HTTP 500・tool のエラー (`isError`)・JSON-RPC のエラー・通信の失敗が、それぞれ別の失敗になる。
    @Test func 検索の失敗は理由ごとに分かれる() async throws {
        let rateLimitedURL = Self.endpointURL(name: "search-429")
        let failedURL = Self.endpointURL(name: "search-500")
        let toolErrorURL = Self.endpointURL(name: "search-tool-error")
        let unreachableURL = Self.endpointURL(name: "search-unreachable")
        let jsonRPCErrorURL = Self.endpointURL(name: "search-jsonrpc-error")
        StubURLProtocol.stubResponses.withLock {
            $0[rateLimitedURL.absoluteString] = .http(statusCode: 429, body: Data())
            $0[failedURL.absoluteString] = .http(statusCode: 500, body: Self.searchResponseJSON)
            $0[toolErrorURL.absoluteString] = .http(
                statusCode: 200,
                body: Data(#"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Missing required arguments: catalog"}],"isError":true}}"#.utf8)
            )
            $0[unreachableURL.absoluteString] = .connectionFailure
            $0[jsonRPCErrorURL.absoluteString] = .http(
                statusCode: 200,
                body: Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"UCP discovery failed","data":{"code":"profile_malformed"}}}"#.utf8)
            )
        }
        await #expect(throws: ShopifyCatalogError.failed) {
            try await searchShopifyCatalog(query: "a", endpointURL: jsonRPCErrorURL, urlSession: StubURLProtocol.urlSession())
        }
        await #expect(throws: ShopifyCatalogError.rateLimited(retryAfterSeconds: nil)) {
            try await searchShopifyCatalog(query: "a", endpointURL: rateLimitedURL, urlSession: StubURLProtocol.urlSession())
        }
        await #expect(throws: ShopifyCatalogError.failed) {
            try await searchShopifyCatalog(query: "a", endpointURL: failedURL, urlSession: StubURLProtocol.urlSession())
        }
        await #expect(throws: ShopifyCatalogError.failed) {
            try await searchShopifyCatalog(query: "a", endpointURL: toolErrorURL, urlSession: StubURLProtocol.urlSession())
        }
        await #expect(throws: ShopifyCatalogError.connectionFailed) {
            try await searchShopifyCatalog(query: "a", endpointURL: unreachableURL, urlSession: StubURLProtocol.urlSession())
        }
    }

    /// 店の入口が返した、選んだ値の組と 1 件の商品バリアントを読む。
    @Test func 店の入口のget_productで選んだ値の組の商品バリアントを読む() async throws {
        let shopDomain = "storefront-ok.example.com"
        StubURLProtocol.stubResponses.withLock { $0["https://\(shopDomain)/api/ucp/mcp"] = .http(statusCode: 200, body: Self.storefrontProductJSON) }
        let product = try await loadShopifyStorefrontProduct(
            shopDomain: shopDomain,
            productID: "gid://shopify/Product/8503532617906",
            selected: [ShopifyCatalogSelectedOption(name: "豆・粉", label: "粉")],
            urlSession: StubURLProtocol.urlSession()
        )
        #expect(product.variants.map(\.id) == ["gid://shopify/ProductVariant/45476749770930"])
        #expect(product.selected?.last == ShopifyCatalogSelectedOption(name: "豆・粉", label: "粉"))
    }

    /// 店の入口が商品バリアントを 1 件も返さない時は、選べる種類が無いので失敗にする。
    @Test func 商品バリアントが返らない店の入口の応答は失敗にする() async {
        let shopDomain = "storefront-empty.example.com"
        StubURLProtocol.stubResponses.withLock {
            $0["https://\(shopDomain)/api/ucp/mcp"] = .http(
                statusCode: 200,
                body: Data(#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"product":{"id":"p","title":"t","variants":[]}}}}"#.utf8)
            )
        }
        await #expect(throws: ShopifyCatalogError.failed) {
            try await loadShopifyStorefrontProduct(shopDomain: shopDomain, productID: "p", selected: nil, urlSession: StubURLProtocol.urlSession())
        }
    }

    /// ホスト名の形でない店のドメインでは通信せずに失敗にする (似ているが通る側はホスト名の形の店のドメイン)。
    @Test func 店のドメインがホスト名の形でない時は店の入口を呼ばない() async {
        await #expect(throws: ShopifyCatalogError.failed) {
            try await loadShopifyStorefrontProduct(shopDomain: "evil.example.com/path", productID: "x", selected: nil, urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains("evil.example.com") } } == [])
        #expect(shopifyStorefrontCatalogEndpointURL(shopDomain: "chimney-coffee.com")?.absoluteString == "https://chimney-coffee.com/api/ucp/mcp")
    }

    /// `gid://shopify/ProductVariant/{数字}` の形だけが通り、空・英字混じり・商品の ID・gid でない文字列は nil になる。
    @Test(arguments: [
        ("gid://shopify/ProductVariant/45476745412786", "45476745412786"),
        ("gid://shopify/ProductVariant/1", "1"),
        ("gid://shopify/ProductVariant/", nil),
        ("gid://shopify/ProductVariant/12a", nil),
        ("gid://shopify/Product/45476745412786", nil),
        ("45476745412786", nil),
    ] as [(String, String?)])
    func 商品バリアントのIDは数字で終わる形だけ数字を取り出す(variantGID: String, expectedNumericID: String?) {
        #expect(shopifyVariantNumericID(variantGID: variantGID) == expectedNumericID)
    }

    /// `seller.url` から、https でポートと認証情報の無いホスト名だけを小文字で取り出す。
    @Test(arguments: [
        ("https://chimney-coffee.com", "chimney-coffee.com"),
        ("https://WWW.SotCoffee.com/", "www.sotcoffee.com"),
        ("http://chimney-coffee.com", nil),
        ("https://chimney-coffee.com:8443", nil),
        ("https://user@chimney-coffee.com", nil),
        ("chimney-coffee.com", nil),
    ] as [(String, String?)])
    func 店のドメインはhttpsのホスト名の形だけ取り出す(sellerURLText: String, expectedShopDomain: String?) {
        #expect(shopifyCatalogShopDomain(variant: ShopifyCatalogVariant(
            id: "gid://shopify/ProductVariant/1",
            title: "x",
            price: nil,
            availability: nil,
            seller: ShopifyCatalogVariant.Seller(url: sellerURLText)
        )) == expectedShopDomain)
    }

    /// `seller` を返さない商品バリアント (店の入口の応答) からは店のドメインを取らない。
    @Test func 店の無い商品バリアントから店のドメインは取れない() {
        #expect(shopifyCatalogShopDomain(variant: ShopifyCatalogVariant(id: "gid://shopify/ProductVariant/1", title: "x", price: nil, availability: nil, seller: nil)) == nil)
    }

    /// `Retry-After` は 0 以上の整数の秒数だけを読み、負の数・日時の形・無い時は nil になる。
    @Test(arguments: [("120", 120), ("0", 0), (" 5 ", 5), ("-1", nil), ("Wed, 21 Oct 2015 07:28:00 GMT", nil), (nil, nil)] as [(String?, Int?)])
    func Retry_Afterは0以上の秒数だけ読む(headerValue: String?, expectedSeconds: Int?) {
        #expect(retryAfterSeconds(headerValue: headerValue) == expectedSeconds)
    }

    /// 取得から 10 分ちょうどで価格を取り直す境界 (Shopify の「Caching limits」の 10 分)。
    @Test func 価格は取得から10分より前だけ出してよい() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000_000)
        #expect(isShopifyCatalogPriceFresh(fetchedAt: fetchedAt, now: fetchedAt))
        #expect(isShopifyCatalogPriceFresh(fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(10 * 60 - 1)))
        #expect(!isShopifyCatalogPriceFresh(fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(10 * 60)))
    }

    /// 円は補助の単位が無く、米ドルは 100 分の 1 で書く。
    @Test func 価格は通貨の最小の単位から書く() {
        // 円は補助の単位が無く、米ドルは 100 分の 1 (documents/research/2026-11-18/search-api-and-amazon-purchase-url.md の「minor currency units」)。
        #expect(shopifyCatalogPriceText(money: ShopifyCatalogMoney(amount: 2700, currency: "JPY")).contains("2,700"))
        #expect(shopifyCatalogPriceText(money: ShopifyCatalogMoney(amount: 2700, currency: "USD")).contains("27.00"))
    }

    /// 選び直した種類の選び方の値だけが替わり、無い選び方は末尾に足される。
    @Test func 選び直した値だけを替える() {
        let bitter = ShopifyCatalogSelectedOption(name: "味", label: "BITTER")
        #expect(reselectedOptions(selected: [bitter, ShopifyCatalogSelectedOption(name: "挽き", label: "豆")], optionName: "挽き", label: "粉") == [
            bitter, ShopifyCatalogSelectedOption(name: "挽き", label: "粉"),
        ])
        #expect(reselectedOptions(selected: [bitter], optionName: "挽き", label: "粉") == [bitter, ShopifyCatalogSelectedOption(name: "挽き", label: "粉")])
    }

    /// 値が 1 つだけの選び方 (`Default Title`) しか無い商品は、種類が無い商品として扱う。
    @Test func 種類の選び方に値が2つ以上ある時だけ種類がある() {
        #expect(!hasShopifyCatalogVariantChoices(options: nil))
        #expect(!hasShopifyCatalogVariantChoices(options: [ShopifyCatalogOption(name: "Title", values: [.init(label: "Default Title")])]))
        #expect(hasShopifyCatalogVariantChoices(options: [
            ShopifyCatalogOption(name: "Title", values: [.init(label: "Default Title")]),
            ShopifyCatalogOption(name: "挽き", values: [.init(label: "豆"), .init(label: "粉")]),
        ]))
    }

    /// Catalog の画像の URL と価格は保存せず、識別子の無い種類はお気に入りにしない。
    @Test func 検索の結果から作るお気に入りはCatalogの画像と価格を持たない() {
        let firstID = UUID()
        let secondID = UUID()
        #expect(shopifyCatalogFavorites(
            shopDomain: "chimney-coffee.com",
            name: "いつものコーヒー",
            hasVariantChoices: true,
            selectedVariants: [
                ShopifyCatalogSelectedVariant(variantID: "45476749770930", title: "MILD / 粉"),
                ShopifyCatalogSelectedVariant(variantID: "45476745412786", title: "BITTER / 豆"),
                ShopifyCatalogSelectedVariant(variantID: "999", title: "識別子の無い種類"),
            ],
            quantitiesByVariantID: ["45476749770930": 2, "45476745412786": 1, "999": 1],
            favoriteIDsByVariantID: ["45476749770930": firstID, "45476745412786": secondID]
        ) == [
            Favorite(
                id: firstID, name: "いつものコーヒー", variantName: "MILD / 粉", imageURL: nil, quantity: 2,
                product: .shopify(ShopifyProduct(shopDomain: "chimney-coffee.com", variantID: "45476749770930")), reminder: nil
            ),
            Favorite(
                id: secondID, name: "いつものコーヒー", variantName: "BITTER / 豆", imageURL: nil, quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "chimney-coffee.com", variantID: "45476745412786")), reminder: nil
            ),
        ])
    }

    /// 検索の結果から追加の画面を通って保存したお気に入りの購入画面の URL は `https://{seller.url のホスト}/cart/{商品バリアントの ID}:{個数}`。
    @Test func 検索の結果から保存したお気に入りは店のドメインと商品バリアントのIDと個数で購入画面を開く() async throws {
        let endpointURL = Self.endpointURL(name: "search-save")
        StubURLProtocol.stubResponses.withLock { $0[endpointURL.absoluteString] = .http(statusCode: 200, body: Self.searchResponseJSON) }
        let searchedVariant = try #require(try await searchShopifyCatalog(query: "コーヒー豆", endpointURL: endpointURL, urlSession: StubURLProtocol.urlSession()).first?.variants.first)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-favorites-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try finishFavoriteAddition(
            choice: .add,
            favorites: shopifyCatalogFavorites(
                shopDomain: try #require(shopifyCatalogShopDomain(variant: searchedVariant)),
                name: "いつものコーヒー",
                hasVariantChoices: true,
                selectedVariants: [ShopifyCatalogSelectedVariant(variantID: try #require(shopifyVariantNumericID(variantGID: searchedVariant.id)), title: "BITTER / 豆")],
                quantitiesByVariantID: ["45476745412786": 3],
                favoriteIDsByVariantID: ["45476745412786": UUID()]
            ),
            fileURL: fileURL
        )
        let savedFavorites = try loadFavorites(fileURL: fileURL)
        #expect(savedFavorites.map(\.product) == [.shopify(ShopifyProduct(shopDomain: "chimney-coffee.com", variantID: "45476745412786"))])
        #expect(savedFavorites.map(\.imageURL) == [nil])
        #expect(savedFavorites.first.flatMap(purchaseURL(favorite:))?.absoluteString == "https://chimney-coffee.com/cart/45476745412786:3")
    }

    /// 種類の選び方が無い商品では、店が付けた `Default Title` を種類の名前に入れない。
    @Test func 種類の無い商品のお気に入りは種類の名前を持たない() {
        #expect(shopifyCatalogFavorites(
            shopDomain: "chimney-coffee.com",
            name: "豆",
            hasVariantChoices: false,
            selectedVariants: [ShopifyCatalogSelectedVariant(variantID: "1", title: "Default Title")],
            quantitiesByVariantID: ["1": 1],
            favoriteIDsByVariantID: ["1": UUID()]
        ).map(\.variantName) == [nil])
    }

    /// 画像は Shopify の CDN か店のドメインのものだけを出し、ほかのホストの画像は出さない。
    @Test func 一覧の画像はShopifyのCDNか店のドメインのものだけ出す() throws {
        #expect(shopifyCatalogImageURL(
            product: try JSONDecoder().decode(ShopifyCatalogProduct.self, from: Data(#"{"id":"p","title":"t","media":[{"url":"https://cdn.shopify.com/a.jpg"}],"variants":[]}"#.utf8)),
            shopDomain: "chimney-coffee.com"
        )?.absoluteString == "https://cdn.shopify.com/a.jpg")
        #expect(shopifyCatalogImageURL(
            product: try JSONDecoder().decode(ShopifyCatalogProduct.self, from: Data(#"{"id":"p","title":"t","media":[{"url":"https://tracker.example.com/a.jpg"}],"variants":[]}"#.utf8)),
            shopDomain: "chimney-coffee.com"
        ) == nil)
    }
}
