import Foundation
import Testing
@testable import QuickBuy

/// Amazon の商品ページの URL と短い URL から ASIN を取り出す関数、商品ページの URL を組み立てる関数、Amazon のお気に入りを作る関数を確かめる。
struct AmazonProductPageTests {
    /// テストごとに別の、短い URL の英数字の部分を返す (テストどうしが同じ URL の応答を取り合わないため)。
    private func uniqueShortURLCode() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    // MARK: - 商品ページの URL から ASIN を取り出す

    /// 3 つの形 (`/dp/`・`/gp/product/`・`/gp/aw/d/`) と、商品名の部分・`ref=` の部分・引数・末尾の `/` が付いた形から ASIN を取り出す。小文字の ASIN は大文字にする。
    @Test(arguments: [
        ("https://www.amazon.co.jp/dp/4065356113", "4065356113"),
        ("https://www.amazon.co.jp/dp/B0DTESTAB1/", "B0DTESTAB1"),
        ("https://www.amazon.co.jp/dp/4065356113?ref_=cm_sw_r_cp_ud_dp_EXAMPLEEXAMPLEEXAMPL_1&skipTwisterOG=2", "4065356113"),
        ("https://www.amazon.co.jp/Python-CasADi/dp/4065356113/ref=sr_1_1?keywords=casadi", "4065356113"),
        ("https://www.amazon.co.jp/%E3%82%B3%E3%83%BC%E3%83%92%E3%83%BC/dp/B0DTESTAB1", "B0DTESTAB1"),
        ("https://www.amazon.co.jp/gp/product/4065356113", "4065356113"),
        ("https://www.amazon.co.jp/gp/product/4065356113/ref=ppx_yo_dt_b_asin_title", "4065356113"),
        ("https://www.amazon.co.jp/gp/aw/d/4065356113", "4065356113"),
        ("https://www.amazon.co.jp/dp/b0dtestab1", "B0DTESTAB1"),
        ("HTTPS://WWW.AMAZON.CO.JP/dp/4065356113", "4065356113"),
        ("https://www.amazon.co.jp/dp/406535611X", "406535611X"),
    ])
    func 商品ページのURLからASINを取り出す(text: String, expectedASIN: String) {
        #expect(amazonASIN(text: text) == expectedASIN)
    }

    /// 商品ページの URL と似ているが受け取らない形では nil を返す。
    @Test(arguments: [
        // ホストが www.amazon.co.jp でない (ほかの国・www の無い形・短い URL・似たドメイン)
        "https://www.amazon.com/dp/4065356113",
        "https://amazon.co.jp/dp/4065356113",
        "https://amzn.asia/d/8TwVTO3",
        "https://www.amazon.co.jp.evil.example/dp/4065356113",
        // https でない・認証情報・ポート
        "http://www.amazon.co.jp/dp/4065356113",
        "https://user@www.amazon.co.jp/dp/4065356113",
        "https://www.amazon.co.jp:8443/dp/4065356113",
        // ASIN の形でない (9 文字・11 文字・記号)
        "https://www.amazon.co.jp/dp/406535611",
        "https://www.amazon.co.jp/dp/40653561130",
        "https://www.amazon.co.jp/dp/40653561-3",
        // 受け取らないパスの形 (商品名の部分が 2 つ・ref= で始まらない後ろの部分・後ろの部分が 2 つ・ASIN が無い・カート・検索・gp の途中まで)
        "https://www.amazon.co.jp/a/b/dp/4065356113",
        "https://www.amazon.co.jp/dp/4065356113/cart",
        "https://www.amazon.co.jp/dp/4065356113/ref=a/ref=b",
        "https://www.amazon.co.jp/dp/",
        "https://www.amazon.co.jp/gp/cart/view.html",
        "https://www.amazon.co.jp/s?k=coffee",
        "https://www.amazon.co.jp/gp/product/",
        "https://www.amazon.co.jp/gp/aw/d/",
        "https://www.amazon.co.jp//dp/4065356113",
        // 印字できる ASCII 以外を含む
        "https://www.amazon.co.jp/dp/4065356113 ",
        "https://www.amazon.co.jp/コーヒー/dp/4065356113",
        "",
    ])
    func 受け取らない形ではASINを返さない(text: String) {
        #expect(amazonASIN(text: text) == nil)
    }

