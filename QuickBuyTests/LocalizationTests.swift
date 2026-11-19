import Foundation
import Testing
@testable import QuickBuy

/// 端末の言語が英語の時の、通知・ウィジェット・画面の文言を返す関数の文言を確かめる (issue #54)。
///
/// 期待値は文字列カタログ (`Shared/Localizable.xcstrings`) の英語の訳。日本語の文言は、各関数のテストが `Locale(identifier: "ja")` を渡して確かめる。
struct LocalizationTests {
    /// 英語の locale。
    private let englishLocale = Locale(identifier: "en")
    /// 日数を数え始めた日時として使う、固定の日時 (2026-11-17 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)

    /// 名前・商品バリアントの名前・個数を指定した、Shopify の店 mori-coffee.example の商品のお気に入りを返す。
    private func shopifyFavorite(name: String, variantName: String?, quantity: Int) -> Favorite {
        Favorite(
            id: UUID(),
            name: name,
            variantName: variantName,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: nil
        )
    }

    /// 名前を指定した Amazon の商品のお気に入りを返す。
    private func amazonFavorite(name: String) -> Favorite {
        Favorite(id: UUID(), name: name, imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil)
    }

    // MARK: - 通知

    /// ウィジェットの「カートイン」の確認の通知は、見出しと本文が英語になる。店と商品の名前は訳さない。
    @Test func カートインの確認の通知は英語() throws {
        let shopifyContent = try #require(
            cartInConfirmationNotificationContent(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 2), locale: englishLocale)
        )
        #expect(shopifyContent.title == "Open checkout?")
        #expect(shopifyContent.body == "コーヒー豆 200g ×2\nTap to open checkout on mori-coffee.example")

        let amazonContent = try #require(cartInConfirmationNotificationContent(favorite: amazonFavorite(name: "単3電池"), locale: englishLocale))
        #expect(amazonContent.title == "Open the Amazon product page?")
        #expect(amazonContent.body == "単3電池\nTap to open the product page on www.amazon.co.jp")
    }

    /// リマインドの通知は、見出しと本文が英語になる。
    @Test func リマインドの通知は英語() {
        let shopifyContent = reminderNotificationContent(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 1), locale: englishLocale)
        #expect(shopifyContent.title == "Time to buy again")
        #expect(shopifyContent.body == "コーヒー豆 200g\nTap to open checkout")
        #expect(reminderNotificationContent(favorite: amazonFavorite(name: "単3電池"), locale: englishLocale).body == "単3電池\nTap to open the Amazon product page")
    }

    // MARK: - ウィジェット

    /// ウィジェットの行のボタンは英語になる。
    @Test func ボタンと確認の見出しは英語() {
        #expect(cartInButtonTitle(favorite: shopifyFavorite(name: "豆", variantName: nil, quantity: 1), locale: englishLocale) == "Add to Cart")
        #expect(cartInButtonTitle(favorite: amazonFavorite(name: "電池"), locale: englishLocale) == "Open in Amazon")
        #expect(cartInConfirmationTitle(favorite: shopifyFavorite(name: "豆", variantName: nil, quantity: 1), locale: englishLocale) == "Open checkout?")
        #expect(cartInConfirmationTitle(favorite: amazonFavorite(name: "電池"), locale: englishLocale) == "Open the Amazon product page?")
    }

    /// 通知の許可が要ることの文は、ボタンの英語の名前を入れた英語の文になる。両方の店を並べた時は 2 つの名前を「 / 」で区切る。
    @Test func 通知の許可が要ることの文は英語() {
        #expect(widgetNotificationRequiredText(favorites: [shopifyFavorite(name: "豆", variantName: nil, quantity: 1)], locale: englishLocale) == "Add to Cart needs notification permission")
        #expect(
            widgetNotificationRequiredText(favorites: [shopifyFavorite(name: "豆", variantName: nil, quantity: 1), amazonFavorite(name: "電池")], locale: englishLocale)
                == "Add to Cart / Open in Amazon needs notification permission"
        )
        #expect(widgetNotificationRequiredText(favorites: [], locale: englishLocale) == "Add to Cart needs notification permission")
    }

    /// ウィジェットの行の説明は、個数を「×N」で出し、商品バリアントの名前との区切りを「 · 」にする。
    @Test func 行の説明は英語の個数() {
        #expect(favoriteWidgetRowCaption(favorite: shopifyFavorite(name: "豆", variantName: "200g", quantity: 2), locale: englishLocale) == "200g · ×2")
        #expect(favoriteWidgetRowCaption(favorite: shopifyFavorite(name: "豆", variantName: nil, quantity: 1), locale: englishLocale) == "×1")
        #expect(favoriteWidgetRowCaption(favorite: amazonFavorite(name: "電池"), locale: englishLocale) == "Amazon")
    }

    /// リマインドの状態は英語で、残りの日数が 1 日の時は単数、2 日以上の時は複数の形になる。
    @Test func リマインドの状態は英語で日数の単数と複数を分ける() {
        let reminder = Reminder(intervalDays: 7, countedFrom: countedFrom)
        #expect(reminderStatusText(reminder: nil, now: countedFrom, locale: englishLocale) == "No reminder")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(7 * 86400), locale: englishLocale) == "Time to buy again")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(6 * 86400), locale: englishLocale) == "Next reminder in 1 day")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(5 * 86400), locale: englishLocale) == "Next reminder in 2 days")
    }

    // MARK: - 画面

    /// 一覧の確認の 2 行目と、編集の画面の数え直しの文は英語になる。
    @Test func 確認の文と数え直しの文は英語() {
        #expect(cartInConfirmationText(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 2), locale: englishLocale) == "Opens with コーヒー豆 200g ×2 in the cart")
        #expect(cartInConfirmationText(favorite: amazonFavorite(name: "単3電池"), locale: englishLocale) == "Opens the product page for 単3電池 (not added to cart)")
        #expect(reminderRecountText(favorite: shopifyFavorite(name: "豆", variantName: nil, quantity: 1), locale: englishLocale) == "The count restarts on the day you open checkout")
        #expect(reminderRecountText(favorite: amazonFavorite(name: "電池"), locale: englishLocale) == "The count restarts on the day you open the Amazon product page")
    }

    /// 追加の画面の保存するボタンは、選んだ種類が 1 つの時は単数、2 つ以上の時は複数の形になる。
    @Test(arguments: [
        (true, 1, "Add 1 Variant to Favorites"),
        (true, 2, "Add 2 Variants to Favorites"),
        (true, 0, "Add to Favorites"),
        (false, 1, "Add to Favorites"),
    ])
    func 保存するボタンは英語で種類の数の単数と複数を分ける(hasVariantChoices: Bool, selectedVariantCount: Int, expectedTitle: String) {
        #expect(favoriteAdditionButtonTitle(hasVariantChoices: hasVariantChoices, selectedVariantCount: selectedVariantCount, locale: englishLocale) == expectedTitle)
    }

    /// 登録できない理由の文言は、どの理由でも英語になる。
    @Test(arguments: [
        (FavoriteAdditionLoadError.notProductPageURL, "This URL can't be added\nEnter a product page URL from a Shopify store or Amazon"),
        (.notAmazonProductPageURL, "This Amazon URL can't be added\nOn an Amazon product page in the app or website, tap Share and choose Quick Buy"),
        (.temporarilyUnavailable, "Couldn't get product info\nPlease wait a moment and try again"),
        (.notRegistrable, "This product can't be added\nThe store doesn't share product info or the product wasn't found"),
    ])
    func 登録できない理由は英語(error: FavoriteAdditionLoadError, expectedMessage: String) {
        #expect(favoriteAdditionLoadErrorMessage(error: error, locale: englishLocale) == expectedMessage)
    }

    /// 検索の失敗の文言は、どの理由でも英語になる。待つ秒数は 1 秒の時は単数、2 秒以上の時は複数の形になる。
    @Test(arguments: [
        (ShopifyCatalogError.rateLimited(retryAfterSeconds: 1), "It's busy right now\nPlease wait about 1 second and try again"),
        (.rateLimited(retryAfterSeconds: 120), "It's busy right now\nPlease wait about 120 seconds and try again"),
        (.rateLimited(retryAfterSeconds: nil), "It's busy right now\nPlease wait a moment and try again"),
        (.connectionFailed, "Couldn't connect\nPlease try again where the signal is better"),
        (.failed, "Couldn't load products\nPlease wait a moment and try again"),
    ])
    func 検索の失敗の文言は英語(error: ShopifyCatalogError, expectedMessage: String) {
        #expect(shopifyCatalogErrorMessage(error: error, locale: englishLocale) == expectedMessage)
    }

    /// 通知の要求の文言は、渡した言語になる (アプリは `appTextLocale` を渡す)。
    @Test func 通知の要求は渡した言語の文言() throws {
        let favorite = shopifyFavorite(name: "コーヒー豆", variantName: nil, quantity: 5)
        #expect(try #require(cartInConfirmationNotificationRequest(favorite: favorite, locale: englishLocale)).content.body == "コーヒー豆 ×5\nTap to open checkout on mori-coffee.example")
        #expect(try #require(cartInConfirmationNotificationRequest(favorite: favorite, locale: Locale(identifier: "ja"))).content.body == "コーヒー豆 を 5 個\nタップすると mori-coffee.example の購入画面が開きます")
        var reminderFavorite = favorite
        reminderFavorite.reminder = Reminder(intervalDays: 7, countedFrom: countedFrom)
        #expect(try #require(reminderNotificationRequest(favorite: reminderFavorite, locale: englishLocale)).content.title == "Time to buy again")
        #expect(try #require(reminderNotificationRequest(favorite: reminderFavorite, locale: Locale(identifier: "ja"))).content.title == "そろそろ買う頃です")
    }

    /// ホームの検索語の候補は、英語では英語の語、日本語では今の語になる。先頭の語が最初に検索する語になる。
    @Test func 検索語の候補は言語ごとの語() {
        #expect(homeSuggestedSearchQueries(locale: englishLocale) == ["Coffee beans", "Black tea", "Shampoo", "Laundry detergent", "Protein", "Dog food"])
        #expect(homeSuggestedSearchQueries(locale: Locale(identifier: "ja")) == ["コーヒー豆", "紅茶", "シャンプー", "洗濯洗剤", "プロテイン", "ドッグフード"])
    }

    /// 文言の言語は、bundle が選んだ言語の並びの先頭にする。並びが空の時だけ渡した代わりの locale にする。
    @Test func 文言の言語はbundleが選んだ言語の先頭() {
        #expect(textLocale(preferredLocalizations: ["en", "ja"], fallback: Locale(identifier: "fr")).identifier == "en")
        #expect(textLocale(preferredLocalizations: ["ja"], fallback: Locale(identifier: "fr")).identifier == "ja")
        #expect(textLocale(preferredLocalizations: [], fallback: Locale(identifier: "fr")).identifier == "fr")
    }

    /// 設定画面の、Firebase に送る記録の説明 (PR #51 で足した文言) が英語で引ける。
    @Test func 設定画面の記録の説明は英語() {
        #expect(
            String(localized: LocalizedStringResource("利用の状況とアプリが落ちた時の記録を Google の Firebase に送ります\n商品や店の名前と開いた画面の URL は送りません", locale: englishLocale))
                == "Usage and crash reports are sent to Google Firebase\nProduct names, store names, and URLs of opened pages are not sent"
        )
    }

    /// 画面に直接書いた、数を含む文言のカタログの訳 (編集の画面の「N 日ごと」と次の知らせの日付) が英語で引ける。
    @Test func 画面の数を含む文言は英語() {
        #expect(String(localized: LocalizedStringResource("\(1) 日ごと", locale: englishLocale)) == "1 day")
        #expect(String(localized: LocalizedStringResource("\(7) 日ごと", locale: englishLocale)) == "7 days")
        #expect(String(localized: LocalizedStringResource("\("Restarts")\n次の知らせは \("Nov 26") です", locale: englishLocale)) == "Restarts\nNext reminder: Nov 26")
        #expect(
            String(localized: LocalizedStringResource("\("Restarts")\n次の知らせは \("Nov 26") です\n通知が許可されていません\n設定アプリで Quick Buy の通知を許可すると届きます", locale: englishLocale))
                == "Restarts\nNext reminder: Nov 26\nNotifications aren't allowed\nAllow notifications for Quick Buy in Settings to get reminders"
        )
    }

    /// 追加の画面の URL の説明が英語で引ける。`www.amazon.co.jp` を含むが、画面は `Text(String)` で渡すためリンクにならない (2026-11-19 に simtunnel で英語と日本語の両方を確かめた)。
    @Test func 追加の画面のURLの説明は英語() {
        #expect(
            String(localized: LocalizedStringResource("Shopify の店か Amazon (www.amazon.co.jp) の商品ページの URL を貼り付けてください", locale: englishLocale))
                == "Paste a product page URL from a Shopify store or Amazon (www.amazon.co.jp)"
        )
    }

    /// 問い合わせのメールの件名は英語になる。
    @Test func 問い合わせの件名は英語() throws {
        #expect(
            try #require(contactMailURL(locale: englishLocale).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }).queryItems
                == [URLQueryItem(name: "subject", value: "Quick Buy Inquiry")]
        )
    }
}
