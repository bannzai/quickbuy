import Foundation
import Testing
import UserNotifications
@testable import QuickBuy

/// リマインドの、次に知らせる日時の計算・通知の予約と取り消しの判断・数え直し・通知が指すお気に入りの扱いを確かめる。
struct ReminderTests {
    /// 日数を数え始めた日時として使う、固定の日時 (2026-11-17 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)
    /// 1 日の秒数 (24 時間)。期待値を対象のコードの定数から作らないよう、テストの側に書いている。
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

    /// リマインドを設定していないお気に入りの行には「知らせなし」を出す。
    @Test func リマインドが無い時の文言は知らせなし() {
        #expect(reminderStatusText(reminder: nil, now: countedFrom) == "知らせなし")
    }

    // MARK: - 通知の予約と取り消しの判断

    /// リマインドの無かったお気に入りにリマインドが付くと、そのお気に入りの予約を 1 つ返す。
    @Test func リマインドを新しく設定すると予約する() {
        let favoriteWithReminder = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(before: [favorite(idSuffix: "1", reminder: nil)], after: [favoriteWithReminder])
                == [.schedule(favorite: favoriteWithReminder)]
        )
    }

    /// 日数だけが変わった時も、新しい日数のお気に入りで予約し直す。
    @Test func 日数を変えると予約し直す() {
        let favoriteWithNewInterval = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 14, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))],
                after: [favoriteWithNewInterval]
            ) == [.schedule(favorite: favoriteWithNewInterval)]
        )
    }

    /// 日数を数え始めた日時だけが変わった時 (購入画面を開いた時) も予約し直す。
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

    /// お気に入りは残り、リマインドだけが無くなった時は、そのお気に入りの予約を取り消す。
    @Test func リマインドをやめると予約を取り消す() {
        #expect(
            reminderNotificationChanges(
                before: [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))],
                after: [favorite(idSuffix: "1", reminder: nil)]
            ) == [.cancel(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!)]
        )
    }

    /// リマインドのあったお気に入りが並びから無くなった時は、そのお気に入りの予約だけを取り消す。
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

    /// リマインド付きのお気に入りが新しく並びに加わった時 (保存の前には無かった時) は、そのお気に入りの予約を返す。
    @Test func リマインド付きのお気に入りが加わると予約する() {
        let existingFavorite = favorite(idSuffix: "1", reminder: nil)
        let addedFavorite = favorite(idSuffix: "2", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        #expect(
            reminderNotificationChanges(before: [existingFavorite], after: [existingFavorite, addedFavorite])
                == [.schedule(favorite: addedFavorite)]
        )
    }

    // MARK: - 保存の操作と通知の予約のつなぎ

    /// 保存の操作が成功した時は、操作の前後の違いから決めた変更が 1 回だけ渡る。
    @Test func 保存の操作の後に前後の違いの変更が渡る() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: nil)
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        let savedAt = countedFrom.addingTimeInterval(3 * daySeconds)
        var appliedChanges: [[ReminderNotificationChange]] = []

        try performSaving(fileURL: fileURL, applyChanges: { appliedChanges.append($0) }) {
            try setFavoriteReminder(id: savedFavorite.id, reminder: Reminder(intervalDays: 30, countedFrom: countedFrom), now: savedAt, fileURL: fileURL)
        }

        #expect(appliedChanges == [[.schedule(favorite: favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: savedAt)))]])
    }

    /// 操作が途中でエラーを投げた時も、そこまでに保存された分の変更が渡り、そのエラーが呼び出し側へ投げられる。
    @Test func 操作が途中で失敗しても保存済みの分の変更が渡りエラーが投げられる() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(throws: FavoriteStoreError.favoriteNotFound) {
            try performSaving(fileURL: fileURL, applyChanges: { appliedChanges.append($0) }) {
                try setFavoriteReminder(id: savedFavorite.id, reminder: nil, now: countedFrom, fileURL: fileURL)
                try setFavoriteReminder(id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA9")!, reminder: nil, now: countedFrom, fileURL: fileURL)
            }
        }
        #expect(appliedChanges == [[.cancel(favoriteID: savedFavorite.id)]])
    }

    /// 操作の前に保存先を読めない時 (中身が壊れている時) は、操作を実行せず、変更も渡さずにエラーを投げる。
    @Test func 保存先を読めない時は操作を実行せず変更も渡さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data("壊れた中身".utf8).write(to: fileURL)
        var appliedChanges: [[ReminderNotificationChange]] = []
        var isOperationPerformed = false

        #expect(throws: (any Error).self) {
            try performSaving(fileURL: fileURL, applyChanges: { appliedChanges.append($0) }) {
                isOperationPerformed = true
            }
        }
        #expect(!isOperationPerformed)
        #expect(appliedChanges.isEmpty)
    }

    // MARK: - 通知への操作

    /// 通知のタップでは、通知が指すお気に入りの購入画面の URL を返し、そのお気に入りを数え直して予約し直す変更を渡す。
    @Test func 通知のタップで購入画面のURLを返し数え直して予約し直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let notifiedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [notifiedFavorite], fileURL: fileURL)
        let tappedAt = countedFrom.addingTimeInterval(31 * daySeconds)
        let recountedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: tappedAt))
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(
            purchaseURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: ["favoriteID": notifiedFavorite.id.uuidString],
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { appliedChanges.append($0) }
            )?.absoluteString == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(try loadFavorites(fileURL: fileURL) == [recountedFavorite])
        #expect(appliedChanges == [[.schedule(favorite: recountedFavorite)]])
    }

    /// 通知を消す操作 (タップ以外の操作) では、購入画面を開かず、数え直しもしない。
    @Test func 通知を消す操作では購入画面を開かず数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let notifiedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [notifiedFavorite], fileURL: fileURL)
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(
            purchaseURLForNotificationResponse(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                userInfo: ["favoriteID": notifiedFavorite.id.uuidString],
                now: countedFrom.addingTimeInterval(31 * daySeconds),
                fileURL: fileURL,
                applyChanges: { appliedChanges.append($0) }
            ) == nil
        )
        #expect(try loadFavorites(fileURL: fileURL) == [notifiedFavorite])
        #expect(appliedChanges.isEmpty)
    }

    /// 付加情報にお気に入りの識別子が無い通知のタップでは、購入画面を開かず、数え直しもしない。
    @Test func 識別子の無い通知のタップでは購入画面を開かず数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(
            purchaseURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: [:],
                now: countedFrom.addingTimeInterval(31 * daySeconds),
                fileURL: fileURL,
                applyChanges: { appliedChanges.append($0) }
            ) == nil
        )
        #expect(try loadFavorites(fileURL: fileURL) == [savedFavorite])
        #expect(appliedChanges.isEmpty)
    }

    /// 保存先を読めない時 (中身が壊れている時) の通知のタップでは、エラーにせず nil を返して購入画面を開かない。
    @Test func 保存先を読めない時の通知のタップでは購入画面を開かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data("壊れた中身".utf8).write(to: fileURL)

        #expect(
            purchaseURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: ["favoriteID": "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1"],
                now: countedFrom,
                fileURL: fileURL,
                applyChanges: { _ in }
            ) == nil
        )
    }

    /// 保存先を読めない時 (中身が壊れている時) は、一覧の「買う」が使う関数は URL を返さずにエラーを投げる (一覧は「保存できませんでした」を出して購入画面を開かない)。
    @Test func 保存先を読めない時は購入画面のURLを返さずエラーを投げる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data("壊れた中身".utf8).write(to: fileURL)

        #expect(throws: (any Error).self) {
            try purchaseURLForOpening(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!, now: countedFrom, fileURL: fileURL)
        }
    }

    // MARK: - リマインドの保存

    /// 渡したリマインドの日時ではなく、保存の時刻から数え始める。ほかのお気に入りは変えない。
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

    /// 編集の画面でリマインドに触れずに保存した時は、数え直さない。
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

    /// 日数を変えて保存した時は、新しい日数で保存の時刻から数え始める。
    @Test func 日数を変えて保存すると保存の時刻から数え直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        let savedAt = countedFrom.addingTimeInterval(10 * daySeconds)

        try setFavoriteReminder(id: savedFavorite.id, reminder: Reminder(intervalDays: 7, countedFrom: countedFrom), now: savedAt, fileURL: fileURL)

        #expect(try loadFavorites(fileURL: fileURL) == [favorite(idSuffix: "1", reminder: Reminder(intervalDays: 7, countedFrom: savedAt))])
    }

    /// リマインドに nil を渡すと、保存済みのリマインドが無くなる。
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

    /// 日数が 0 以下のリマインドはエラーにし、保存済みの内容を変えない。
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

    /// 保存されていない識別子を渡した時は、お気に入りが無いエラーを投げる。
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

    /// 購入画面を開いたお気に入りだけを開いた時刻から数え直し、ほかのお気に入りのリマインドは変えない。
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

    /// リマインドを設定していないお気に入りは、購入画面を開いても保存の内容が変わらない。
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

    /// 削除済みのお気に入りを指す識別子では、先頭のお気に入りなど別のお気に入りの購入画面を開かない。
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

    /// 保存先のファイルがまだ無い時も、エラーにせず nil を返す。
    @Test func お気に入りが1件も無い時は購入画面のURLを返さない() throws {
        #expect(try purchaseURLForOpening(favoriteID: UUID(), now: countedFrom, fileURL: temporaryFavoritesFileURL()) == nil)
    }

    /// 購入画面を開けない Amazon の商品のお気に入りは、開いたことにならないので数え直さない。
    @Test func 購入画面のURLを組み立てられないお気に入りでは数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        var amazonFavorite = favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom))
        amazonFavorite.product = .amazon(AmazonProduct(asin: "B000000000"))
        try saveFavorites(favorites: [amazonFavorite], fileURL: fileURL)

        #expect(try purchaseURLForOpening(favoriteID: amazonFavorite.id, now: countedFrom.addingTimeInterval(40 * daySeconds), fileURL: fileURL) == nil)
        #expect(try loadFavorites(fileURL: fileURL) == [amazonFavorite])
    }

    // MARK: - 通知の内容

    /// 通知には見本どおりの 3 行と識別子だけを載せ、店のドメインを含む値を載せない。
    @Test func 通知の内容はお気に入りの名前と識別子だけを持ち購入画面のURLを持たない() {
        let content = reminderNotificationContent(favorite: favorite(idSuffix: "1", reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)))

        #expect(content.title == "そろそろ買う頃です")
        #expect(content.body == "コーヒー豆 1\nタップすると購入画面が開きます")
        #expect(reminderNotificationFavoriteID(userInfo: content.userInfo) == UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!)
        #expect(content.userInfo.count == 1)
        #expect(!"\(content.title)\(content.subtitle)\(content.body)\(content.userInfo)".contains("mori-coffee.example"))
    }

    /// 付加情報が空・文字列が識別子の形でない・値が文字列でない時は nil を返す。
    @Test func 識別子の形でない通知の付加情報からは識別子を取り出さない() {
        #expect(reminderNotificationFavoriteID(userInfo: [:]) == nil)
        #expect(reminderNotificationFavoriteID(userInfo: ["favoriteID": "識別子ではない"]) == nil)
        #expect(reminderNotificationFavoriteID(userInfo: ["favoriteID": 1]) == nil)
    }

    // MARK: - 開発者メニュー

    /// 数え始めた日時を、今から設定した日数だけ前にずらす。リマインドの無いお気に入りは変えない。
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
