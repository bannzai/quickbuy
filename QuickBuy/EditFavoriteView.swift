import SwiftUI
import UIKit
import UserNotifications

/// お気に入りの編集の画面。名前と個数とリマインドを変えて保存する、またはお気に入りから外す。
struct EditFavoriteView: View {
    /// 編集中のお気に入り。開く時に保存済みの値を渡す。「保存」を押すまで保存先には書かない。
    @State var favorite: Favorite
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL
    /// この画面を閉じる処理。保存・削除の後と、戻る時に呼ぶ。
    let onFinish: () -> Void

    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false
    /// 端末の設定で Quick Buy の通知が拒否されている時は true。
    @State private var isNotificationDenied = false
    /// この画面でリマインドのオン・オフか日数を操作した時は true。操作していない保存では、保存先のリマインドを書き換えない
    /// (画面を開いている間に保存先のリマインドが数え直されていても、名前だけの保存で数え直さず、通知も予約し直さないため)。
    @State private var isReminderEdited = false

    /// 店のドメイン・名前と個数の入力・リマインドの設定・お気に入りから外すボタン。
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FavoriteThumbnail(imageURL: favorite.imageURL)
                        Text(shopDomainText(favorite: favorite))
                            .font(.headline)
                    }
                }
                Section {
                    TextField("名前", text: $favorite.name, axis: .vertical)
                        .accessibilityIdentifier("favoriteNameField")
                    // Amazon の商品は個数を持たない (個数は利用者が Amazon の画面で選ぶ。`amazonFavorite(asin:name:id:)`)。
                    if case .shopify = favorite.product {
                        QuantityStepperRow(quantity: $favorite.quantity)
                    }
                }
                Section {
                    Toggle("リマインド", isOn: isReminderOn)
                        .accessibilityIdentifier("favoriteReminderToggle")
                    if let reminder = favorite.reminder {
                        // 上限の 365 日は、いつもの商品を買い直す間隔として 1 年を超える設定を想定しないため。
                        Stepper(value: reminderIntervalDays(reminder: reminder), in: 1 ... 365) {
                            LabeledContent("知らせる間隔") {
                                Text("\(reminder.intervalDays) 日ごと")
                            }
                        }
                        .accessibilityIdentifier("favoriteReminderIntervalStepper")
                    }
                } footer: {
                    if let reminder = favorite.reminder {
                        if isNotificationDenied {
                            Text("\(reminderRecountText(favorite: favorite, locale: appTextLocale))\n次の知らせは \(nextReminderDate(reminder: reminder, now: .now).formatted(.dateTime.month().day())) です\n通知が許可されていません\n設定アプリで Quick Buy の通知を許可すると届きます")
                        } else {
                            Text("\(reminderRecountText(favorite: favorite, locale: appTextLocale))\n次の知らせは \(nextReminderDate(reminder: reminder, now: .now).formatted(.dateTime.month().day())) です")
                        }
                    }
                }
                Section {
                    Button("お気に入りから外す", role: .destructive) {
                        finish {
                            try deleteFavorite(id: favorite.id, fileURL: favoritesFileURL)
                        }
                    }
                }
            }
            .navigationTitle("お気に入りの編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る", action: onFinish)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        finish {
                            try saveEditedFavorite(favorite: favorite, isReminderEdited: isReminderEdited, now: .now, fileURL: favoritesFileURL)
                        }
                    }
                    .disabled(!isFavoriteNameSavable(name: favorite.name))
                }
            }
            .alert("保存できませんでした", isPresented: $isSaveFailed) {}
        }
        .tint(quickBuyAccentColor)
        // 設定アプリで通知の許可を変えて戻った時にも案内を合わせるよう、画面を開いた時とアプリが前面に戻るたびに読み直す。
        .task {
            await refreshNotificationDenied()
        }
        // この画面は sheet の中に出るため、アプリが前面に戻ったことを、sheet の中でも届くアプリの通知で受け取る。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshNotificationDenied()
            }
        }
    }

    /// リマインドのオン・オフ。オンにした時は、既定の日数で今から数え始めるリマインドを編集中のお気に入りに入れ、通知の許可を求める。
    private var isReminderOn: Binding<Bool> {
        Binding {
            favorite.reminder != nil
        } set: { isOn in
            // 既定の 30 日は、画面の見本 (documents/design/mock-2026-11-17/ の「お気に入りの編集とリマインド」) の値。
            favorite.reminder = isOn ? Reminder(intervalDays: 30, countedFrom: .now) : nil
            isReminderEdited = true
            if isOn {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    await refreshNotificationDenied()
                }
            }
        }
    }

    /// 何日ごとに知らせるかの入力。日数を変えた時は、今から数え始めるリマインドに置き換える (保存すると、保存の時刻から数え始めるため)。
    private func reminderIntervalDays(reminder: Reminder) -> Binding<Int> {
        Binding {
            reminder.intervalDays
        } set: { intervalDays in
            favorite.reminder = Reminder(intervalDays: intervalDays, countedFrom: .now)
            isReminderEdited = true
        }
    }

    /// 端末の通知の設定を読み、Quick Buy の通知が拒否されているかを表示に反映する。
    private func refreshNotificationDenied() async {
        isNotificationDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// 保存の操作を実行し、成功したら画面を閉じる。失敗した時は画面を閉じずにその旨を知らせる。
    /// 操作で変わったリマインドに合わせて、通知の予約も取り消す・予約し直す。
    private func finish(operation: () throws -> Void) {
        do {
            try performSavingWithReminderNotifications(fileURL: favoritesFileURL, center: .current(), operation: operation)
            onFinish()
        } catch {
            isSaveFailed = true
        }
    }
}

/// 編集の画面の「保存」で、編集中のお気に入りの名前と個数を保存し、`isReminderEdited` が true の時だけリマインドも保存する。
///
/// `isReminderEdited` は、編集の画面でリマインドのオン・オフか日数を操作したか。false の時は保存先のリマインドを書き換えない
/// (画面を開いている間に保存先のリマインドが数え直されていても、名前だけの保存で数え直さず、通知も予約し直さないため)。
/// true の時のリマインドの保存は `setFavoriteReminder(id:reminder:now:fileURL:)` に従い、`now` から数え始める。
/// その識別子のお気に入りが保存されていない時は `FavoriteStoreError.favoriteNotFound` を投げる。
func saveEditedFavorite(favorite: Favorite, isReminderEdited: Bool, now: Date, fileURL: URL) throws {
    try updateFavorite(id: favorite.id, name: favorite.name, quantity: favorite.quantity, fileURL: fileURL)
    if isReminderEdited {
        try setFavoriteReminder(id: favorite.id, reminder: favorite.reminder, now: now, fileURL: fileURL)
    }
}

/// リマインドの設定の下に出す、日数を数え直す時の文を `locale` の言語で返す。Shopify の店の商品は購入画面、Amazon の商品は商品ページを開いた日から数え直す (`openingURL(favoriteID:now:fileURL:)`)。
func reminderRecountText(favorite: Favorite, locale: Locale) -> String {
    switch favorite.product {
    case .shopify:
        String(localized: LocalizedStringResource("購入画面を開いた日から数え直します", locale: locale))
    case .amazon:
        String(localized: LocalizedStringResource("Amazon の商品ページを開いた日から数え直します", locale: locale))
    }
}
