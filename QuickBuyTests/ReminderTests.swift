import Foundation
import Testing
import UserNotifications
@testable import QuickBuy

/// リマインドの、次に知らせる日時の計算・通知の予約と取り消しの判断・数え直し・通知が指すお気に入りの扱いを確かめる。
struct ReminderTests {
    /// 日数を数え始めた日時として使う、固定の日時 (2026-11-17 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)
    /// 1 日の秒数。
    private let daySeconds: TimeInterval = 86400

    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// 識別子の末尾の 1 文字とリマインドを指定した、Shopify の商品のお気に入りを返す。
    private func favorite(idSuffix: String, reminder: Reminder?) -> Favorite {
        Favorite(
            id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA\(idSuffix)")!,
            name: "コーヒー豆 \(idSuffix)",
            imageURL: nil,
            quantity: 2,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: reminder
        )
    }

    // MARK: - 次に知らせる日時

    /// 30 日ごとのリマインドで、数え始めてからの経過の日数ごとに、次に知らせる日時が「今より後で最初に来る 30 日ごとの日時」になる。
    /// 30 日ちょうど (通知が届いた瞬間) と 60 日ちょうどでは、その次の回になる。
    @Test(arguments: [
        (0.0, 30.0),
        (29.5, 30.0),
        (30.0, 60.0),
        (30.5, 60.0),
        (59.9, 60.0),
        (60.0, 90.0),
        (-3.0, 30.0),
    ])
    func 次に知らせる日時は今より後で最初に来る回(elapsedDays: Double, expectedDaysFromCountedFrom: Double) {
        #expect(
            nextReminderDate(
                reminder: Reminder(intervalDays: 30, countedFrom: countedFrom),
                now: countedFrom.addingTimeInterval(elapsedDays * daySeconds)
            ) == countedFrom.addingTimeInterval(expectedDaysFromCountedFrom * daySeconds)
        )
    }

    /// 日数を変えると、次に知らせる日時もその日数の分になる。
    @Test func 日数が7日なら7日後に知らせる() {
        #expect(
            nextReminderDate(reminder: Reminder(intervalDays: 7, countedFrom: countedFrom), now: countedFrom)
                == countedFrom.addingTimeInterval(7 * daySeconds)
        )
    }

    /// 30 日ごとのリマインドは、30 日ちょうどから「日数が過ぎた」になり、その後も数え直すまで過ぎたまま。
    @Test(arguments: [
        (0.0, false),
        (29.99, false),
        (30.0, true),
        (45.0, true),
        (75.0, true),
    ])
    func 設定した日数ちょうどから日数が過ぎた扱いになる(elapsedDays: Double, expectedIsDue: Bool) {
        #expect(
            isReminderDue(
                reminder: Reminder(intervalDays: 30, countedFrom: countedFrom),
                now: countedFrom.addingTimeInterval(elapsedDays * daySeconds)
            ) == expectedIsDue
        )
    }

    // MARK: - 一覧の行の文言

    /// 30 日ごとのリマインドの、経過の日数ごとの一覧の文言。残りが 1 日に満たない端数は切り上げる。
    @Test(arguments: [
        (0.0, "次の知らせは 30 日後"),
        (18.0, "次の知らせは 12 日後"),
        (28.5, "次の知らせは 2 日後"),
        (29.0, "次の知らせは 1 日後"),
        (29.9, "次の知らせは 1 日後"),
        (30.0, "そろそろ買う頃"),
        (47.0, "そろそろ買う頃"),
    ])
    func リマインドの状態の文言(elapsedDays: Double, expectedText: String) {
        #expect(
            reminderStatusText(
                reminder: Reminder(intervalDays: 30, countedFrom: countedFrom),
                now: countedFrom.addingTimeInterval(elapsedDays * daySeconds)
            ) == expectedText
        )
    }

    @Test func リマインドが無い時の文言は知らせなし() {
        #expect(reminderStatusText(reminder: nil, now: countedFrom) == "知らせなし")
    }

    // MARK: - 通知の予約と取り消しの判断

    @Test func リマインドを新しく設定すると予約する() {
        let favoriteWithReminder = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(before: [favorite(idSuffix: "1", reminder: nil)], after: [favoriteWithReminder])
                == [.schedule(favorite: favoriteWithReminder)]
        )
    }

    @Test func 日数を変えると予約し直す() {
        let favoriteWithNewInterval = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 14, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))],
                after: [favoriteWithNewInterval]
            ) == [.schedule(favorite: favoriteWithNewInterval)]
        )
    }

    @Test func 数え直すと予約し直す() {
        let recountedFavorite = favorite(
            idSuffix: "1",
            reminder: Reminder(intervalDays: 30, countedFrom: countedFrom.addingTimeInterval(10 * daySeconds))
        )
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))],
                after: [recountedFavorite]
            ) == [.schedule(favorite: recountedFavorite)]
        )
    }

    @Test func リマインドをやめると予約を取り消す() {
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))],
                after: [favorite(idSuffix: "1", reminder: nil)]
            ) == [.cancel(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!)]
        )
    }

    @Test func お気に入りを削除すると予約を取り消す() {
        let remainingFavorite = favorite(idSuffix: "2", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)), remainingFavorite],
                after: [remainingFavorite]
            ) == [.cancel(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!)]
        )
    }

    /// リマインドが同じなら、名前・個数・並びが変わっても予約に触らない。リマインドの無いお気に入りの削除でも取り消さない。
    @Test func リマインドが変わらない保存では予約を変えない() {
        var renamedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        renamedFavorite.name = "別の名前"
        renamedFavorite.quantity = 5
        #expect(
            reminderNotificationChanges(
                before: [
                    favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)),
                    favorite(idSuffix: "2", reminder: nil),
                    favorite(idSuffix: "3", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom)),
                ],
                after: [favorite(idSuffix: "3", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom)), renamedFavorite]
            ) == []
        )
    }

    /// 1 回の保存で複数のお気に入りが変わった時は、取り消しを先に、それぞれの変更を返す。
    @Test func 複数のお気に入りの変更をまとめて返す() {
        let newlySetFavorite = favorite(idSuffix: "2", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)), favorite(idSuffix: "2", reminder: nil)],
                after: [newlySetFavorite]
            ) == [.cancel(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!), .schedule(favorite: newlySetFavorite)]
        )
    }

    // MARK: - リマインドの保存

    @Test func リマインドを設定すると保存の時刻から数え始める() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [favorite(idSuffix: "1", reminder: nil), favorite(idSuffix: "2", reminder: nil)], fileURL: fileURL)
        let savedAt = countedFrom.addingTimeInterval(3 * daySeconds)

        try setFavoriteReminder(
            id: favorite(idSuffix: "1", reminder: nil).id,
            reminder: Reminder(intervalDays: 14, countedFrom: countedFrom),
            now: savedAt,
            fileURL: fileURL
        )

        #expect(
            try loadFavorites(fileURL: fileURL) == [
                favorite(idSuffix: "1", reminder: Reminder(intervalDays: 14, countedFrom: savedAt)),
                favorite(idSuffix: "2", reminder: nil),
            ]
        )
    }

    @Test func 同じリマインドのまま保存しても数え始めた日時は変わらない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)

        try setFavoriteReminder(
            id: savedFavorite.id,
            reminder: savedFavorite.reminder,
            now: countedFrom.addingTimeInterval(10 * daySeconds),
            fileURL: fileURL
        )

        #expect(try loadFavorites(fileURL: fileURL) == [savedFavorite])
    }

    @Test func 日数を変えて保存すると保存の時刻から数え直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        let savedAt = countedFrom.addingTimeInterval(10 * daySeconds)

        try setFavoriteReminder(id: savedFavorite.id, reminder: Reminder(intervalDays: 7, countedFrom: countedFrom), now: savedAt, fileURL: fileURL)

        #expect(try loadFavorites(fileURL: fileURL) == [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 7, countedFrom: savedAt))])
    }

    @Test func リマインドをやめると保存から消える() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)

        try setFavoriteReminder(id: savedFavorite.id, reminder: nil, now: countedFrom, fileURL: fileURL)

        #expect(try loadFavorites(fileURL: fileURL) == [favorite(idSuffix: "1", reminder: nil)])
    }

    /// 編集の画面で選べる範囲の両端 (1 日と 365 日) は保存でき、読み直すと同じ日数になる。
    @Test(arguments: [1, 365])
    func 選べる範囲の両端の日数のリマインドは保存できる(intervalDays: Int) throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [favorite(idSuffix: "1", reminder: nil)], fileURL: fileURL)

        try setFavoriteReminder(
            id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
            reminder: Reminder(intervalDays: intervalDays, countedFrom: countedFrom),
            now: countedFrom,
            fileURL: fileURL
        )

        #expect(try loadFavorites(fileURL: fileURL) == [favorite(idSuffix: "1", reminder: Reminder(intervalDays: intervalDays, countedFrom: countedFrom))])
    }

    @Test(arguments: [0, -1])
    func 日数が1未満のリマインドは保存しない(intervalDays: Int) throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: nil)
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)

        #expect(throws: FavoriteStoreError.reminderIntervalDaysLessThanOne) {
            try setFavoriteReminder(
                id: savedFavorite.id,
                reminder: Reminder(intervalDays: intervalDays, countedFrom: countedFrom),
                now: countedFrom,
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL) == [savedFavorite])
    }

    @Test func 無いお気に入りのリマインドの設定はエラーにする() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [favorite(idSuffix: "1", reminder: nil)], fileURL: fileURL)

        #expect(throws: FavoriteStoreError.favoriteNotFound) {
            try setFavoriteReminder(
                id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA9")!,
                reminder: Reminder(intervalDays: 30, countedFrom: countedFrom),
                now: countedFrom,
                fileURL: fileURL
            )
        }
    }

    // MARK: - 購入画面を開く時の数え直し

    @Test func 購入画面を開くと数え始めた日時がその時刻に書き換わりURLを返す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let openedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        let otherFavorite = favorite(idSuffix: "2", reminder: Reminder(intervalDays: 7, countedFrom: countedFrom))
        try saveFavorites(favorites: [openedFavorite, otherFavorite], fileURL: fileURL)
        let openedAt = countedFrom.addingTimeInterval(40 * daySeconds)

        #expect(
            try purchaseURLForOpening(favoriteID: openedFavorite.id, now: openedAt, fileURL: fileURL)?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(
            try loadFavorites(fileURL: fileURL) == [
                favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: openedAt)),
                otherFavorite,
            ]
        )
    }

    @Test func リマインドの無いお気に入りの購入画面を開いてもリマインドは付かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let openedFavorite = favorite(idSuffix: "1", reminder: nil)
        try saveFavorites(favorites: [openedFavorite], fileURL: fileURL)

        #expect(
            try purchaseURLForOpening(favoriteID: openedFavorite.id, now: countedFrom, fileURL: fileURL)?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(try loadFavorites(fileURL: fileURL) == [openedFavorite])
    }

    @Test func 通知が指すお気に入りが無い時は購入画面のURLを返さず保存も変えない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)

        #expect(
            try purchaseURLForOpening(
                favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA9")!,
                now: countedFrom.addingTimeInterval(40 * daySeconds),
                fileURL: fileURL
            ) == nil
        )
        #expect(try loadFavorites(fileURL: fileURL) == [savedFavorite])
    }

    @Test func お気に入りが1件も無い時は購入画面のURLを返さない() throws {
        #expect(try purchaseURLForOpening(favoriteID: UUID(), now: countedFrom, fileURL: temporaryFavoritesFileURL()) == nil)
    }

    @Test func 購入画面のURLを組み立てられないお気に入りでは数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        var amazonFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        amazonFavorite.product = .amazon(AmazonProduct(asin: "B000000000"))
        try saveFavorites(favorites: [amazonFavorite], fileURL: fileURL)

        #expect(try purchaseURLForOpening(favoriteID: amazonFavorite.id, now: countedFrom.addingTimeInterval(40 * daySeconds), fileURL: fileURL) == nil)
        #expect(try loadFavorites(fileURL: fileURL) == [amazonFavorite])
    }

    // MARK: - 通知の内容

    @Test func 通知の内容はお気に入りの名前と識別子だけを持ち購入画面のURLを持たない() {
        let content = reminderNotificationContent(favorite: favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)))

        #expect(content.title == "そろそろ買う頃です")
        #expect(content.body == "コーヒー豆 1\nタップすると購入画面が開きます")
        #expect(reminderNotificationFavoriteID(userInfo: content.userInfo) == UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!)
        #expect(content.userInfo.count == 1)
        #expect(!"\(content.title)\(content.subtitle)\(content.body)\(content.userInfo)".contains("mori-coffee.example"))
    }

    @Test func 識別子の形でない通知の付加情報からは識別子を取り出さない() {
        #expect(reminderNotificationFavoriteID(userInfo: [:]) == nil)
        #expect(reminderNotificationFavoriteID(userInfo: ["favoriteID": "識別子ではない"]) == nil)
        #expect(reminderNotificationFavoriteID(userInfo: ["favoriteID": 1]) == nil)
    }

    // MARK: - 開発者メニュー

    @Test func 日数が過ぎた状態にするとリマインドのあるお気に入りだけが過ぎた扱いになる() throws {
        let fileURL = temporaryFavoritesFileURL()
        let favoriteWithoutReminder = favorite(idSuffix: "2", reminder: nil)
        try saveFavorites(
            favorites: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)), favoriteWithoutReminder],
            fileURL: fileURL
        )
        let now = countedFrom.addingTimeInterval(2 * daySeconds)

        try makeFavoriteRemindersDue(now: now, fileURL: fileURL)

        #expect(
            try loadFavorites(fileURL: fileURL) == [
                favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom.addingTimeInterval(-28 * daySeconds))),
                favoriteWithoutReminder,
            ]
        )
        #expect(try loadFavorites(fileURL: fileURL).map { reminderStatusText(reminder: $0.reminder, now: now) } == ["そろそろ買う頃", "知らせなし"])
    }
}
