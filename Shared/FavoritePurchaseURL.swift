import Foundation

/// 保存済みのお気に入りから、その商品が個数分カートに入った店の購入画面の URL を組み立てて返す。
///
/// 渡してよいのは、登録の画面で利用者が店のドメインを確かめて保存したお気に入りだけ (documents/adr/0003)。
/// Shopify の店の商品は `shopifyCartPermalinkURL(shopDomain:lines:)` で組み立て、同関数が組み立てない値 (ホスト名の形でない店のドメイン等) では nil を返す。
/// Amazon の商品は、最初の版でどう扱うかが決まっていないため nil を返す (documents/DIRECTION.md「必要な機能」)。
func purchaseURL(favorite: Favorite) -> URL? {
    switch favorite.product {
    case let .shopify(shopifyProduct):
        shopifyCartPermalinkURL(
            shopDomain: shopifyProduct.shopDomain,
            lines: [ShopifyCartLine(variantID: shopifyProduct.variantID, quantity: favorite.quantity)]
        )
    case .amazon:
        nil
    }
}
