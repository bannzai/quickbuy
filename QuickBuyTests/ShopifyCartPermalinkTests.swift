import Foundation
import Testing
@testable import QuickBuy

/// `shopifyCartPermalinkURL(shopDomain:lines:)` が、決まった形の URL だけを組み立てることを確かめる。
/// 期待する URL の形は https://shopify.dev/docs/apps/build/checkout/create-cart-permalinks の `/cart/{variant_id}:{quantity}` (複数はカンマ区切り)。
struct ShopifyCartPermalinkTests {
    /// 商品 1 つの時は `/cart/{商品バリアントの ID}:{個数}` になる。
    @Test func 商品1つのURLを組み立てる() {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "example.myshopify.com",
                lines: [ShopifyCartLine(variantID: 70_881_412, quantity: 1)]
            )?.absoluteString == "https://example.myshopify.com/cart/70881412:1"
        )
    }

    /// 複数の商品は、渡した順にカンマでつながる。
    @Test func 複数の商品をカンマでつなぐ() {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "my-shop.example.jp",
                lines: [
                    ShopifyCartLine(variantID: 70_881_412, quantity: 1),
                    ShopifyCartLine(variantID: 70_881_382, quantity: 3),
                ]
            )?.absoluteString == "https://my-shop.example.jp/cart/70881412:1,70881382:3"
        )
    }

    /// 大文字を含む店のドメインは、小文字のホスト名になる。
    @Test func 店のドメインは小文字にそろえる() {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "Example.MyShopify.com",
                lines: [ShopifyCartLine(variantID: 1, quantity: 2)]
            )?.absoluteString == "https://example.myshopify.com/cart/1:2"
        )
    }

    /// 数字だけのラベルは、最後のラベルでなければ通る (IP アドレスの形と似ているが通る側)。
    @Test func 最後以外のラベルは数字だけでも通る() {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "123.example.com",
                lines: [ShopifyCartLine(variantID: 1, quantity: 1)]
            )?.absoluteString == "https://123.example.com/cart/1:1"
        )
    }

    /// ラベルが 63 文字、全体が 253 文字 (63 + 63 + 63 + 61 文字のラベルとドット 3 つ) のドメインは通る (長さの上限ちょうど)。
    @Test func 長さの上限ちょうどの店のドメインは通る() {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: [63, 63, 63, 61].map { String(repeating: "a", count: $0) }.joined(separator: "."),
                lines: [ShopifyCartLine(variantID: 1, quantity: 1)]
            )?.host()?.count == 253
        )
    }

    /// 商品バリアントの ID は、0 も UInt64 の最大値も、桁を落とさずそのまま URL に入る (ID が店に実在するかは見ない)。
    @Test(arguments: [
        (UInt64.min, "https://example.myshopify.com/cart/0:1"),
        (UInt64.max, "https://example.myshopify.com/cart/18446744073709551615:1"),
    ])
    func 商品バリアントのIDは境界の値でもそのまま入る(variantID: UInt64, expectedURL: String) {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "example.myshopify.com",
                lines: [ShopifyCartLine(variantID: variantID, quantity: 1)]
            )?.absoluteString == expectedURL
        )
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
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: shopDomain,
                lines: [ShopifyCartLine(variantID: 1, quantity: 1)]
            ) == nil
        )
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

    /// 商品が 1 つも無い時は nil になる。
    @Test func 商品が空なら組み立てない() {
        #expect(shopifyCartPermalinkURL(shopDomain: "example.myshopify.com", lines: []) == nil)
    }

    /// 個数が 0 以下の商品が 1 つでもあれば nil になる (個数 1 は通る境界)。
    @Test(arguments: [0, -1])
    func 個数が1未満なら組み立てない(quantity: Int) {
        #expect(
            shopifyCartPermalinkURL(
                shopDomain: "example.myshopify.com",
                lines: [
                    ShopifyCartLine(variantID: 1, quantity: 1),
                    ShopifyCartLine(variantID: 2, quantity: quantity),
                ]
            ) == nil
        )
    }
}