    // MARK: - 短い URL

    /// `https://amzn.asia/d/{英数字}` の形は URL を返す (ホストの大文字は小文字にそろえる)。
    @Test(arguments: [
        ("https://amzn.asia/d/8TwVTO3", "https://amzn.asia/d/8TwVTO3"),
        ("https://AMZN.ASIA/d/8TwVTO3", "https://amzn.asia/d/8TwVTO3"),
    ])
    func 短いURLの形はURLを返す(text: String, expectedURLText: String) {
        #expect(amazonShortURL(text: text)?.absoluteString == expectedURLText)
    }

    /// 短い URL と似ているが受け取らない形では nil を返す。
    @Test(arguments: [
        "https://amzn.to/3abcDEF",
        "https://a.co/d/8TwVTO3",
        "http://amzn.asia/d/8TwVTO3",
        "https://amzn.asia/d/8TwVTO3?tag=x",
        "https://amzn.asia/d/",
        "https://amzn.asia/d/8Tw-VTO3",
        "https://amzn.asia/d/8TwVTO3/x",
        "https://amzn.asia/x/8TwVTO3",
        "https://user@amzn.asia/d/8TwVTO3",
        "https://amzn.asia:8443/d/8TwVTO3",
    ])
    func 受け取らない短いURLの形ではnilを返す(text: String) {
        #expect(amazonShortURL(text: text) == nil)
    }

    // MARK: - 商品ページの URL を組み立てる

    /// ASIN から `https://www.amazon.co.jp/dp/{ASIN}` を組み立て、アソシエイトの ID (`tag`) を含む引数を付けない。
    @Test func ASINから商品ページのURLを組み立てる() throws {
        let url = try #require(amazonProductPageURL(asin: "B0DTESTAB1"))
        #expect(url.absoluteString == "https://www.amazon.co.jp/dp/B0DTESTAB1")
        #expect(url.query == nil)
    }

    /// ASIN の形でない値 (空・9 文字・11 文字・小文字・パスや引数を含む) では組み立てない。
    @Test(arguments: ["", "B0DTESTAB", "B0DTESTAB12", "b0dtestab1", "B0DTE/../X", "B0DTEST?a="])
    func ASINの形でない値では組み立てない(asin: String) {
        #expect(amazonProductPageURL(asin: asin) == nil)
    }

    // MARK: - 渡された文字列から ASIN を読む

