import UIKit
import UserNotifications

/// お気に入りのリマインドの通知の内容を返す。
///
/// 載せるのは見出し・お気に入りの名前・商品バリアントの名前 (持つお気に入りだけ)・案内の文言と、タップされた時にお気に入りを探すための識別子だけ。
/// 商品バリアントの名前は、同じ商品の商品バリアントごとのお気に入りの通知を見分けられるよう、名前と同じ行に空白で区切って続ける
/// (並べ方は documents/design/mock-2026-11-18/project/WidgetPush.dc.html の通知の見本「コーヒー豆 200g / 豆のまま」)。
/// 案内の文言は、タップで開くもの (Shopify の店の商品は購入画面、Amazon の商品は商品ページ) を書く。
/// 開く URL は載せない (.claude/rules/purchase-url.md。URL はタップされた時に保存済みのお気に入りから組み立てる)。
func reminderNotificationContent(favorite: Favorite) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "そろそろ買う頃です"
    content.body = switch favorite.product {
    case .shopify:
        "\([favorite.name, favorite.variantName].compactMap { $0 }.joined(separator: " "))\nタップすると購入画面が開きます"
    case .amazon:
        "\(favorite.name)\nタップすると Amazon の商品ページが開きます"
    }
    content.sound = .default
    content.userInfo = [favoriteNotificationFavoriteIDKey: favorite.id.uuidString]
    return content
}

/// 通知の予約へ加える変更を、端末の通知の仕組みに反映する。
///
/// 予約は、お気に入りの識別子を通知の識別子にして 1 件につき 1 つにする。同じ識別子で予約すると、前の予約は置き換わる
/// (https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier の
/// 「If you use the same identifier when scheduling a new notification, the system removes the previously scheduled notification with that identifier and replaces it with the new one.」)。
/// 予約は繰り返しにして、無視された時も同じ日数が過ぎるたびに知らせる
/// (https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger/init(timeinterval:repeats:) の
/// 「Specify true to reschedule the notification request each time the system delivers the notification.」)。
/// 取り消す時と予約し直す時は、届いたまま残っているそのお気に入りの通知も消す。
func applyReminderNotificationChanges(changes: [ReminderNotificationChange], center: UNUserNotificationCenter) {
    for change in changes {
        switch change {
        case let .cancel(favoriteID):
            center.removePendingNotificationRequests(withIdentifiers: [favoriteID.uuidString])
            center.removeDeliveredNotifications(withIdentifiers: [favoriteID.uuidString])
        case let .schedule(favorite):
            guard let request = reminderNotificationRequest(favorite: favorite) else {
                continue
            }
            center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
            center.add(request)
        }
    }
}

/// お気に入りのリマインドの通知の予約を返す。リマインドを設定していないお気に入りでは nil を返す。
///
/// 通知の識別子はお気に入りの識別子 (1 件につき予約を 1 つにするため)。予約した時刻から、設定した日数ごとに繰り返し知らせる。
func reminderNotificationRequest(favorite: Favorite) -> UNNotificationRequest? {
    favorite.reminder.map { reminder in
        UNNotificationRequest(
            identifier: favorite.id.uuidString,
            content: reminderNotificationContent(favorite: favorite),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderTimeInterval(reminder: reminder), repeats: true)
        )
    }
}

/// お気に入りの保存の操作を実行し、その前後のお気に入りの違いから、通知の予約を取り消す・予約し直す。
///
/// 一覧・編集の画面・通知のタップ・開発者メニューの保存の操作をすべてここに通すことで、数え直した時・日数を変えた時・リマインドをやめた時・お気に入りを削除した時の予約の扱いを 1 か所で決める。
/// 操作が途中でエラーを投げた時も、そこまでに保存された分を予約に反映してから、そのエラーを投げる。
func performSavingWithReminderNotifications(fileURL: URL, center: UNUserNotificationCenter, operation: () throws -> Void) throws {
    try performSaving(
        fileURL: fileURL,
        applyChanges: { applyReminderNotificationChanges(changes: $0, center: center) },
        operation: operation
    )
}

