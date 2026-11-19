import Foundation

/// Amazon の URL のホストとして見分けるホストのうち、ドメインの部分に `amazon` を含まない短い URL のホスト。
///
/// `amzn.asia` は `amazonShortURLHost`。`amzn.to` と `a.co` は Amazon のほかの国の短い URL のホスト (https://github.com/bannzai/quickbuy/issues/35 で、Amazon の共有の操作が作るリンクとして検索で見つかった値)。
/// 受け取らない Amazon の URL に、Shopify の店の URL の案内ではなく Amazon の共有から渡す案内を出すためだけに使う。
private let amazonLookingShortURLHosts: Set<String> = [amazonShortURLHost, "amzn.to", "a.co"]

/// 文字列を空白と改行で区切った部分のうち、最初の Amazon の商品ページの URL (`amazonASIN(text:)` が通すもの) か短い URL (`amazonShortURL(text:)` が通すもの) を返す。どちらも無ければ nil を返す。
///
/// Amazon のアプリの共有は、URL の前に商品の名前などの文章を付けた文字列を渡すことがあるため、文字列の全体ではなく区切った部分ごとに見る。
func amazonURLText(text: String) -> String? {
    text.split(whereSeparator: \.isWhitespace).map(String.init).first { amazonASIN(text: $0) != nil || amazonShortURL(text: $0) != nil }
}

/// 文字列を空白と改行で区切った部分のどれかが、Amazon のホストの URL なら true を返す。
///
/// Amazon のホストは、ドメインを `.` で区切った部分のどれかが `amazon` のホスト (`www.amazon.co.jp`・`amazon.com`・`smile.amazon.com` 等) と、`amazonLookingShortURLHosts`。
/// 受け取る形かどうかは見ない (受け取る形は `amazonURLText(text:)` が見分ける)。
func containsAmazonLookingURL(text: String) -> Bool {
    text.split(whereSeparator: \.isWhitespace).contains { part in
        guard let host = URLComponents(string: String(part))?.host?.lowercased() else {
            return false
        }
        return host.split(separator: ".").contains("amazon") || amazonLookingShortURLHosts.contains(host)
    }
}

/// 短い URL への GET で、最初の転送先を記録して、転送には従わない delegate。
///
/// class にしているのは、`URLSessionTaskDelegate` が `NSObject` を継承した型を求めるため。
final class AmazonShortURLRedirectRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// 最初の転送先の URL。転送を受けていなければ nil。`lock` を取ってから読み書きする。
    private var redirectedURL: URL?
    /// `redirectedURL` の読み書きを 1 つずつにする鍵。
    private let lock = NSLock()

    /// 最初の転送先の URL を返す。転送を受けていなければ nil。
    func firstRedirectedURL() -> URL? {
        lock.withLock { redirectedURL }
    }

    /// 転送先を記録し、転送には従わない (nil を返す)。
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        lock.withLock {
            if redirectedURL == nil {
                redirectedURL = request.url
            }
        }
        return nil
    }
}

/// 渡された文字列 (前後の空白と改行は除く) が Amazon の商品ページの URL か短い URL を含めば、その商品の ASIN を返す。Amazon の URL を含まなければ nil を返す (Shopify の店の URL として扱う)。保存はしない。
///
/// 商品ページの URL は通信せずに `amazonASIN(text:)` で読む。短い URL は、短い URL への GET を 1 回だけ行い、転送には従わずに転送先を `amazonASIN(text:)` で読む
/// (Amazon の商品ページそのものは取得しない。Amazon が持つ名前・画像・価格を読まないため)。
/// 失敗した時は `FavoriteAdditionLoadError` を投げる。受け取らない形の Amazon の URL (`containsAmazonLookingURL(text:)` が true) は `notAmazonProductPageURL`、
/// 短い URL の転送先が www.amazon.co.jp の商品ページでない時は `notAmazonProductPageURL`、転送を受けられなかった時 (通信の失敗・転送しない応答) は `temporarilyUnavailable`。
func loadAmazonASIN(text: String, urlSession: URLSession) async throws -> String? {
    guard let urlText = amazonURLText(text: text) else {
        if containsAmazonLookingURL(text: text) {
            throw FavoriteAdditionLoadError.notAmazonProductPageURL
        }
        return nil
    }
    if let asin = amazonASIN(text: urlText) {
        return asin
    }
    guard let shortURL = amazonShortURL(text: urlText) else {
        return nil
    }
    let redirectRecorder = AmazonShortURLRedirectRecorder()
    // 転送に従わない時の終わり方 (転送の応答を返すか、通信の失敗か) は通信の仕組みによって違い得るため、結果は見ずに記録した転送先だけで決める。
    _ = try? await urlSession.data(from: shortURL, delegate: redirectRecorder)
    guard let redirectedURL = redirectRecorder.firstRedirectedURL() else {
        throw FavoriteAdditionLoadError.temporarilyUnavailable
    }
    guard let asin = amazonASIN(text: redirectedURL.absoluteString) else {
        throw FavoriteAdditionLoadError.notAmazonProductPageURL
    }
    return asin
}

/// 確認の画面で利用者が名前を付けた Amazon の商品を、保存するお気に入りにして返す。保存はしない。
///
/// 持つのは ASIN・利用者が付けた名前・識別子だけで、画像の URL と商品バリアントの名前は持たない (Amazon が返す名前・画像を保存しない。documents/research/2026-11-18/search-api-and-amazon-purchase-url.md)。
/// 個数は 1 にする。商品ページの URL で個数を渡す方法を確かめられず (`amazonProductPageURL(asin:)` は個数を URL に入れない)、個数は利用者が Amazon の画面で選ぶため、
/// 1 は `Favorite.quantity` の下限 (1 以上) を満たすためだけの値で、一覧・ウィジェット・通知に出さない。
func amazonFavorite(asin: String, name: String, id: UUID) -> Favorite {
    Favorite(id: id, name: name, variantName: nil, imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: asin)), reminder: nil)
}
