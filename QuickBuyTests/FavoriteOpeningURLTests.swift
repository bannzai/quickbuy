import Foundation
import Testing
@testable import QuickBuy

/// 保存済みのお気に入りから組み立てる開く URL が、決まった形であることを確かめる。
/// Shopify の店の商品は店のドメイン・商品バリアントの ID・個数だけからなる購入画面の URL。
struct FavoriteOpeningURLTests {
    /// 商品と個数だけを指定したお気に入りを返す。
    private func favorite(quantity: Int, product: Favorite.Product) -> Favorite {
        Favorite(id: UUID(), name: "コーヒー豆", imageURL: nil, quantity: quantity, product: product, reminder: nil)
    }

    /// Shopify の商品は、保存した個数を店のカートに足す URL になる。
    @Test func Shopifyの商品は個数分をカートに足すURLになる() {
        #expect(
            openingURL(favorite: favorite(quantity: 2, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412"))))?.absoluteString
                == "https://mori-coffee.example/cart/add?id=70881412&quantity=2"
        )
    }

    /// 個数を変えると URL の個数も変わる (個数が固定値になっていない)。
    @Test func 個数を変えるとURLの個数も変わる() {
        #expect(
            openingURL(favorite: favorite(quantity: 5, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412"))))?.absoluteString
                == "https://mori-coffee.example/cart/add?id=70881412&quantity=5"
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

    /// 確認を出すボタンと確認の見出しの文言は、購入画面を開くと読める。
    @Test func ボタンと確認の文言() {
        #expect(cartInButtonTitle(locale: Locale(identifier: "ja")) == "カートイン")
        #expect(cartInConfirmationTitle(locale: Locale(identifier: "ja")) == "購入画面を開きますか？")
    }
}
