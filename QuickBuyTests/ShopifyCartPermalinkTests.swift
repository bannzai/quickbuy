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

    /// スキーム・パス・ポート・認証情報・クエリを含む文字列、ラベルが 1 つ・空・ハイフン始まりや終わりの文字列、
    /// ASCII の英数字とハイフン以外の文字 (日本語・全角数字・アクセント付きの文字・空白・改行・下線) を含む文字列は nil になる。
    @Test(arguments: [
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
        "example .com",
        "example\n.com",
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
