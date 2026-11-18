import Foundation
import Testing
import UserNotifications
@testable import QuickBuy

/// 通知の許可の説明の画面を出すかどうかの判定と、出したことの記録を確かめる。
struct NotificationPermissionExplanationTests {
    /// ほかのテストと端末の設定に触れない、このテストだけの記録の保存先を作って `body` に渡し、終わったら消す。
    private func withTemporaryUserDefaults(body: (UserDefaults) throws -> Void) throws {
        let suiteName = "NotificationPermissionExplanationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        try body(userDefaults)
    }

    // MARK: - 出すかどうかの判定

    /// お気に入りが 1 件も無い間は、通知の許可を聞かれていなくても出さない。
    @Test func お気に入りが0件の間は出さない() {
        #expect(!shouldPresentNotificationPermissionExplanation(favoriteCount: 0, authorizationStatus: .notDetermined, isExplanationPresented: false))
    }

    /// 最初の追加で 1 件になった時も、1 回の追加で 2 件以上になった時も出す。
    @Test(arguments: [1, 2, 3])
    func お気に入りが1件以上になったら出す(favoriteCount: Int) {
        #expect(
            shouldPresentNotificationPermissionExplanation(
                favoriteCount: favoriteCount,
                authorizationStatus: .notDetermined,
                isExplanationPresented: false
            )
        )
    }

    /// 通知の許可を既に聞かれた端末 (許可済み・拒否済みなど) では、お気に入りがあって記録が無くても出さない。
    @Test(arguments: [UNAuthorizationStatus.authorized, .denied, .provisional, .ephemeral])
    func 通知の許可を聞かれた後の端末では出さない(authorizationStatus: UNAuthorizationStatus) {
        #expect(
            !shouldPresentNotificationPermissionExplanation(
                favoriteCount: 1,
                authorizationStatus: authorizationStatus,
                isExplanationPresented: false
            )
        )
    }

    /// 出した記録がある時は、お気に入りがあって通知の許可を聞かれていなくても出さない (「あとで」を選んだ人に追加のたびに出さない)。
    @Test func 出した記録がある時は出さない() {
        #expect(!shouldPresentNotificationPermissionExplanation(favoriteCount: 1, authorizationStatus: .notDetermined, isExplanationPresented: true))
        #expect(!shouldPresentNotificationPermissionExplanation(favoriteCount: 2, authorizationStatus: .notDetermined, isExplanationPresented: true))
    }

    // MARK: - 出したことの記録

    /// 何も記録していない保存先では、出したことが無い扱いになる。
    @Test func 記録が無い時は出したことが無い() throws {
        try withTemporaryUserDefaults { userDefaults in
            #expect(!isNotificationPermissionExplanationPresented(userDefaults: userDefaults))
        }
    }

    /// 最初の 1 件の後に 1 回出すと記録が残り、次の追加の後には出さない。記録は 2 回書いても変わらない。
    @Test func 記録した後は次の追加で出さない() throws {
        try withTemporaryUserDefaults { userDefaults in
            #expect(
                shouldPresentNotificationPermissionExplanation(
                    favoriteCount: 1,
                    authorizationStatus: .notDetermined,
                    isExplanationPresented: isNotificationPermissionExplanationPresented(userDefaults: userDefaults)
                )
            )
            recordNotificationPermissionExplanationPresented(userDefaults: userDefaults)
            recordNotificationPermissionExplanationPresented(userDefaults: userDefaults)
            #expect(isNotificationPermissionExplanationPresented(userDefaults: userDefaults))
            #expect(
                !shouldPresentNotificationPermissionExplanation(
                    favoriteCount: 2,
                    authorizationStatus: .notDetermined,
                    isExplanationPresented: isNotificationPermissionExplanationPresented(userDefaults: userDefaults)
                )
            )
        }
    }

    /// 開発者メニューで記録を消すと、出したことが無い状態に戻る。記録が無い時に消しても変わらない。
    @Test func 記録を消すと出したことが無い状態に戻る() throws {
        try withTemporaryUserDefaults { userDefaults in
            resetNotificationPermissionExplanationPresented(userDefaults: userDefaults)
            #expect(!isNotificationPermissionExplanationPresented(userDefaults: userDefaults))
            recordNotificationPermissionExplanationPresented(userDefaults: userDefaults)
            resetNotificationPermissionExplanationPresented(userDefaults: userDefaults)
            #expect(!isNotificationPermissionExplanationPresented(userDefaults: userDefaults))
        }
    }
}
