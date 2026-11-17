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
        /// 通信の失敗 (圏外など)。
        case connectionFailure
    }

    /// URL の文字列ごとの、返す応答。
    static let stubResponses = OSAllocatedUnfairLock<[String: StubResponse]>(initialState: [:])
    /// 差し替えが受けたリクエストの URL の文字列 (受けた順)。
    static let requestedURLTexts = OSAllocatedUnfairLock<[String]>(initialState: [])

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
        switch Self.stubResponses.withLock({ $0[requestedURLText] }) {
        case let .http(statusCode, body):
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .connectionFailure, nil:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    /// 途中で止めるものが無いため何もしない。
    override func stopLoading() {}
}

/// 商品ページの URL から登録前のお気に入りを作る流れと、確認の画面の「お気に入りに入れる」「やめる」が保存に与える結果を確かめる。
struct AddFavoriteTests {
    /// 登録前のお気に入りの確認に使う識別子。
    private let draftID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

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

    // MARK: - 登録前のお気に入りの取得

    /// 前後に空白と改行が付いた商品ページの URL から、その店の `/products/{商品のハンドル}.js` だけを取得して、登録前のお気に入りを作る。
    @Test func 商品ページのURLから登録前のお気に入りを作る() async throws {
        let shopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(shopDomain)/products/coffee-beans.js"] = .http(statusCode: 200, body: productJSON) }
        #expect(
            try await loadFavoriteDraft(text: "  https://\(shopDomain)/products/coffee-beans?variant=70881412\n", id: draftID, urlSession: StubURLProtocol.urlSession())
                == Favorite(
                    id: draftID,
                    name: "コーヒー豆 200g",
                    imageURL: URL(string: "https://cdn.shopify.com/beans.png"),
                    quantity: 1,
                    product: .shopify(ShopifyProduct(shopDomain: shopDomain, variantID: "70881412")),
                    reminder: nil
                )
        )
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(shopDomain) } } == ["https://\(shopDomain)/products/coffee-beans.js"])
    }

    /// 商品ページの URL の形でない入力 (Amazon の商品ページ・`http`・カートの URL) は、通信せずに「URL の形でない」で終わる。
    @Test(arguments: ["/dp/B00EXAMPLE", "/cart/70881412:1", "/"])
    func 商品ページのURLでない入力は通信せずに断る(path: String) async {
        let shopDomain = uniqueShopDomain()
        await #expect(throws: FavoriteDraftLoadError.notProductPageURL) {
            try await loadFavoriteDraft(text: "https://\(shopDomain)\(path)", id: draftID, urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(shopDomain) } } == [])
    }

    /// `http` の商品ページの URL は、通信せずに「URL の形でない」で終わる。
    @Test func httpのURLは通信せずに断る() async {
        let shopDomain = uniqueShopDomain()
        await #expect(throws: FavoriteDraftLoadError.notProductPageURL) {
            try await loadFavoriteDraft(text: "http://\(shopDomain)/products/coffee-beans", id: draftID, urlSession: StubURLProtocol.urlSession())
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
        await #expect(throws: FavoriteDraftLoadError.notRegistrable) {
            try await loadFavoriteDraft(text: "https://\(shopDomain)\(pathAndQuery)", id: draftID, urlSession: StubURLProtocol.urlSession())
        }
    }

    /// 店が応答を制限している (429。本文が商品の JSON でも) 時と、通信に失敗した時は「一時的に取得できない」で終わる。
    @Test func 応答の制限と通信の失敗は一時的に取得できないで終わる() async {
        let rateLimitedShopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(rateLimitedShopDomain)/products/coffee-beans.js"] = .http(statusCode: 429, body: productJSON) }
        await #expect(throws: FavoriteDraftLoadError.temporarilyUnavailable) {
            try await loadFavoriteDraft(text: "https://\(rateLimitedShopDomain)/products/coffee-beans", id: draftID, urlSession: StubURLProtocol.urlSession())
        }
        let unreachableShopDomain = uniqueShopDomain()
        StubURLProtocol.stubResponses.withLock { $0["https://\(unreachableShopDomain)/products/coffee-beans.js"] = .connectionFailure }
        await #expect(throws: FavoriteDraftLoadError.temporarilyUnavailable) {
            try await loadFavoriteDraft(text: "https://\(unreachableShopDomain)/products/coffee-beans", id: draftID, urlSession: StubURLProtocol.urlSession())
        }
    }

    // MARK: - 確認の画面の操作

    /// 名前と個数を確認の画面で変えた後の、登録前のお気に入り。
    private var confirmedFavorite: Favorite {
        Favorite(
            id: draftID,
            name: "いつもの豆",
            imageURL: nil,
            quantity: 3,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: nil
        )
    }

    /// 「お気に入りに入れる」を押すと、保存済みの並びの末尾に、確認の画面の値のまま足される。
    @Test func お気に入りに入れるを押すと末尾に保存される() throws {
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
        try finishFavoriteAddition(choice: .add, favorite: confirmedFavorite, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [existingFavorite, confirmedFavorite])
    }

    /// 「やめる」を押すと、保存先のファイルは作られず、お気に入りは 0 件のまま。
    @Test func やめるを押すと保存されない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try finishFavoriteAddition(choice: .cancel, favorite: confirmedFavorite, fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }

    // MARK: - 名前と個数の入力

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

    /// 登録できなかった理由ごとに、別の文言を出す (理由を取り違えて出さない)。
    @Test func 登録できなかった理由ごとに文言が違う() {
        #expect(favoriteDraftLoadErrorMessage(error: .notProductPageURL).hasPrefix("この URL は登録できません"))
        #expect(favoriteDraftLoadErrorMessage(error: .temporarilyUnavailable).hasPrefix("商品の情報を取得できませんでした"))
        #expect(favoriteDraftLoadErrorMessage(error: .notRegistrable).hasPrefix("この商品は登録できません"))
    }
}
