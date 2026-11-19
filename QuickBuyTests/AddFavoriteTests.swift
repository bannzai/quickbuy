import Foundation
import os
import Testing
@testable import QuickBuy

/// テストが決めた応答を返す、通信の差し替え。実際のネットワークには出ない。
///
/// class にしているのは、`URLSessionConfiguration.protocolClasses` が `URLProtocol` のサブクラスを求めるため。
final class StubURLProtocol: URLProtocol {
    /// 差し替えが返す応答。
    enum StubResponse: Sendable {
        /// 指定した HTTP ステータスと本文の応答。
        case http(statusCode: Int, body: Data)
        /// 指定した HTTP ステータス・ヘッダー・本文の応答。
        case httpWithHeaders(statusCode: Int, headerFields: [String: String], body: Data)
        /// 通信の失敗 (圏外など)。
        case connectionFailure
        /// 指定した URL への転送 (HTTP 302)。
        case redirect(locationURLText: String)
    }

    /// URL の文字列ごとの、返す応答。
    static let stubResponses = OSAllocatedUnfairLock<[String: StubResponse]>(initialState: [:])
    /// 差し替えが受けたリクエストの URL の文字列 (受けた順)。
    static let requestedURLTexts = OSAllocatedUnfairLock<[String]>(initialState: [])
    /// 差し替えが受けたリクエストの本文 (URL の文字列ごとに、受けた順)。本文の無いリクエストは記録しない。
    static let requestedBodiesByURLText = OSAllocatedUnfairLock<[String: [Data]]>(initialState: [:])

    /// この差し替えを通る `URLSession` を返す。
    static func urlSession() -> URLSession {
        let urlSessionConfiguration = URLSessionConfiguration.ephemeral
        urlSessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: urlSessionConfiguration)
    }

    /// すべてのリクエストをこの差し替えで受ける。
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    /// リクエストを変えずに返す。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// 登録された応答を返す。URL に応答が登録されていない時は通信の失敗にする。
    override func startLoading() {
        let requestedURLText = request.url?.absoluteString ?? ""
        Self.requestedURLTexts.withLock { $0.append(requestedURLText) }
        // URLSession は送る本文を `httpBody` ではなく `httpBodyStream` に移して渡すため、ストリームから読む。
        if let requestedBody = request.httpBodyStream.map(readAllData(inputStream:)) {
            Self.requestedBodiesByURLText.withLock { $0[requestedURLText, default: []].append(requestedBody) }
        }
        switch Self.stubResponses.withLock({ $0[requestedURLText] }) {
        case let .http(statusCode, body):
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .httpWithHeaders(statusCode, headerFields, body):
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headerFields)!,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .redirect(locationURLText):
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: URL(string: locationURLText)!),
                redirectResponse: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": locationURLText])!
            )
            // 転送を伝えた後は、この読み込みを取り消しの失敗で終える (転送に従う時は、転送先を読む新しい読み込みが別に始まる)。
            // 終えないと、転送に従わなかった通信が終わらない (https://github.com/bannzai/quickbuy/actions/runs/44241340789 で 60 秒の上限に達した)。
            client?.urlProtocol(self, didFailWithError: CocoaError(.userCancelled))
        case .connectionFailure, nil:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    /// 途中で止めるものが無いため何もしない。
    override func stopLoading() {}
}

