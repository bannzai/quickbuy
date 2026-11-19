import Foundation
import UserNotifications

/// 通知が指すお気に入りの識別子を、通知の付加情報 (`userInfo`) に入れる時のキー。リマインドの通知と「カートイン」の確認の通知が使う。
let favoriteNotificationFavoriteIDKey = "favoriteID"

/// 通知の付加情報 (`userInfo`) から、通知が指すお気に入りの識別子を取り出して返す。入っていない・識別子の形でない時は nil を返す。
func favoriteNotificationFavoriteID(userInfo: [AnyHashable: Any]) -> UUID? {
    (userInfo[favoriteNotificationFavoriteIDKey] as? String).flatMap(UUID.init(uuidString:))
}

/// ウィジェットの「カートイン」で出す、「購入画面を開きますか？」の確認の通知の内容を返す。購入画面の URL を組み立てられないお気に入り (Amazon の商品) では nil を返す。
///
/// 文言は documents/design/mock-2026-11-18/project/WidgetPush.dc.html の通知の見本 (見出し・何を何個・どの店の購入画面が開くか)。
/// 載せるのは文言と、タップされた時にお気に入りを探すための識別子だけ。購入画面の URL は載せず、通知をタップされた時に保存済みのお気に入りから組み立てる (.claude/rules/purchase-url.md)。
func cartInConfirmationNotificationContent(favorite: Favorite) -> UNMutableNotificationContent? {
    guard purchaseURL(favorite: favorite) != nil, case let .shopify(shopifyProduct) = favorite.product else {
        return nil
    }
    let content = UNMutableNotificationContent()
    content.title = "購入画面を開きますか？"
    content.body = "\([favorite.name, favorite.variantName].compactMap { $0 }.joined(separator: " ")) を \(favorite.quantity) 個\nタップすると \(shopifyProduct.shopDomain) の購入画面が開きます"
    content.sound = .default
    content.userInfo = [favoriteNotificationFavoriteIDKey: favorite.id.uuidString]
    return content
}

/// 「カートイン」の確認の通知の、お気に入りごとの通知の識別子を返す。
///
/// 同じお気に入りの「カートイン」を続けて押した時に、確認の通知を増やさず 1 つに置き換えるため、お気に入り 1 件につき 1 つの値にする。
/// リマインドの通知の識別子 (お気に入りの識別子そのもの) と別の値にして、リマインドの予約を置き換えないようにする。
func cartInConfirmationNotificationIdentifier(favoriteID: UUID) -> String {
    "cartInConfirmation-\(favoriteID.uuidString)"
}

/// 「カートイン」の確認の通知を、すぐに出す通知の要求として返す。購入画面の URL を組み立てられないお気に入りでは nil を返す。
func cartInConfirmationNotificationRequest(favorite: Favorite) -> UNNotificationRequest? {
    cartInConfirmationNotificationContent(favorite: favorite).map { content in
        UNNotificationRequest(identifier: cartInConfirmationNotificationIdentifier(favoriteID: favorite.id), content: content, trigger: nil)
    }
}

/// 保存済みのお気に入りのうち、指定した識別子のものの「カートイン」の確認の通知の要求を返す。
///
/// 保存先を読むだけで書かない (リマインドの数え直しは、通知をタップして購入画面を開いた時に行う)。
/// その識別子のお気に入りが無い時と、購入画面の URL を組み立てられない時は nil を返す。保存先を読めない時はエラーを投げる。
func cartInConfirmationNotificationRequest(favoriteID: UUID, fileURL: URL) throws -> UNNotificationRequest? {
    try loadFavorites(fileURL: fileURL).first(where: { $0.id == favoriteID }).flatMap(cartInConfirmationNotificationRequest(favorite:))
}

/// 保存済みのお気に入りのうち、指定した識別子のものの「カートイン」の確認の通知を出す。ウィジェットの「カートイン」のボタンの処理が呼ぶ。
///
/// 出す通知は `cartInConfirmationNotificationRequest(favoriteID:fileURL:)` が返すもので、nil の時は何も出さない。
/// 保存先を読めない時と、通知を出せない時 (通知が許可されていない等) はエラーを投げる。
func postCartInConfirmationNotification(favoriteID: UUID, fileURL: URL, center: UNUserNotificationCenter) async throws {
    guard let request = try cartInConfirmationNotificationRequest(favoriteID: favoriteID, fileURL: fileURL) else {
        return
    }
    try await center.add(request)
}
