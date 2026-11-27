import Foundation

/// 保存済みのお気に入りから、確認の後に開く URL を組み立てて返す。
///
/// 渡してよいのは、登録の画面で利用者が店のドメインを確かめて保存したお気に入りだけ (documents/adr/0003)。
/// Shopify の店の商品は、その店のカートに商品を個数分足して購入画面 (店の `/cart`) を開く URL を `shopifyCartAddURL(shopDomain:variantID:quantity:)` で組み立て、同関数が組み立てない値 (ホスト名の形でない店のドメイン等) では nil を返す。
func openingURL(favorite: Favorite) -> URL? {
    switch favorite.product {
    case let .shopify(shopifyProduct):
        shopifyCartAddURL(shopDomain: shopifyProduct.shopDomain, variantID: shopifyProduct.variantID, quantity: favorite.quantity)
    }
}

/// 指定した識別子の保存済みのお気に入りを開く時に呼び、開く URL を返す。一覧の確認の「開く」と、通知 (リマインドの通知・ウィジェットの「カートイン」の確認の通知) のタップが使う。
///
/// リマインドを設定しているお気に入りでは、日数を数え始めた日時を `now` に書き換えて保存する (開いた時刻から数え直す)。
/// その識別子のお気に入りが保存されていない時と、開く URL を組み立てられない時は、何も書かずに nil を返す (呼び出し側は何も開かない)。
func openingURL(favoriteID: UUID, now: Date, fileURL: URL) throws -> URL? {
    guard let favoriteOpeningURL = try loadFavorites(fileURL: fileURL).first(where: { $0.id == favoriteID }).flatMap(openingURL(favorite:)) else {
        return nil
    }
    try recountFavoriteReminder(id: favoriteID, now: now, fileURL: fileURL)
    return favoriteOpeningURL
}

/// 一覧とウィジェットの行の、確認を出すボタンの文言「カートイン」を `locale` の言語で返す。
func cartInButtonTitle(locale: Locale) -> String {
    String(localized: LocalizedStringResource("カートイン", locale: locale))
}

/// 一覧の確認と、ウィジェットの確認の通知の見出し「購入画面を開きますか？」を `locale` の言語で返す。
func cartInConfirmationTitle(locale: Locale) -> String {
    String(localized: LocalizedStringResource("購入画面を開きますか？", locale: locale))
}
