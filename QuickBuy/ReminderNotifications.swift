import UIKit
import UserNotifications

/// リマインドの通知が指すお気に入りの識別子を、通知の付加情報 (`userInfo`) に入れる時のキー。
let reminderNotificationFavoriteIDKey = "favoriteID"

/// お気に入りのリマインドの通知の内容を返す。
///
/// 載せるのは見出し・お気に入りの名前・案内の文言と、タップされた時にお気に入りを探すための識別子だけ。
/// 購入画面の URL は載せない (.claude/rules/purchase-url.md。URL はタップされた時に保存済みのお気に入りから組み立てる)。
func reminderNotificationContent(favorite: Favorite) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "そろそろ買う頃です"
    content.body = "\(favorite.name)\nタップすると購入画面が開きます"
    content.sound = .default
    content.userInfo = [reminderNotificationFavoriteIDKey: favorite.id.uuidString]
    return content
}

/// 通知の付加情報 (`userInfo`) から、通知が指すお気に入りの識別子を取り出して返す。入っていない・識別子の形でない時は nil を返す。
func reminderNotificationFavoriteID(userInfo: [AnyHashable: Any]) -> UUID? {
    (userInfo[reminderNotificationFavoriteIDKey] as? String).flatMap(UUID.init(uuidString:))
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
            guard let reminder = favorite.reminder else {
                continue
            }
            center.removeDeliveredNotifications(withIdentifiers: [favorite.id.uuidString])
            center.add(
                UNNotificationRequest(
                    identifier: favorite.id.uuidString,
                    content: reminderNotificationContent(favorite: favorite),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderTimeInterval(reminder: reminder), repeats: true)
                )
            )
        }
    }
}

/// お気に入りの保存の操作を実行し、その前後のお気に入りの違いから、通知の予約を取り消す・予約し直す。
///
/// 一覧・編集の画面・通知のタップ・開発者メニューの保存の操作をすべてここに通すことで、数え直した時・日数を変えた時・リマインドをやめた時・お気に入りを削除した時の予約の扱いを 1 か所で決める。
/// 操作が途中でエラーを投げた時も、そこまでに保存された分を予約に反映してから、そのエラーを投げる。
func performSavingWithReminderNotifications(fileURL: URL, center: UNUserNotificationCenter, operation: () throws -> Void) throws {
    let favoritesBeforeOperation = try loadFavorites(fileURL: fileURL)
    defer {
        if let favoritesAfterOperation = try? loadFavorites(fileURL: fileURL) {
            applyReminderNotificationChanges(
                changes: reminderNotificationChanges(before: favoritesBeforeOperation, after: favoritesAfterOperation),
                center: center
            )
        }
    }
    try operation()
}

/// リマインドの通知を受け取る。通知がタップされた時に、通知が指すお気に入りの購入画面を開く。
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

    /// 通知がタップされた時に、通知が指すお気に入りの購入画面を既定のブラウザで開き、リマインドの日数を数え直す。
    ///
    /// 通知が指すお気に入りが保存されていない時は購入画面を開かない (アプリは開くので、お気に入りの一覧が表示される)。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let favoriteID = reminderNotificationFavoriteID(userInfo: response.notification.request.content.userInfo),
              let favoritesFileURL = sharedFavoritesFileURL()
        else {
            completionHandler()
            return
        }
        var openingURL: URL?
        try? performSavingWithReminderNotifications(fileURL: favoritesFileURL, center: center) {
            openingURL = try purchaseURLForOpening(favoriteID: favoriteID, now: .now, fileURL: favoritesFileURL)
        }
        guard let openingURL else {
            completionHandler()
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(openingURL) { _ in
                completionHandler()
            }
        }
    }
}
