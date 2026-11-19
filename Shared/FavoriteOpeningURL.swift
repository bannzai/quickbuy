import Foundation

/// 保存済みのお気に入りから、確認の後に開く URL を組み立てて返す。
///
/// 渡してよいのは、登録の画面で利用者が店のドメインを確かめて保存したお気に入りだけ (documents/adr/0003)。
/// Shopify の店の商品は、その商品が個数分カートに入った購入画面の URL を `shopifyCartPermalinkURL(shopDomain:lines:)` で組み立て、同関数が組み立てない値 (ホスト名の形でない店のドメイン等) では nil を返す。
/// Amazon の商品は、商品ページの URL を `amazonProductPageURL(asin:)` で組み立て、ASIN の形でない保存値では nil を返す (開いた時に商品はカートに入っていない。documents/DIRECTION.md「必要な機能」)。
func openingURL(favorite: Favorite) -> URL? {
    switch favorite.product {
    case let .shopify(shopifyProduct):
        shopifyCartPermalinkURL(
            shopDomain: shopifyProduct.shopDomain,
            lines: [ShopifyCartLine(variantID: shopifyProduct.variantID, quantity: favorite.quantity)]
        )
    case let .amazon(amazonProduct):
        amazonProductPageURL(asin: amazonProduct.asin)
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

/// 一覧とウィジェットの行の、確認を出すボタンの文言を `locale` の言語で返す。Shopify の店の商品は「カートイン」、Amazon の商品は「Amazon で開く」。
///
/// Amazon の商品ページは開いた時に商品がカートに入っていないため、カートに入れると読める文言を使わない (https://github.com/bannzai/quickbuy/issues/35 で agent が決めた文言)。
func cartInButtonTitle(favorite: Favorite, locale: Locale) -> String {
    switch favorite.product {
    case .shopify:
        String(localized: LocalizedStringResource("カートイン", locale: locale))
    case .amazon:
        String(localized: LocalizedStringResource("Amazon で開く", locale: locale))
    }
}

/// 一覧の確認と、ウィジェットの確認の通知の見出しを `locale` の言語で返す。Shopify の店の商品は「購入画面を開きますか？」、Amazon の商品は「Amazon の商品ページを開きますか？」。
///
/// 用語「購入画面」は Amazon の商品ページを含まない (documents/DIRECTION.md「用語」)。
func cartInConfirmationTitle(favorite: Favorite, locale: Locale) -> String {
    switch favorite.product {
    case .shopify:
        String(localized: LocalizedStringResource("購入画面を開きますか？", locale: locale))
    case .amazon:
        String(localized: LocalizedStringResource("Amazon の商品ページを開きますか？", locale: locale))
    }
}
