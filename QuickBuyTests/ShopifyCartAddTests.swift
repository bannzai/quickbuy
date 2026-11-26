import Foundation
import Testing
@testable import QuickBuy

/// `shopifyCartAddURL(shopDomain:variantID:quantity:)` が、決まった形の URL だけを組み立てることを確かめる。
/// 期待する URL の形は `https://{店のドメイン}/cart/add?id={商品バリアントの ID}&quantity={個数}` (形の出典と、実在の店で開いて確かめた結果は関数の document コメント)。
struct ShopifyCartAddTests {
    /// 店のドメイン・商品バリアントの ID・個数が、`/cart/add` の `id` と `quantity` に入る。
    @Test func カートに足すURLを組み立てる() {
        #expect(
            shopifyCartAddURL(shopDomain: "example.myshopify.com", variantID: "70881412", quantity: 3)?.absoluteString
                == "https://example.myshopify.com/cart/add?id=70881412&quantity=3"
        )
    }

    /// 大文字を含む店のドメインは、小文字のホスト名になる。
    @Test func 店のドメインは小文字にそろえる() {
        #expect(
            shopifyCartAddURL(shopDomain: "Example.MyShopify.com", variantID: "1", quantity: 2)?.absoluteString
                == "https://example.myshopify.com/cart/add?id=1&quantity=2"
        )
    }

    /// 数字だけのラベルは、最後のラベルでなければ通る (IP アドレスの形と似ているが通る側)。
    @Test func 最後以外のラベルは数字だけでも通る() {
        #expect(
            shopifyCartAddURL(shopDomain: "123.example.com", variantID: "1", quantity: 1)?.absoluteString
                == "https://123.example.com/cart/add?id=1&quantity=1"
        )
    }

    /// ラベルが 63 文字、全体が 253 文字 (63 + 63 + 63 + 61 文字のラベルとドット 3 つ) のドメインは通る (長さの上限ちょうど)。
    @Test func 長さの上限ちょうどの店のドメインは通る() {
        #expect(
            shopifyCartAddURL(
                shopDomain: [63, 63, 63, 61].map { String(repeating: "a", count: $0) }.joined(separator: "."),
                variantID: "1",
                quantity: 1
            )?.host()?.count == 253
        )
    }

    /// 数字だけの商品バリアントの ID は、1 桁でも、先頭が 0 でも、UInt64 の最大値 (18446744073709551615) を超える桁数でも、
    /// 文字列のまま URL に入る (ID が店に実在するかは見ない)。
    @Test(arguments: [
        ("0", "https://example.myshopify.com/cart/add?id=0&quantity=1"),
        ("007", "https://example.myshopify.com/cart/add?id=007&quantity=1"),
        ("18446744073709551616", "https://example.myshopify.com/cart/add?id=18446744073709551616&quantity=1"),
        ("1234567890123456789012345", "https://example.myshopify.com/cart/add?id=1234567890123456789012345&quantity=1"),
    ])
    func 数字だけの商品バリアントのIDはそのまま入る(variantID: String, expectedURL: String) {
        #expect(shopifyCartAddURL(shopDomain: "example.myshopify.com", variantID: variantID, quantity: 1)?.absoluteString == expectedURL)
    }

    /// 数字以外を含む商品バリアントの ID は nil になる。
    /// 空文字、URL のクエリを書き換えうる文字 (`&` `=` `?` `#` `%`)、URL の区切りになる文字 (`:` `,` `/`)、英字、符号、小数点、空白・改行、全角の数字、
    /// ASCII でない数字 (アラビア・インド数字) を含む。
    /// 似ているが通る側は、同じ形の呼び出しで ID が数字だけのもの (上の「数字だけの商品バリアントのIDはそのまま入る」)。
    @Test(arguments: [
        "",
        "1&quantity=99",
        "1=2",
        "1:2",
        "1,2",
        "1/2",
        "1?x",
        "1#2",
        "%31",
        "1a",
        "abc",
        "-1",
        "+1",
        "1.0",
        " 1",
        "1 ",
        "1\n",
        "１２３",
        "١٢٣",
        "gid://shopify/ProductVariant/1",
    ])
    func 数字以外を含む商品バリアントのIDは通さない(variantID: String) {
        #expect(shopifyCartAddURL(shopDomain: "example.myshopify.com", variantID: variantID, quantity: 1) == nil)
    }

    /// スキーム・パス・ポート・認証情報・クエリを含む文字列、ラベルが 1 つ・空・ハイフン始まりや終わりの文字列、
    /// ASCII の英数字とハイフン以外の文字 (日本語・全角数字・アクセント付きの文字・下線) を含む文字列、
    /// IP アドレスの形 (最後のラベルに英字が無い)、64 文字のラベル、全体が 254 文字の文字列は nil になる。
    @Test(arguments: [
        "127.0.0.1",
        "192.168.0.1",
        "example.123",
        String(repeating: "a", count: 64) + ".com",
        [63, 63, 63, 62].map { String(repeating: "a", count: $0) }.joined(separator: "."),
        "https://example.myshopify.com",
        "example.myshopify.com/cart",
        "example.myshopify.com:8080",
        "user@example.myshopify.com",
        "example.myshopify.com?x=1",
        "-example.myshopify.com",
        "example-.myshopify.com",
        "example..com",
        "example.myshopify.com.",
        "localhost",
        "",
        "例え.jp",
        "１２３.com",
        "é.com",
        "exa_mple.com",
    ])
    func ホスト名の形でない店のドメインは通さない(shopDomain: String) {
        #expect(shopifyCartAddURL(shopDomain: shopDomain, variantID: "1", quantity: 1) == nil)
    }

    /// 空白・改行・タブを含む文字列は、ホスト名と判定されない。
    /// この 3 つは `URL(string:)` も弾くため (店のドメインの検査を外した版でも URL が nil になることを CI で確かめた)、
    /// URL の組み立ての結果ではなく `isHostName(text:)` を直接確かめる。似ているが通る側は空白の無い同じドメイン。
    @Test(arguments: [
        ("example.com", true),
        ("example .com", false),
        ("example\n.com", false),
        ("example\t.com", false),
    ])
    func 空白や改行を含む文字列はホスト名と判定しない(text: String, expected: Bool) {
        #expect(isHostName(text: text) == expected)
    }

    /// 個数が 0 以下の時は nil になり、個数 1 は通る (境界)。
    @Test(arguments: [
        (1, "https://example.myshopify.com/cart/add?id=2&quantity=1"),
        (0, nil),
        (-1, nil),
    ] as [(Int, String?)])
    func 個数が1未満なら組み立てない(quantity: Int, expectedURL: String?) {
        #expect(shopifyCartAddURL(shopDomain: "example.myshopify.com", variantID: "2", quantity: quantity)?.absoluteString == expectedURL)
    }
}
