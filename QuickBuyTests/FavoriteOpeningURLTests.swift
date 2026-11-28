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

    // MARK: - 最後にカートインした日の文言

    /// 東京の time zone のグレゴリオ暦。日付の区切りを runner の time zone (UTC) によらず決めるため。
    private var tokyoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 最後にカートインした日時 2026-11-20 03:00:00 UTC (東京の 11 月 20 日)。
    private let lastCartInAt = Date(timeIntervalSince1970: 1_795_143_600)
    /// 文言を出す日時 2026-11-28 00:00:00 UTC (`lastCartInAt` と同じ年)。
    private let now = Date(timeIntervalSince1970: 1_795_824_000)
    /// 前の年に最後にカートインした日時 2025-11-20 03:00:00 UTC (東京の 2025 年 11 月 20 日)。
    private let lastYearCartInAt = Date(timeIntervalSince1970: 1_763_607_600)

    /// 同じ年は月と日だけ、違う年は年も、言語と地域の書き方で出す。前置きは「前回のカートイン」の訳。
    @Test(arguments: [
        ("ja", "JP", "前回のカートイン 11月20日", "前回のカートイン 2025年11月20日"),
        ("en", "US", "Last added to cart Nov 20", "Last added to cart Nov 20, 2025"),
        ("en", "GB", "Last added to cart 20 Nov", "Last added to cart 20 Nov 2025"),
    ])
    func 最後にカートインした日は同じ年なら年を出さない(languageCode: String, regionCode: String, sameYearText: String, otherYearText: String) {
        let locale = Locale(identifier: languageCode)
        #expect(lastCartInText(lastCartInAt: lastCartInAt, now: now, calendar: tokyoCalendar, locale: locale, region: Locale.Region(regionCode)) == sameYearText)
        #expect(lastCartInText(lastCartInAt: lastYearCartInAt, now: now, calendar: tokyoCalendar, locale: locale, region: Locale.Region(regionCode)) == otherYearText)
    }

    /// 日付の区切りは渡した calendar の time zone で数える (UTC では 11 月 19 日の 2026-11-19 20:00:00 UTC は、東京では 11 月 20 日)。
    @Test func 日付は渡したcalendarのtimezoneで数える() {
        #expect(
            lastCartInText(lastCartInAt: Date(timeIntervalSince1970: 1_795_118_400), now: now, calendar: tokyoCalendar, locale: Locale(identifier: "ja"), region: Locale.Region("JP"))
                == "前回のカートイン 11月20日"
        )
    }

    /// 9 つの言語のどれでも、文言は日本語の前置きのまま出ず、同じ年は年の数字を含まず、違う年は年の数字を含む。
    /// 買ったかはアプリから分からないため、購入に当たる語 (各言語の「購入」「買う」の語) を含まない。
    @Test(arguments: ["ja", "en", "es", "fr", "de", "pt-BR", "ko", "zh-Hans", "zh-Hant"])
    func 九つの言語で年の有無と購入に当たる語が無いこと(localeIdentifier: String) {
        let locale = Locale(identifier: localeIdentifier)
        let sameYearText = lastCartInText(lastCartInAt: lastCartInAt, now: now, calendar: tokyoCalendar, locale: locale, region: nil)
        let otherYearText = lastCartInText(lastCartInAt: lastYearCartInAt, now: now, calendar: tokyoCalendar, locale: locale, region: nil)
        #expect(!sameYearText.contains("2026"), "\(sameYearText)")
        #expect(otherYearText.contains("2025"), "\(otherYearText)")
        #expect(localeIdentifier == "ja" || !sameYearText.contains("前回のカートイン"), "\(sameYearText)")
        for purchaseWord in ["購入", "買", "purchase", "buy", "bought", "compra", "achat", "acheté", "kauf", "gekauft", "구매", "구입", "购买", "購買"] {
            #expect(!sameYearText.lowercased().contains(purchaseWord), "\(localeIdentifier): \(sameYearText)")
        }
    }

    /// 確認を出すボタンと確認の見出しの文言は、購入画面を開くと読める。
    @Test func ボタンと確認の文言() {
        #expect(cartInButtonTitle(locale: Locale(identifier: "ja")) == "カートイン")
        #expect(cartInConfirmationTitle(locale: Locale(identifier: "ja")) == "購入画面を開きますか？")
    }
}
