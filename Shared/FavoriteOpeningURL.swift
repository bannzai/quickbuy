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
/// 開く時は、最後にカートインした日時を `now` にし、リマインドを設定しているお気に入りでは日数を数え始めた日時も `now` に書き換えて保存する (`recordFavoriteCartIn(id:now:fileURL:)`)。
/// その識別子のお気に入りが保存されていない時と、開く URL を組み立てられない時は、何も書かずに nil を返す (呼び出し側は何も開かない)。
func openingURL(favoriteID: UUID, now: Date, fileURL: URL) throws -> URL? {
    guard let favoriteOpeningURL = try loadFavorites(fileURL: fileURL).first(where: { $0.id == favoriteID }).flatMap(openingURL(favorite:)) else {
        return nil
    }
    try recordFavoriteCartIn(id: favoriteID, now: now, fileURL: fileURL)
    return favoriteOpeningURL
}

/// 一覧の行と編集の画面に出す、最後にカートインした日の文言 (例: 「前回のカートイン 11月20日」) を `locale` の言語で返す。
///
/// 日付は、`locale` の言語と `region` の地域の書き方で月と日を出し、`lastCartInAt` が `now` と違う年の時は年も出す。年と日付の区切りは `calendar` (とその time zone) で数える。
/// 買ったかはアプリから分からないため、文言に購入に当たる語を使わない (documents/adr/0003)。
func lastCartInText(lastCartInAt: Date, now: Date, calendar: Calendar, locale: Locale, region: Locale.Region?) -> String {
    // 地域を渡さない時は、言語に付いた地域 (pt-BR の BR 等) の書き方にする。
    let dateFormatStyle = Date.FormatStyle(
        locale: Locale(languageCode: locale.language.languageCode, script: locale.language.script, languageRegion: region ?? locale.language.region),
        calendar: calendar,
        timeZone: calendar.timeZone
    ).month().day()
    return String(localized: LocalizedStringResource(
        "前回のカートイン \(lastCartInAt.formatted(calendar.isDate(lastCartInAt, equalTo: now, toGranularity: .year) ? dateFormatStyle : dateFormatStyle.year()))",
        locale: locale
    ))
}

/// 一覧とウィジェットの行の、確認を出すボタンの文言「カートイン」を `locale` の言語で返す。
func cartInButtonTitle(locale: Locale) -> String {
    String(localized: LocalizedStringResource("カートイン", locale: locale))
}

/// 一覧の確認と、ウィジェットの確認の通知の見出し「購入画面を開きますか？」を `locale` の言語で返す。
func cartInConfirmationTitle(locale: Locale) -> String {
    String(localized: LocalizedStringResource("購入画面を開きますか？", locale: locale))
}