/// お気に入りの保存の操作を実行し、その前後のお気に入りの違いから決めた、通知の予約へ加える変更を `applyChanges` に渡す。
///
/// 操作が途中でエラーを投げた時も、そこまでに保存された分の変更を `applyChanges` に渡してから、そのエラーを投げる。
/// 操作の前に保存先を読めない時は、操作を実行せず `applyChanges` も呼ばずにエラーを投げる。
/// 通知の仕組みを呼ばずにテストできるよう、変更を反映する処理を引数で受け取る。
func performSaving(fileURL: URL, applyChanges: ([ReminderNotificationChange]) -> Void, operation: () throws -> Void) throws {
    let favoritesBeforeOperation = try loadFavorites(fileURL: fileURL)
    defer {
        if let favoritesAfterOperation = try? loadFavorites(fileURL: fileURL) {
            applyChanges(reminderNotificationChanges(before: favoritesBeforeOperation, after: favoritesAfterOperation))
        }
    }
    try operation()
}

/// 通知 (リマインドの通知と「カートイン」の確認の通知) への操作を受けて、開く URL (`openingURL(favorite:)`。Shopify の店は購入画面、Amazon は商品ページ) を返す。
/// 開く時は、通知が指すお気に入りのリマインドを `now` から数え直して保存し、通知の予約へ加える変更を `applyChanges` に、開いた記録を `recordAnalyticsEvent` に渡す。
///
/// `notificationIdentifier` は通知の識別子。「カートイン」の確認の通知の識別子 (`cartInConfirmationNotificationIdentifier(favoriteID:)`) なら入口を確認の通知、それ以外ならリマインドの通知として記録する。
/// 次の時は何も保存も記録もせずに nil を返す (呼び出し側は何も開かない): 操作が通知のタップ (`UNNotificationDefaultActionIdentifier`) でない、
/// 通知の付加情報からお気に入りの識別子を取り出せない、通知が指すお気に入りが保存されていない、開く URL を組み立てられない、保存先を読めない・書けない。
func openingURLForNotificationResponse(
    actionIdentifier: String,
    notificationIdentifier: String,
    userInfo: [AnyHashable: Any],
    now: Date,
    fileURL: URL,
    applyChanges: ([ReminderNotificationChange]) -> Void,
    recordAnalyticsEvent: (AnalyticsEvent) -> Void
) -> URL? {
    guard actionIdentifier == UNNotificationDefaultActionIdentifier, let favoriteID = favoriteNotificationFavoriteID(userInfo: userInfo) else {
        return nil
    }
    var favoriteOpeningURL: URL?
    do {
        try performSaving(fileURL: fileURL, applyChanges: applyChanges) {
            favoriteOpeningURL = try openingURL(
                favoriteID: favoriteID,
                entryPoint: notificationIdentifier == cartInConfirmationNotificationIdentifier(favoriteID: favoriteID) ? .cartInNotification : .reminderNotification,
                now: now,
                fileURL: fileURL,
                recordAnalyticsEvent: recordAnalyticsEvent
            )
        }
    } catch {
        return nil
    }
    return favoriteOpeningURL
}

/// リマインドを設定しているのに、通知の予約が無いお気に入りの識別子を返す。
///
/// `pendingNotificationIdentifiers` は、端末に残っている未配信の予約の識別子 (お気に入りの識別子の文字列)。
func favoriteIDsMissingReminderNotification(favorites: [Favorite], pendingNotificationIdentifiers: Set<String>) -> [UUID] {
    favorites
        .filter { $0.reminder != nil && !pendingNotificationIdentifiers.contains($0.id.uuidString) }
        .map(\.id)
}

