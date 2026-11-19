import AppIntents
import UserNotifications

/// ウィジェットの行の「カートイン」(Amazon の商品は「Amazon で開く」) のボタンの処理。アプリを開かずに、そのお気に入りの確認の通知 (`cartInConfirmationNotificationContent(favorite:locale:)`) を出す。
///
/// 購入画面も商品ページも開かない。開くのは、利用者が確認の通知をタップした時のアプリ (`ReminderNotificationDelegate`)。
struct CartInIntent: AppIntent {
    /// ショートカットのアプリなどに出す名前。
    static var title: LocalizedStringResource = "カートイン"
    /// ウィジェットのボタンからだけ使うため、ショートカットのアプリと Spotlight には出さない。
    static var isDiscoverable = false

    /// 確認の通知を出すお気に入りの識別子 (`UUID` の文字列)。
    @Parameter(title: "お気に入りの識別子")
    var favoriteID: String

    /// システムがボタンの押下から処理を作り直す時に使う (`AppIntent` が引数の無い初期化を求めるため)。
    init() {}

    /// ウィジェットの行のボタンに渡す処理を、お気に入りの識別子から作る (`@Parameter` の値は memberwise initializer で渡せないため)。
    init(favoriteID: UUID) {
        self.favoriteID = favoriteID.uuidString
    }

    /// 確認の通知を出す。お気に入りの保存先を得られない・識別子の形でない時は何もしない。
    func perform() async throws -> some IntentResult {
        guard let favoritesFileURL = sharedFavoritesFileURL(), let favoriteUUID = UUID(uuidString: favoriteID) else {
            return .result()
        }
        try await postCartInConfirmationNotification(favoriteID: favoriteUUID, fileURL: favoritesFileURL, center: .current())
        return .result()
    }
}
