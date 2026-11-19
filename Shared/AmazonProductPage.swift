import Foundation

/// Quick Buy が受け取る Amazon の店のホスト。ほかの国の Amazon は受け取らない (https://github.com/bannzai/quickbuy/issues/35 で agent が決めた範囲)。
let amazonHost = "www.amazon.co.jp"

/// Amazon の商品ページの短い URL のホスト。
///
/// 2026-11-19 に `https://amzn.asia/d/8TwVTO3` へ GET した時、HTTP 301 で `Location: https://www.amazon.co.jp/dp/4065356113?ref_=cm_sw_r_cp_ud_dp_…` が返った
/// (`cm_sw_r_cp` は Amazon の共有の操作で作られたリンクを指す引数の値)。
let amazonShortURLHost = "amzn.asia"

/// 1 文字以上の文字列が ASIN の形 (ASCII の英大文字と数字だけの 10 文字) なら true を返す。
///
/// ASIN の形の出典: https://affiliate.amazon.co.jp/creatorsapi/docs/en-us/api-reference/operations/get-items の `itemIds` の説明 (ASIN は 10 文字の英数字)。
/// 書籍の ASIN は ISBN-10 と同じ値 (数字と末尾の `X`) で、この形に含まれる。小文字を含む文字列は false (呼び出し側が大文字にしてから渡す)。
func isASIN(text: String) -> Bool {
    text.utf8.count == 10 && text.utf8.allSatisfy { (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains($0) || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }
}

/// 文字列が www.amazon.co.jp の商品ページの URL の形なら、その商品の ASIN (英大文字) を返す。形が違えば nil を返す。
///
/// 通す形は次の 3 つで、どれも後ろに `/{ref= で始まる部分}` と `?{引数}` が付いてもよい。引数と `ref=` の部分は読まずに落とす (アソシエイトの ID `tag` も落ちる)。ASIN の小文字は大文字にする。
/// - `https://www.amazon.co.jp[/{商品名の部分}]/dp/{ASIN}`
/// - `https://www.amazon.co.jp/gp/product/{ASIN}`
/// - `https://www.amazon.co.jp/gp/aw/d/{ASIN}`
///
/// 形式の出典: `/dp/{ASIN}` は、Amazon の短い URL の転送先 (2026-11-19 に `https://amzn.asia/d/8TwVTO3` の `Location` が `https://www.amazon.co.jp/dp/4065356113?ref_=…`) と、
/// Creators API の応答の見本の `detailPageURL` (`https://www.amazon.com/dp/0545162076?tag=…`。documents/research/2026-11-18/search-api-and-amazon-purchase-url.md)。
/// 公式の文書が無い 3 つの形は、2026-11-19 に GitHub Actions の Linux Runner の Chromium (webtunnel) で開いて確かめた:
/// `/Python-CasADi/dp/4065356113/ref=sr_1_1?keywords=casadi`・`/gp/product/4065356113`・`/gp/aw/d/4065356113` は、どれも URL を変えずに同じ商品の商品ページを表示した。
///
/// nil を返す入力: 印字できる ASCII 以外の文字を含む文字列、`https` 以外のスキーム、認証情報・ポートを含む URL、ホストが `amazonHost` でない URL (ほかの国の Amazon・`amazon.co.jp`・短い URL を含む)、
/// 上の形でないパス (商品名の部分が 2 つ以上・`ref=` で始まらない後ろの部分・カートの URL・検索の URL を含む)、ASIN の形でない値。
func amazonASIN(text: String) -> String? {
    guard text.utf8.allSatisfy({ (0x21 ... 0x7E).contains($0) }),
          let urlComponents = URLComponents(string: text, encodingInvalidCharacters: false),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil,
          urlComponents.host?.lowercased() == amazonHost
    else {
        return nil
    }
    let pathComponents = Array(urlComponents.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst())
    guard let asinIndex = amazonProductPathASINIndex(pathComponents: pathComponents) else {
        return nil
    }
    let asin = pathComponents[asinIndex].uppercased()
    let trailingComponents = pathComponents[(asinIndex + 1)...]
    // 後ろに続けてよいのは、`ref=` で始まる部分 1 つか、末尾の `/` (空の部分) 1 つだけ。
    guard isASIN(text: asin),
          trailingComponents.count <= 1,
          trailingComponents.allSatisfy({ $0.isEmpty || $0.hasPrefix("ref=") })
    else {
        return nil
    }
    return asin
}

/// 商品ページの URL のパスを `/` で区切った部分の並び (先頭の `/` の前の空の部分は除く) から、ASIN が入る位置を返す。`amazonASIN(text:)` が通す 3 つの形のどれでもなければ nil を返す。
private func amazonProductPathASINIndex(pathComponents: [Substring]) -> Int? {
    if pathComponents.starts(with: ["gp", "product"]) {
        return pathComponents.count >= 3 ? 2 : nil
    }
    if pathComponents.starts(with: ["gp", "aw", "d"]) {
        return pathComponents.count >= 4 ? 3 : nil
    }
    // `dp` の前の商品名の部分は、あっても空でない 1 つだけ。
    if pathComponents.count >= 2, pathComponents[0] == "dp" {
        return 1
    }
    if pathComponents.count >= 3, !pathComponents[0].isEmpty, pathComponents[1] == "dp" {
        return 2
    }
    return nil
}

/// 文字列が Amazon の商品ページの短い URL (`https://amzn.asia/d/{英数字}`) の形なら URL を返す。形が違えば nil を返す。
///
/// 形式の出典: 2026-11-19 に `https://amzn.asia/d/8TwVTO3` が www.amazon.co.jp の商品ページへ転送されたこと (`amazonShortURLHost`)。
/// nil を返す入力: 印字できる ASCII 以外の文字を含む文字列、`https` 以外のスキーム、認証情報・ポート・引数を含む URL、ホストが `amazonShortURLHost` でない URL (`amzn.to` を含む)、`/d/` の後が英数字でない・空の URL。
func amazonShortURL(text: String) -> URL? {
    guard text.utf8.allSatisfy({ (0x21 ... 0x7E).contains($0) }),
          let urlComponents = URLComponents(string: text, encodingInvalidCharacters: false),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil,
          urlComponents.query == nil,
          urlComponents.host?.lowercased() == amazonShortURLHost
    else {
        return nil
    }
    let pathComponents = urlComponents.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
    guard pathComponents.count == 2,
          pathComponents.first == "d",
          let code = pathComponents.last,
          !code.isEmpty,
          code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
    else {
        return nil
    }
    return URL(string: "https://\(amazonShortURLHost)/d/\(code)")
}

/// 保存済みの ASIN から、Amazon の商品ページの URL `https://www.amazon.co.jp/dp/{ASIN}` を組み立てて返す。ASIN の形 (`isASIN(text:)`) でない値では nil を返す。
///
/// 形式の出典は `amazonASIN(text:)` と同じ。開いた時に商品はカートに入っていない (documents/DIRECTION.md「必要な機能」)。
/// アソシエイトの ID (`tag`) を含む引数は付けない (Amazon がアプリを承認するまで付けない。documents/DIRECTION.md「決めたこと」)。
func amazonProductPageURL(asin: String) -> URL? {
    isASIN(text: asin) ? URL(string: "https://\(amazonHost)/dp/\(asin)") : nil
}