/// 通知が許可されているのに予約の無いリマインドを予約する。アプリが前面に来た時に呼ぶ。
///
/// 通知を拒否している間に保存したリマインドは予約されない (拒否された状態の予約は失敗する。
/// https://developer.apple.com/documentation/usernotifications/unerror/notificationsnotallowed )。後から設定アプリで許可した時に届くようにする。
/// 通知が許可されていない時、予約の無いリマインドが無い時、保存先を読めない・書けない時は何も変えない。
/// 画面からの保存の操作と同時に保存先を読み書きしないよう、メインのスレッド (画面の操作と同じ) で実行する。
@MainActor
func restoreMissingReminderNotifications(fileURL: URL, center: UNUserNotificationCenter, now: Date) async {
    guard await center.notificationSettings().authorizationStatus == .authorized else {
        return
    }
    try? await restoreMissingReminderNotifications(
        fileURL: fileURL,
        pendingNotificationIdentifiers: Set(center.pendingNotificationRequests().map(\.identifier)),
        now: now,
        applyChanges: { applyReminderNotificationChanges(changes: $0, center: center) }
    )
}

/// 予約の無いリマインドについて、通知の予約へ加える変更を `applyChanges` に渡す。
///
/// - 日数がまだ過ぎていないリマインドは、`now` から数え直して保存し、予約する (予約は予約した時刻から日数ごとに届くため、一覧の「次の知らせは N 日後」と届く時刻を合わせる)
/// - 日数が過ぎているリマインドは、数え直さずに予約する (「そろそろ買う頃」は、購入画面を開くかリマインドを設定し直すまで出し続けるため)
///
/// `pendingNotificationIdentifiers` は、端末に残っている未配信の予約の識別子。予約の無いリマインドが無い時は `applyChanges` に空の変更が渡る。
/// 通知の仕組みを呼ばずにテストできるよう、未配信の予約の識別子と、変更を反映する処理を引数で受け取る。
func restoreMissingReminderNotifications(
    fileURL: URL,
    pendingNotificationIdentifiers: Set<String>,
    now: Date,
    applyChanges: ([ReminderNotificationChange]) -> Void
) throws {
    let favoritesMissingNotification = try loadFavorites(fileURL: fileURL).filter { favorite in
        favoriteIDsMissingReminderNotification(favorites: [favorite], pendingNotificationIdentifiers: pendingNotificationIdentifiers) == [favorite.id]
    }
    try performSaving(fileURL: fileURL, applyChanges: applyChanges) {
        for favorite in favoritesMissingNotification {
            if let reminder = favorite.reminder, !isReminderDue(reminder: reminder, now: now) {
                try recountFavoriteReminder(id: favorite.id, now: now, fileURL: fileURL)
            }
        }
    }
    applyChanges(
        favoritesMissingNotification
            .filter { favorite in favorite.reminder.map { isReminderDue(reminder: $0, now: now) } == true }
            .map { ReminderNotificationChange.schedule(favorite: $0) }
    )
}

/// リマインドの通知と「カートイン」の確認の通知を受け取る。通知がタップされた時に、通知が指すお気に入りの購入画面を開く。
///
/// 通知の仕組み (`UNUserNotificationCenterDelegate`) がクラスのオブジェクトを求めるため、クラスにしている。
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// アプリが前面にある時に通知が届いたら、前面でも通知の表示と音を出す。
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// 通知がタップされた時に、通知が指すお気に入りの購入画面 (Amazon の商品は商品ページ) をアプリの外で開き、リマインドの日数を数え直す。
    ///
    /// 通知が指すお気に入りが保存されていない時は何も開かない (アプリは開くので、お気に入りの一覧が表示される)。
    /// 画面からの保存の操作と同時に保存先を読み書きしないよう、数え直しの保存もメインのスレッド (画面の操作と同じ) で実行する。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            guard let favoritesFileURL = sharedFavoritesFileURL(),
                  let openingURL = openingURLForNotificationResponse(
                      actionIdentifier: response.actionIdentifier,
                      notificationIdentifier: response.notification.request.identifier,
                      userInfo: response.notification.request.content.userInfo,
                      now: .now,
                      fileURL: favoritesFileURL,
                      applyChanges: { applyReminderNotificationChanges(changes: $0, center: center) },
                      recordAnalyticsEvent: recordAnalyticsEventToFirebase(event:)
                  )
            else {
                completionHandler()
                return
            }
            UIApplication.shared.open(openingURL) { _ in
                completionHandler()
            }
        }
    }
}