    /// 商品ページの URL は通信せずに ASIN を返す。前に文章が付いた共有の文字列 (改行区切り) からも読む。
    @Test(arguments: [
        "  https://www.amazon.co.jp/dp/4065356113\n",
        "PythonとCasADiで学ぶモデル予測制御\nhttps://www.amazon.co.jp/dp/4065356113?ref_=cm_sw_r_cp_ud_dp",
    ])
    func 商品ページのURLは通信せずにASINを返す(text: String) async throws {
        let requestedCountBefore = StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains("amazon") }.count }
        #expect(try await loadAmazonASIN(text: text, urlSession: StubURLProtocol.urlSession()) == "4065356113")
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains("amazon") }.count } == requestedCountBefore)
    }

    /// 短い URL は、短い URL だけに GET し、転送先の商品ページを取得せずに転送先の URL から ASIN を返す。
    @Test func 短いURLは転送先からASINを返し転送先を取得しない() async throws {
        let shortURLText = "https://amzn.asia/d/\(uniqueShortURLCode())"
        let redirectedURLText = "https://www.amazon.co.jp/dp/B0DTESTAB2?ref_=cm_sw_r_cp_ud_dp_\(uniqueShortURLCode())"
        StubURLProtocol.stubResponses.withLock { $0[shortURLText] = .redirect(locationURLText: redirectedURLText) }

        #expect(try await loadAmazonASIN(text: "おすすめ \(shortURLText)", urlSession: StubURLProtocol.urlSession()) == "B0DTESTAB2")
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0 == shortURLText }.count } == 1)
        #expect(StubURLProtocol.requestedURLTexts.withLock { !$0.contains(redirectedURLText) })
    }

    /// 短い URL の転送先が www.amazon.co.jp の商品ページでない時は「受け取らない Amazon の URL」で終わり、転送先を取得しない。
    @Test(arguments: ["https://www.amazon.com/dp/B0DTESTAB2", "https://evil.example/dp/B0DTESTAB2", "https://www.amazon.co.jp/s?k=coffee"])
    func 短いURLの転送先が商品ページでなければ断る(redirectedURLText: String) async {
        let shortURLText = "https://amzn.asia/d/\(uniqueShortURLCode())"
        StubURLProtocol.stubResponses.withLock { $0[shortURLText] = .redirect(locationURLText: redirectedURLText) }

        await #expect(throws: FavoriteAdditionLoadError.notAmazonProductPageURL) {
            try await loadAmazonASIN(text: shortURLText, urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { !$0.contains(redirectedURLText) })
    }

    /// 短い URL への通信に失敗した時と、転送しない応答 (200) が返った時は「一時的に取得できない」で終わる。
    @Test(arguments: [StubURLProtocol.StubResponse.connectionFailure, .http(statusCode: 200, body: Data("<html></html>".utf8))])
    func 短いURLで転送されなければ一時的に取得できない(stubResponse: StubURLProtocol.StubResponse) async {
        let shortURLText = "https://amzn.asia/d/\(uniqueShortURLCode())"
        StubURLProtocol.stubResponses.withLock { $0[shortURLText] = stubResponse }

        await #expect(throws: FavoriteAdditionLoadError.temporarilyUnavailable) {
            try await loadAmazonASIN(text: shortURLText, urlSession: StubURLProtocol.urlSession())
        }
    }

    /// 受け取らない形の Amazon の URL (ほかの国・カート・ほかの短い URL) は、通信せずに「受け取らない Amazon の URL」で終わる。
    @Test(arguments: [
        "https://www.amazon.com/dp/4065356113",
        "https://www.amazon.co.jp/gp/cart/view.html",
        "https://smile.amazon.co.jp/dp/4065356113",
        "https://amzn.to/3abcDEF",
        "https://a.co/d/8TwVTO3",
    ])
    func 受け取らないAmazonのURLは通信せずに断る(text: String) async {
        let requestedCountBefore = StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(text) }.count }
        await #expect(throws: FavoriteAdditionLoadError.notAmazonProductPageURL) {
            try await loadAmazonASIN(text: text, urlSession: StubURLProtocol.urlSession())
        }
        #expect(StubURLProtocol.requestedURLTexts.withLock { $0.filter { $0.contains(text) }.count } == requestedCountBefore)
    }

    /// Amazon の URL を含まない文字列 (Shopify の店の URL・ホストに amazon を含むが区切りの一部でないドメイン・ホストに amazon の部分や a.co を持つ Shopify の店の商品ページの URL・URL でない文字列) では nil を返し、Shopify の店の URL として扱わせる。
    @Test(arguments: [
        "https://mori-coffee.example/products/coffee-beans",
        "https://notamazon.example/dp/4065356113",
        "https://amazonfan.example/products/x",
        "https://amazon.example/products/coffee-beans",
        "https://shop.amazon.example/products/coffee-beans?variant=1",
        "https://a.co/products/coffee-beans",
        "コーヒー豆",
        "",
    ])
    func AmazonのURLを含まなければnilを返す(text: String) async throws {
        #expect(try await loadAmazonASIN(text: text, urlSession: StubURLProtocol.urlSession()) == nil)
    }

    // MARK: - お気に入りにする

    /// ASIN・名前・識別子だけを持ち、商品バリアントの名前・画像の URL・リマインドを持たず、個数は 1 のお気に入りを作る。
    @Test func Amazonのお気に入りはASINと名前だけを持つ() {
        let favoriteID = UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        #expect(
            amazonFavorite(asin: "B0DTESTAB1", name: "単3電池", id: favoriteID)
                == Favorite(id: favoriteID, name: "単3電池", variantName: nil, imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B0DTESTAB1")), reminder: nil)
        )
    }
}
