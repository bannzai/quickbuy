import Foundation
import Testing
@testable import QuickBuy

/// 保存済みのお気に入りから組み立てる開く URL が、決まった形であることを確かめる。
/// Shopify の店の商品は店のドメイン・商品バリアントの ID・個数だけからなる購入画面の URL、Amazon の商品は ASIN だけからなる商品ページの URL。
struct FavoriteOpeningURLTests {
    /// 商品と個数だけを指定したお気に入りを返す。
    private func favorite(quantity: Int, product: Favorite.Product) -> Favorite {
        Favorite(id: UUID(), name: "コーヒー豆", imageURL: nil, quantity: quantity, product: product, reminder: nil)
    }

    /// Shopify の商品は、保存した個数がカートに入る cart permalink になる。
    @Test func Shopifyの商品は個数分がカートに入るURLになる() {
        #expect(
            openingURL(favorite: favorite(quantity: 2, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412"))))?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
    }

    /// 個数を変えると URL の個数も変わる (個数が固定値になっていない)。
    @Test func 個数を変えるとURLの個数も変わる() {
        #expect(
            openingURL(favorite: favorite(quantity: 5, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412"))))?.absoluteString
                == "https://mori-coffee.example/cart/70881412:5"
        )
    }

    /// 店のドメインがホスト名の形でない (パスを含む)・商品バリアントの ID が数字だけでない・個数が 0 のお気に入りでは URL を返さない。
    @Test(arguments: [
        ("mori-coffee.example/evil", "70881412", 1),
        ("mori-coffee.example", "70881412:9", 1),
        ("mori-coffee.example", "70881412", 0),
    ])
    func 組み立てられない値ではURLを返さない(shopDomain: String, variantID: String, quantity: Int) {
        #expect(openingURL(favorite: favorite(quantity: quantity, product: .shopify(ShopifyProduct(shopDomain: shopDomain, variantID: variantID)))) == nil)
    }

    /// Amazon の商品は、www.amazon.co.jp の商品ページの URL になる。個数とアソシエイトの ID は URL に入れない。
    @Test func Amazonの商品は商品ページのURLになる() {
        #expect(
            openingURL(favorite: favorite(quantity: 3, product: .amazon(AmazonProduct(asin: "B00EXAMPLE"))))?.absoluteString
                == "https://www.amazon.co.jp/dp/B00EXAMPLE"
        )
    }

    /// ASIN の形でない保存値 (9 文字・小文字・パスを含む) の Amazon の商品では URL を返さない。
    @Test(arguments: ["B00EXAMPL", "b00example", "B00EXAMPLE/../cart"])
    func ASINの形でない保存値ではURLを返さない(asin: String) {
        #expect(openingURL(favorite: favorite(quantity: 1, product: .amazon(AmazonProduct(asin: asin)))) == nil)
    }

    /// 確認を出すボタンと確認の見出しの文言は、Shopify の店の商品は購入画面、Amazon の商品は商品ページを開くと読める。
    @Test func ボタンと確認の文言は店ごとに変わる() {
        let shopifyFavorite = favorite(quantity: 1, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")))
        let amazonFavorite = favorite(quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")))
        #expect(cartInButtonTitle(favorite: shopifyFavorite) == "カートイン")
        #expect(cartInButtonTitle(favorite: amazonFavorite) == "Amazon で開く")
        #expect(cartInConfirmationTitle(favorite: shopifyFavorite) == "購入画面を開きますか？")
        #expect(cartInConfirmationTitle(favorite: amazonFavorite) == "Amazon の商品ページを開きますか？")
    }
}
