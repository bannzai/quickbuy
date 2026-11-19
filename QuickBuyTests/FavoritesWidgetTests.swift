import Foundation
import Testing
import UserNotifications
import WidgetKit
@testable import QuickBuy

/// ウィジェットに並べるお気に入りの選び方・行に出す説明・表示を切り替える時刻を確かめる。
struct FavoritesWidgetTests {
    /// テストでリマインドの日数を数え始めた日時として使う、決まった日時 (2026-11-01 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_793_491_200)
    /// 1 日の秒数 (24 時間)。期待値を対象のコードの定数から作らないよう、テストの側に書いている。
    private let daySeconds: TimeInterval = 86400

    /// 名前・商品バリアントの名前・個数・リマインドを指定した Shopify の商品のお気に入りを返す。
    private func favorite(name: String, variantName: String? = nil, quantity: Int = 1, reminder: Reminder? = nil) -> Favorite {
        Favorite(
            id: UUID(),
            name: name,
            variantName: variantName,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: reminder
        )
    }

    /// 「洗剤」「電池」「水」「米」の順の 4 件のうち、先頭から `count` 件を返す。
    private func favorites(count: Int) -> [Favorite] {
        ["洗剤", "電池", "水", "米"].prefix(count).map { favorite(name: $0) }
    }

    // MARK: - 並べる行の数

    /// 小サイズは先頭の 1 行、中サイズは先頭から 2 行、大サイズは先頭から 3 行までを、保存した並びのまま並べる。
    /// 保存が上限より少ない時はある分だけ、0 件の時は何も並べない。
    @Test(arguments: [
        (WidgetFamily.systemSmall, 0, [String]()),
        (WidgetFamily.systemSmall, 1, ["洗剤"]),
        (WidgetFamily.systemSmall, 4, ["洗剤"]),
        (WidgetFamily.systemMedium, 0, [String]()),
        (WidgetFamily.systemMedium, 1, ["洗剤"]),
        (WidgetFamily.systemMedium, 2, ["洗剤", "電池"]),
        (WidgetFamily.systemMedium, 3, ["洗剤", "電池"]),
        (WidgetFamily.systemLarge, 0, [String]()),
        (WidgetFamily.systemLarge, 2, ["洗剤", "電池"]),
        (WidgetFamily.systemLarge, 3, ["洗剤", "電池", "水"]),
        (WidgetFamily.systemLarge, 4, ["洗剤", "電池", "水"]),
    ])
    func ウィジェットの大きさごとに先頭から並べる(widgetFamily: WidgetFamily, savedCount: Int, expectedNames: [String]) {
        #expect(widgetFavorites(favorites: favorites(count: savedCount), widgetFamily: widgetFamily).map(\.name) == expectedNames)
    }

    /// ウィジェットが対応していない特大サイズには、お気に入りを並べない。
    @Test func 対応していない大きさには並べない() {
        #expect(widgetFavorites(favorites: favorites(count: 4), widgetFamily: .systemExtraLarge) == [])
    }

    // MARK: - 行の説明

    /// 商品バリアントの名前を持つお気に入りの行は「種類 ・ N 個」(画面の見本 WidgetPush.dc.html の行)。
    @Test func 種類の名前を持つ行は種類と個数() {
        #expect(favoriteWidgetRowCaption(favorite: favorite(name: "コーヒー豆", variantName: "200g / 豆のまま", quantity: 2)) == "200g / 豆のまま ・ 2 個")
    }

    /// 商品バリアントの名前を持たないお気に入りの行は「N 個」だけで、前に区切りを付けない。
    @Test func 種類の名前の無い行は個数だけ() {
        #expect(favoriteWidgetRowCaption(favorite: favorite(name: "洗濯用せっけん", quantity: 1)) == "1 個")
    }

    // MARK: - 「カートイン」を出すか

    /// 通知が許可 (authorized) の時だけ「カートイン」を出せる。仮の許可・一時的な許可・拒否・未決定では出せない。
    @Test(arguments: [
        (UNAuthorizationStatus.authorized, true),
        (UNAuthorizationStatus.provisional, false),
        (UNAuthorizationStatus.ephemeral, false),
        (UNAuthorizationStatus.denied, false),
        (UNAuthorizationStatus.notDetermined, false),
    ])
    func 許可の時だけカートインを出せる(authorizationStatus: UNAuthorizationStatus, expected: Bool) {
        #expect(isCartInAvailable(authorizationStatus: authorizationStatus) == expected)
    }

    /// Shopify の商品は通知が許可されている時だけボタンを出し、Amazon の商品は許可されていても出さない。
    @Test func カートインのボタンは許可されたShopifyの商品だけに出す() {
        #expect(isCartInButtonShown(favorite: favorite(name: "洗剤"), isNotificationAuthorized: true))
        #expect(!isCartInButtonShown(favorite: favorite(name: "洗剤"), isNotificationAuthorized: false))
        #expect(
            !isCartInButtonShown(
                favorite: Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil),
                isNotificationAuthorized: true
            )
        )
    }

    // MARK: - 表示を切り替える時刻

    /// 先頭は今の時刻で、続けてまだ日数が過ぎていないリマインドの、日数が過ぎる時刻を早い順に並べる。
    /// 既に過ぎたリマインドと、リマインドの無いお気に入りの時刻は入れない。同じ時刻は 1 つにまとめる。
    @Test func 今とリマインドの日数が過ぎる時刻を早い順に返す() {
        let now = countedFrom.addingTimeInterval(10 * daySeconds)
        #expect(
            favoritesWidgetTimelineDates(
                favorites: [
                    favorite(name: "30日ごと", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)),
                    favorite(name: "7日ごと (過ぎた)", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom)),
                    favorite(name: "14日ごと", reminder: Reminder(intervalDays: 14, countedFrom: countedFrom)),
                    favorite(name: "知らせなし"),
                    favorite(name: "30日ごと (同じ時刻)", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)),
                ],
                now: now
            ) == [
                now,
                countedFrom.addingTimeInterval(14 * daySeconds),
                countedFrom.addingTimeInterval(30 * daySeconds),
            ]
        )
    }

    /// ちょうど今リマインドの日数が過ぎる時刻は、今の時刻と重ねて入れない (今の表示内容で既に「そろそろ買う頃」を出すため)。
    @Test func ちょうど今過ぎる時刻は重ねて入れない() {
        let now = countedFrom.addingTimeInterval(30 * daySeconds)
        #expect(
            favoritesWidgetTimelineDates(favorites: [favorite(name: "30日ごと", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))], now: now) == [now]
        )
    }

    /// お気に入りが無い時は今の時刻だけを返す。
    @Test func お気に入りが無い時は今だけ() {
        #expect(favoritesWidgetTimelineDates(favorites: [], now: countedFrom) == [countedFrom])
    }
}
