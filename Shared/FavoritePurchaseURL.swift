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

/// 指定した識別子の保存済みのお気に入りの購入画面を開く時に呼び、開く URL を返す。一覧の確認の「開く」と、通知 (リマインドの通知・ウィジェットの「カートイン」の確認の通知) のタップが使う。
///
/// リマインドを設定しているお気に入りでは、日数を数え始めた日時を `now` に書き換えて保存する (購入画面を開いた時刻から数え直す)。
/// その識別子のお気に入りが保存されていない時と、購入画面の URL を組み立てられない時は、何も書かずに nil を返す (呼び出し側は購入画面を開かない)。
func purchaseURLForOpening(favoriteID: UUID, now: Date, fileURL: URL) throws -> URL? {
    guard let openingURL = try loadFavorites(fileURL: fileURL).first(where: { $0.id == favoriteID }).flatMap(purchaseURL(favorite:)) else {
        return nil
    }
    try recountFavoriteReminder(id: favoriteID, now: now, fileURL: fileURL)
    return openingURL
}
