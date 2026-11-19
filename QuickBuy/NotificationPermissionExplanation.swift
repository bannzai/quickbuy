import SwiftUI
import UserNotifications

/// 通知の許可の説明の画面を出したことの記録を、端末の設定の保存先 (`UserDefaults`) に入れる時のキー。
let notificationPermissionExplanationPresentedKey = "isNotificationPermissionExplanationPresented"

/// 通知の許可の説明の画面を、この端末で出したことがあるかを返す。記録が無い時は false。
func isNotificationPermissionExplanationPresented(userDefaults: UserDefaults) -> Bool {
    userDefaults.bool(forKey: notificationPermissionExplanationPresentedKey)
}

/// 通知の許可の説明の画面を出したことを記録する。記録済みの時に呼んでも記録は変わらない。
func recordNotificationPermissionExplanationPresented(userDefaults: UserDefaults) {
    userDefaults.set(true, forKey: notificationPermissionExplanationPresentedKey)
}

/// 通知の許可の説明の画面を出すかを返す。
///
/// 出すのは、お気に入りが 1 件以上あり、通知の許可をまだ聞かれておらず (`.notDetermined`)、説明の画面を出した記録が無い時だけ。
/// - 件数を「ちょうど 1 件」にしないのは、1 回の追加の操作で複数のお気に入りが保存されるため (0 件から 2 件以上になった人にも出す)
/// - 許可済み・拒否済みの端末に出さないのは、iOS の許可の問いは 1 回しか出せず、「通知をオンにする」を押しても問いが出ないため
/// - 追加・編集・設定の画面が出ている間 (`isAnotherScreenPresented`) は出さない。同時には表示されず、出したつもりのまま表示されないため
func shouldPresentNotificationPermissionExplanation(
    favoriteCount: Int,
    authorizationStatus: UNAuthorizationStatus,
    isExplanationPresented: Bool,
    isAnotherScreenPresented: Bool
) -> Bool {
    favoriteCount >= 1 && authorizationStatus == .notDetermined && !isExplanationPresented && !isAnotherScreenPresented
}

/// 通知の許可を求める前の説明の画面。通知を何に使うかを伝え、「通知をオンにする」を押した時だけ iOS の許可の問いを出す。
///
/// 文言と並びは画面の見本 (documents/design/mock-2026-11-18/project/PushPermission.dc.html) のとおり。
struct NotificationPermissionExplanationView: View {
    /// 記録の保存先。画面が出た時に、出したことをここへ記録する。
    let userDefaults: UserDefaults
    /// この画面を閉じる処理。「あとで」を押した時と、iOS の許可の問いに答えた後に呼ぶ。
    let onFinish: () -> Void

    /// iOS の許可の問いを出している間は true (問いに答えるまで、ボタンをもう一度押せないようにする)。
    @State private var isRequestingAuthorization = false

    /// 絵・見出し・通知を使う 2 つの場面・補足と、下に固定した「通知をオンにする」「あとで」のボタン。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                illustration
                Text("通知をオンにするとウィジェットから買い直せます")
                    .font(.title.weight(.black))
                VStack(alignment: .leading, spacing: 14) {
                    usage(
                        number: 1,
                        title: "ウィジェットで「カートイン」を押した時",
                        description: "「購入画面を開きますか？」の通知を出します。通知をタップすると店の購入画面が開きます"
                    )
                    usage(
                        number: 2,
                        title: "そろそろ買う頃になった時",
                        description: "お気に入りごとに決めた日数が過ぎたら知らせます"
                    )
                }
                Text("通知だけでは購入されません。支払いの確定は毎回店の画面で行います。宣伝の通知は送りません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    isRequestingAuthorization = true
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        onFinish()
                    }
                } label: {
                    Text("通知をオンにする")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("enableNotificationButton")
                Button("あとで", action: onFinish)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("laterNotificationButton")
            }
            .disabled(isRequestingAuthorization)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.background)
        }
        .tint(quickBuyAccentColor)
        // 出したことの記録は、出すと決めた時ではなく画面が実際に出た時に書く (別の画面が出ていて表示されなかった時に、記録だけが残らないようにするため)。
        .onAppear {
            recordNotificationPermissionExplanationPresented(userDefaults: userDefaults)
        }
    }

    /// ウィジェットの「カートイン」から「購入画面を開きますか？」の通知が出ることを表す絵。読み上げの対象にしない (同じ内容を下の文が伝えるため)。
    private var illustration: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 34, height: 34)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tint)
                    .frame(height: 22)
            }
            .padding(12)
            .frame(width: 96, height: 96)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
            Image(systemName: "arrow.right")
                .font(.title2.bold())
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.tint)
                        .frame(width: 20, height: 20)
                    Text("Quick Buy")
                        .font(.caption2.weight(.black))
                }
                Text("購入画面を開きますか？")
                    .font(.caption.bold())
            }
            .padding(10)
            .frame(width: 150, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(quickBuyAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    /// 通知を使う場面 1 つ分の行。番号の印・場面の見出し・その場面で何が起きるかの説明。
    private func usage(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.weight(.black))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(quickBuyAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.bold())
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