/// `inputStream` を最後まで読んだ内容を返す。
private func readAllData(inputStream: InputStream) -> Data {
    inputStream.open()
    defer { inputStream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while inputStream.hasBytesAvailable {
        let readCount = inputStream.read(&buffer, maxLength: buffer.count)
        guard readCount > 0 else {
            break
        }
        data.append(buffer, count: readCount)
    }
    return data
}

/// 商品ページの URL から確認の画面に出す商品を取得する流れと、確認の画面の「お気に入りに追加」「やめる」が保存に与える結果を確かめる。
struct AddFavoriteTests {
    /// テストごとに別の店のドメインを返す (テストどうしが同じ URL の応答を取り合わないため)。
    private func uniqueShopDomain() -> String {
        "shop-\(UUID().uuidString.lowercased()).example"
    }

    /// 商品バリアントが 1 つの商品「コーヒー豆 200g」(商品バリアントの ID は 70881412) の JSON。
    private let productJSON = Data(
        #"{"title":"コーヒー豆 200g","featured_image":"//cdn.shopify.com/beans.png","variants":[{"id":70881412,"title":"Default Title","available":true}]}"#.utf8
    )

    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    // MARK: - 確認の画面に出す商品の取得

    /// 前後に空白と改行が付いた商品ページの URL から、その店の `/products/{商品のハンドル}.js` だけを取得して、確認の画面に出す商品を返す。
    /// 商品バリアントが 1 つの商品は、その 1 つを個数 1 で選んだ状態から始まる。
    @Test func 商品ページのURLから確認の画面に出す商品を取得する() async throws {
        let shopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(shopDomain)/products/coffee-beans.js"] = .http(statusCode: 200, body: productJSON) }
        let favoriteAddition = try await loadFavoriteAddition(
            text: "  https://\(shopDomain)/products/coffee-beans?variant=70881412\n",
            urlSession: StubURLProtocol.urlSession()
        )
        #expect(
            favoriteAddition.productPage
                == ShopifyProductPage(shopDomain: shopDomain, localePathComponent: nil, percentEncodedProductHandle: "coffee-beans", variantID: "70881412")
        )
        #expect(
            favoriteAddition.product == ShopifyAjaxProduct(
                title: "コーヒー豆 200g",
                featuredImage: "//cdn.shopify.com/beans.png",
                variants: [.init(id: 70_881_412, title: "Default Title", available: true)]
            )
        )
        #expect(favoriteAddition.quantitiesByVariantID == [70_881_412: 1])
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(shopDomain) } } == ["https://\(shopDomain)/products/coffee-beans.js"])
    }

    /// 商品バリアントが複数ある商品の商品ページの URL (`?variant=` なし) からは、商品バリアントが店の並び順のまま全部返り、どれも選んでいない状態から始まる。
    @Test func 商品バリアントが複数ある商品は全部の商品バリアントを未選択で返す() async throws {
        let shopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock {
            $0["https://\(shopDomain)/products/coffee-beans.js"] = .http(
                statusCode: 200,
                body: Data(
                    #"{"title":"コーヒー豆","featured_image":null,"variants":[{"id":101,"title":"200g / 豆のまま","available":true},{"id":102,"title":"500g / 中挽き","available":false}]}"#
                        .utf8
                )
            )
        }
        let favoriteAddition = try await loadFavoriteAddition(text: "https://\(shopDomain)/products/coffee-beans", urlSession: StubURLProtocol.urlSession())
        #expect(
            favoriteAddition.product.variants == [
                .init(id: 101, title: "200g / 豆のまま", available: true),
                .init(id: 102, title: "500g / 中挽き", available: false),
            ]
        )
        #expect(favoriteAddition.quantitiesByVariantID == [:])
    }

    /// 商品ページの URL の形でない入力 (Amazon の商品ページ・`http`・カートの URL) は、通信せずに「URL の形でない」で終わる。
    @Test(arguments: ["/dp/B00EXAMPLE", "/cart/70881412:1", "/"])
    func 商品ページのURLでない入力は通信せずに断る(path: String) async {
        let shopDomain = uniqueShopDomain()
        await #expect(throws: FavoriteAdditionLoadError.notProductPageURL) {
            try await loadFavoriteAddition(text: "https://\(shopDomain)\(path)", urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(shopDomain) } } == [])
    }

    /// `http` の商品ページの URL は、通信せずに「URL の形でない」で終わる。
    @Test func httpのURLは通信せずに断る() async {
        let shopDomain = uniqueShopDomain()
        await #expect(throws: FavoriteAdditionLoadError.notProductPageURL) {
            try await loadFavoriteAddition(text: "http://\(shopDomain)/products/coffee-beans", urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(shopDomain) } } == [])
    }

    /// 商品が無い (404)・Shopify でない店が HTML を返す (200 だが JSON でない)・指定の商品バリアントが無い時は「登録できない」で終わる。
    @Test(arguments: [
        (404, "Not Found", "/products/coffee-beans"),
        (200, "<!doctype html><html><body>パスワードを入力してください</body></html>", "/products/coffee-beans"),
        (200, #"{"title":"コーヒー豆 200g","featured_image":null,"variants":[{"id":70881412,"title":"Default Title","available":true}]}"#, "/products/coffee-beans?variant=999"),
        (500, "", "/products/coffee-beans"),
    ])
    func 商品の情報を取得できない時は登録できないで終わる(statusCode: Int, body: String, pathAndQuery: String) async {
        let shopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(shopDomain)/products/coffee-beans.js"] = .http(statusCode: statusCode, body: Data(body.utf8)) }
        await #expect(throws: FavoriteAdditionLoadError.notRegistrable) {
            try await loadFavoriteAddition(text: "https://\(shopDomain)\(pathAndQuery)", urlSession: StubURLProtocol.urlSession())
        }
    }

    /// 店が応答を制限している (429。本文が商品の JSON でも) 時と、通信に失敗した時は「一時的に取得できない」で終わる。
    @Test func 応答の制限と通信の失敗は一時的に取得できないで終わる() async {
        let rateLimitedShopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(rateLimitedShopDomain)/products/coffee-beans.js"] = .http(statusCode: 429, body: productJSON) }
        await #expect(throws: FavoriteAdditionLoadError.temporarilyUnavailable) {
            try await loadFavoriteAddition(text: "https://\(rateLimitedShopDomain)/products/coffee-beans", urlSession: StubURLProtocol.urlSession())
        }
        let unreachableShopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(unreachableShopDomain)/products/coffee-beans.js"] = .connectionFailure }
        await #expect(throws: FavoriteAdditionLoadError.temporarilyUnavailable) {
            try await loadFavoriteAddition(text: "https://\(unreachableShopDomain)/products/coffee-beans", urlSession: StubURLProtocol.urlSession())
        }
    }

    // MARK: - 確認の画面の操作

    /// 確認の画面で 2 つの商品バリアント (「200g / 豆のまま」を 3 個・「500g / 中挽き」を 1 個) を選んだ時の、保存するお気に入り。
    private var confirmedFavorites: [Favorite] {
        [
            Favorite(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
                name: "いつもの豆",
                variantName: "200g / 豆のまま",
                imageURL: nil,
                quantity: 3,
                product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                reminder: nil
            ),
            Favorite(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!,
                name: "いつもの豆",
                variantName: "500g / 中挽き",
                imageURL: nil,
                quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881413")),
                reminder: nil
            ),
        ]
    }

    /// 「お気に入りに追加」を押すと、保存済みの並びの末尾に、選んだ商品バリアントごとのお気に入りが、選んだ個数と商品バリアントの名前のまま足される。
    @Test func お気に入りに追加を押すと選んだ商品バリアントごとに末尾に保存される() throws {
        let fileURL = temporaryFavoritesFileURL()
        let existingFavorite = Favorite(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
            name: "せっけん",
            imageURL: nil,
            quantity: 1,
            product: .shopify(ShopifyProduct(shopDomain: "sukoyaka-soap.example", variantID: "70881382")),
            reminder: nil
        )
        try saveFavorites(favorites: [existingFavorite], fileURL: fileURL)
        try finishFavoriteAddition(choice: .add, favorites: confirmedFavorites, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [existingFavorite] + confirmedFavorites)
    }

    /// 「やめる」を押すと、商品バリアントを選んだ後でも、保存先のファイルは作られず、お気に入りは 0 件のまま。
    @Test func やめるを押すと保存されない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try finishFavoriteAddition(choice: .cancel, favorites: confirmedFavorites, fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }

    /// 1 つも選んでいないお気に入りの追加は、保存先のファイルを作らない。
    @Test func 選んだものが無い追加は保存先に書かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try finishFavoriteAddition(choice: .add, favorites: [], fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
    }

    /// 選んだうちの 1 件でも個数が 1 未満なら、ほかの 1 件も保存されず、保存済みの並びが残る。
    @Test func 個数が1未満のものが混ざる追加は1件も保存しない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try addFavorites(favorites: [confirmedFavorites[0]], fileURL: fileURL)
        var zeroQuantityFavorite = confirmedFavorites[1]
        zeroQuantityFavorite.quantity = 0
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try finishFavoriteAddition(
                choice: .add,
                favorites: [
                    Favorite(
                        id: UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!,
                        name: "いつもの豆",
                        variantName: "1kg / 豆のまま",
                        imageURL: nil,
                        quantity: 1,
                        product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881414")),
                        reminder: nil
                    ),
                    zeroQuantityFavorite,
                ],
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL) == [confirmedFavorites[0]])
    }

    /// 同じ追加をもう一度呼んでも、同じ識別子のお気に入りは増えない。
    @Test func 同じ追加を繰り返しても増えない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try finishFavoriteAddition(choice: .add, favorites: confirmedFavorites, fileURL: fileURL)
        try finishFavoriteAddition(choice: .add, favorites: confirmedFavorites, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == confirmedFavorites)
    }

    /// 選んだうちの 1 件が保存済みの時は、保存済みの 1 件 (名前と個数を後から変えたもの) を変えず、まだ無い 1 件だけを末尾に足す。
    @Test func 一部が保存済みの追加は無いものだけを足す() throws {
        let fileURL = temporaryFavoritesFileURL()
        try addFavorites(favorites: [confirmedFavorites[1]], fileURL: fileURL)
        try updateFavorite(id: confirmedFavorites[1].id, name: "名前を変えた豆", quantity: 5, fileURL: fileURL)
        try finishFavoriteAddition(choice: .add, favorites: confirmedFavorites, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.id) == [confirmedFavorites[1].id, confirmedFavorites[0].id])
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["名前を変えた豆", "いつもの豆"])
        #expect(try loadFavorites(fileURL: fileURL).map(\.quantity) == [5, 3])
    }

    /// 渡した並びの中に同じ識別子のお気に入りが 2 つある時 (店の商品の情報に同じ商品バリアントが 2 回並んでいた時) は、最初の 1 件だけを保存する。
    @Test func 同じ識別子が並びに複数ある追加は最初の1件だけを足す() throws {
        let fileURL = temporaryFavoritesFileURL()
        var laterDuplicate = confirmedFavorites[0]
        laterDuplicate.quantity = 9
        try finishFavoriteAddition(choice: .add, favorites: [confirmedFavorites[0], confirmedFavorites[1], laterDuplicate], fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == confirmedFavorites)
    }

    /// 個数が 1 未満のものが、保存済みと同じ識別子のもの・並びの中で 2 回目に出てくるものであっても、追加はエラーになり、新しい 1 件も保存されない。
    @Test func 個数が1未満のものは重複として除かれる時でも追加を止める() throws {
        let fileURL = temporaryFavoritesFileURL()
        try addFavorites(favorites: [confirmedFavorites[0]], fileURL: fileURL)
        var zeroQuantitySavedFavorite = confirmedFavorites[0]
        zeroQuantitySavedFavorite.quantity = 0
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try finishFavoriteAddition(choice: .add, favorites: [zeroQuantitySavedFavorite, confirmedFavorites[1]], fileURL: fileURL)
        }
        var zeroQuantityLaterDuplicate = confirmedFavorites[1]
        zeroQuantityLaterDuplicate.quantity = 0
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try finishFavoriteAddition(choice: .add, favorites: [confirmedFavorites[1], zeroQuantityLaterDuplicate], fileURL: fileURL)
        }
        #expect(try loadFavorites(fileURL: fileURL) == [confirmedFavorites[0]])
    }

    /// 店の商品の情報に同じ ID の商品バリアントが 2 回並んでいる時は、ID ごとに最初の 1 つだけを店の並び順のまま返す。
    @Test func 同じIDの商品バリアントが並ぶ商品は最初の1つだけを返す() async throws {
        let shopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock {
            $0["https://\(shopDomain)/products/coffee-beans.js"] = .http(
                statusCode: 200,
                body: Data(
                    #"{"title":"コーヒー豆","featured_image":null,"variants":[{"id":101,"title":"小","available":true},{"id":102,"title":"中","available":true},{"id":101,"title":"大","available":true}]}"#
                        .utf8
                )
            )
        }
        #expect(
            try await loadFavoriteAddition(text: "https://\(shopDomain)/products/coffee-beans", urlSession: StubURLProtocol.urlSession()).product.variants == [
                .init(id: 101, title: "小", available: true),
                .init(id: 102, title: "中", available: true),
            ]
        )
    }

    // MARK: - 名前と個数の入力

    /// 保存するボタンは、名前に字があり、商品バリアントを 1 つ以上選んでいる時だけ押せる。どちらかが欠けると押せない。
    @Test(arguments: [
        ("豆", 1, true),
        ("豆", 3, true),
        ("豆", 0, false),
        ("", 1, false),
        (" ", 2, false),
        ("", 0, false),
    ])
    func 名前があり1つ以上選んでいる時だけ保存できる(name: String, selectedVariantCount: Int, expectedSavable: Bool) {
        #expect(isFavoriteAdditionSavable(name: name, selectedVariantCount: selectedVariantCount) == expectedSavable)
    }

    /// 1 文字でも字があれば保存でき、空文字・空白だけ・改行だけの名前は保存できない。
    @Test(arguments: [
        ("豆", true),
        (" 豆 ", true),
        ("", false),
        (" ", false),
        ("　", false),
        ("\n", false),
    ])
    func 名前が空か空白だけの間は保存できない(name: String, expectedSavable: Bool) {
        #expect(isFavoriteNameSavable(name: name) == expectedSavable)
    }

    /// 個数は 1 つずつ減り、1 からは減らない。
    @Test(arguments: [(3, 2), (2, 1), (1, 1)])
    func 個数は1より小さくならない(quantity: Int, expectedQuantity: Int) {
        #expect(decrementedQuantity(quantity: quantity) == expectedQuantity)
    }

    // MARK: - 共有メニューから渡された項目

    /// 文字列の項目が先、URL の項目が後に渡されても、URL を返す。
    @Test func 共有された項目はURLを文字列より優先する() async {
        #expect(
            await sharedText(itemProviders: [
                NSItemProvider(object: "コーヒー豆 200g" as NSString),
                NSItemProvider(object: URL(string: "https://mori-coffee.example/products/coffee-beans")! as NSURL),
            ]) == "https://mori-coffee.example/products/coffee-beans"
        )
    }

    /// URL の項目が無ければ、最初の文字列の項目を返す (URL として読めない文字列)。
    @Test func URLの項目が無ければ文字列を返す() async {
        #expect(
            await sharedText(itemProviders: [
                NSItemProvider(object: "コーヒー豆 200g" as NSString),
                NSItemProvider(object: "2 つ目の文字列" as NSString),
            ]) == "コーヒー豆 200g"
        )
    }

    /// URL の形の文字列だけが渡された時は、その文字列を返す。
    @Test func URLの形の文字列はそのまま返す() async {
        #expect(
            await sharedText(itemProviders: [NSItemProvider(object: "https://mori-coffee.example/products/coffee-beans" as NSString)])
                == "https://mori-coffee.example/products/coffee-beans"
        )
    }

    /// 項目が 1 つも無い時と、URL でも文字列でもない項目 (画像) だけの時は nil を返す。
    @Test func URLも文字列も無ければnilを返す() async {
        #expect(await sharedText(itemProviders: []) == nil)
        #expect(await sharedText(itemProviders: [NSItemProvider(item: Data([0x89, 0x50]) as NSData, typeIdentifier: "public.png")]) == nil)
    }

    // MARK: - 商品の画像の読み込み

    /// 転送先が、同じホスト・Shopify の CDN (`https`) なら進み、無関係なホスト・`http`・ポート付き・認証情報付き・元の URL や転送先が無い時は進まない。
    @Test(arguments: [
        ("https://mori-coffee.example/cdn/a.png", "https://mori-coffee.example/cdn/b.png", true),
        ("https://mori-coffee.example/cdn/a.png", "https://cdn.shopify.com/s/files/a.png", true),
        ("https://cdn.shopify.com/s/files/a.png", "https://cdn.shopify.com/s/files/b.png", true),
        ("https://Mori-Coffee.Example/cdn/a.png", "https://mori-coffee.example/cdn/b.png", true),
        ("https://mori-coffee.example/cdn/a.png", "https://tracker.example/pixel", false),
        ("https://cdn.shopify.com/s/files/a.png", "https://mori-coffee.example/cdn/a.png", false),
        ("https://mori-coffee.example/cdn/a.png", "http://mori-coffee.example/cdn/b.png", false),
        ("https://mori-coffee.example/cdn/a.png", "https://mori-coffee.example:8443/cdn/b.png", false),
        ("https://mori-coffee.example/cdn/a.png", "https://mori-coffee.example@tracker.example/pixel", false),
        ("https://mori-coffee.example/cdn/a.png", nil, false),
        (nil, "https://cdn.shopify.com/s/files/a.png", false),
    ] as [(String?, String?, Bool)])
    func 画像の転送先は同じホストかShopifyのCDNだけに進む(originalURLText: String?, redirectedURLText: String?, expectedAllowed: Bool) {
        #expect(
            isAllowedProductImageRedirect(originalURL: originalURLText.flatMap(URL.init(string:)), redirectedURL: redirectedURLText.flatMap(URL.init(string:)))
                == expectedAllowed
        )
    }

    /// 画像を読み込む通信の delegate は、無関係なホストへの転送には従わず (nil)、Shopify の CDN への転送には転送先のリクエストをそのまま返す。
    @Test func 画像の通信は無関係なホストへの転送に従わない() async throws {
        let originalURL = try #require(URL(string: "https://mori-coffee.example/cdn/a.png"))
        let task = URLSession.shared.dataTask(with: originalURL)
        let redirectResponse = try #require(HTTPURLResponse(url: originalURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil))
        let cdnRequest = URLRequest(url: try #require(URL(string: "https://cdn.shopify.com/s/files/a.png")))
        #expect(
            try await ProductImageRedirectGuard().urlSession(
                .shared,
                task: task,
                willPerformHTTPRedirection: redirectResponse,
                newRequest: URLRequest(url: #require(URL(string: "https://tracker.example/pixel")))
            ) == nil
        )
        #expect(
            await ProductImageRedirectGuard().urlSession(.shared, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: cdnRequest) == cdnRequest
        )
    }

    /// 画像の読み込みは、HTTP 200 で画像として読めるデータの時だけ画像を返し、200 以外 (従わなかった転送の応答 302 を含む)・画像でないデータ・通信の失敗では nil を返す。
    @Test func 画像は200で画像として読める時だけ返す() async throws {
        let shopDomain = uniqueShopDomain()
        // 1x1 ピクセルの PNG。
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
        StubURLProtocol.stubResponses.withLock {
            $0["https://\(shopDomain)/ok.png"] = .http(statusCode: 200, body: pngData)
            $0["https://\(shopDomain)/redirect.png"] = .http(statusCode: 302, body: pngData)
            $0["https://\(shopDomain)/not-image.png"] = .http(statusCode: 200, body: Data("<html></html>".utf8))
            $0["https://\(shopDomain)/offline.png"] = .connectionFailure
        }
        #expect(try await loadProductImage(url: #require(URL(string: "https://\(shopDomain)/ok.png")), urlSession: StubURLProtocol.urlSession()) != nil)
        for path in ["redirect.png", "not-image.png", "offline.png"] {
            #expect(try await loadProductImage(url: #require(URL(string: "https://\(shopDomain)/\(path)")), urlSession: StubURLProtocol.urlSession()) == nil)
        }
    }

    /// 実際の通信で、無関係なホストへの転送を受けた時は転送先へリクエストを出さず画像も返さない。同じホストへの転送には従って画像を返す。
    /// 時間の上限は、転送に従わなかった通信が終わらない場合に、テストを止めずに失敗させるために付けている。
    @Test(.timeLimit(.minutes(1))) func 通信の途中の転送は同じホストにだけ従う() async throws {
        let shopDomain = uniqueShopDomain()
        let trackerURLText = "https://tracker-\(UUID().uuidString.lowercased()).example/pixel.png"
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
        StubURLProtocol.stubResponses.withLock {
            $0["https://\(shopDomain)/to-tracker.png"] = .redirect(locationURLText: trackerURLText)
            $0[trackerURLText] = .http(statusCode: 200, body: pngData)
            $0["https://\(shopDomain)/to-same-host.png"] = .redirect(locationURLText: "https://\(shopDomain)/moved.png")
            $0["https://\(shopDomain)/moved.png"] = .http(statusCode: 200, body: pngData)
        }
        let urlSessionConfiguration = URLSessionConfiguration.ephemeral
        urlSessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: ProductImageRedirectGuard(), delegateQueue: nil)
        #expect(try await loadProductImage(url: #require(URL(string: "https://\(shopDomain)/to-same-host.png")), urlSession: urlSession) != nil)
        #expect(try await loadProductImage(url: #require(URL(string: "https://\(shopDomain)/to-tracker.png")), urlSession: urlSession) == nil)
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.contains("https://\(shopDomain)/moved.png") })
        #expect(StubURLProtocol.requestedURLTexts.withLock { !$0.contains(trackerURLText) })
    }

    /// 登録できなかった理由ごとに、別の文言を出す (理由を取り違えて出さない)。
    @Test func 登録できなかった理由ごとに文言が違う() {
        #expect(favoriteAdditionLoadErrorMessage(error: .notProductPageURL).hasPrefix("この URL は登録できません"))
        #expect(favoriteAdditionLoadErrorMessage(error: .temporarilyUnavailable).hasPrefix("商品の情報を取得できませんでした"))
        #expect(favoriteAdditionLoadErrorMessage(error: .notRegistrable).hasPrefix("この商品は登録できません"))
    }
}
