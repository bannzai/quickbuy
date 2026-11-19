import Foundation

/// リマインドが 1 日として数える秒数 (24 時間)。通知の予約が秒数で数えるため、暦の日付の変わり目では数えない。
let reminderDaySeconds: TimeInterval = 86400

/// リマインドの「何日ごと」を秒数にして返す。
func reminderTimeInterval(reminder: Reminder) -> TimeInterval {
    TimeInterval(reminder.intervalDays) * reminderDaySeconds
}

/// リマインドの日数が過ぎたか (日数を数え始めた日時から、設定した日数が `now` までに過ぎたか) を返す。
///
/// 過ぎた後は、購入画面を開いて数え直すか、リマインドを設定し直すまで true のまま。
func isReminderDue(reminder: Reminder, now: Date) -> Bool {
    now.timeIntervalSince(reminder.countedFrom) >= reminderTimeInterval(reminder: reminder)
}

/// `now` より後で、最初に知らせる日時を返す。
///
/// 通知は日数を数え始めた日時から設定した日数ごとに出るため、日数が過ぎた後 (通知が無視された後) は、その次の回の日時になる。
/// `now` がちょうど知らせる日時の時は、その次の回を返す。`now` が日数を数え始めた日時より前の時 (端末の時計を戻した時) は、最初の回を返す。
func nextReminderDate(reminder: Reminder, now: Date) -> Date {
    let reminderInterval: TimeInterval = reminderTimeInterval(reminder: reminder)
    return reminder.countedFrom.addingTimeInterval(
        (max(0.0, (now.timeIntervalSince(reminder.countedFrom) / reminderInterval).rounded(.down)) + 1.0) * reminderInterval
    )
}

/// 一覧の行に出す、リマインドの状態の文言を `locale` の言語で返す。
///
/// リマインドを設定していない時は「知らせなし」、日数が過ぎた時は「そろそろ買う頃」、それ以外は次に知らせる日時までの日数 (1 日に満たない端数は切り上げる)。
func reminderStatusText(reminder: Reminder?, now: Date, locale: Locale) -> String {
    guard let reminder else {
        return String(localized: LocalizedStringResource("知らせなし", locale: locale))
    }
    guard !isReminderDue(reminder: reminder, now: now) else {
        return String(localized: LocalizedStringResource("そろそろ買う頃", locale: locale))
    }
    return String(localized: LocalizedStringResource("次の知らせは \(Int((nextReminderDate(reminder: reminder, now: now).timeIntervalSince(now) / reminderDaySeconds).rounded(.up))) 日後", locale: locale))
}

/// 保存の操作の後に、通知の予約へ加える変更。
enum ReminderNotificationChange: Equatable {
    /// そのお気に入りの通知の予約を取り消す。
    case cancel(favoriteID: UUID)
    /// そのお気に入りの前の予約を置き換えて、今から設定した日数ごとに知らせる予約をする。
    case schedule(favorite: Favorite)
}

/// 保存の操作の前後のお気に入りの並びを比べて、通知の予約へ加える変更を返す。
///
/// - リマインドのあったお気に入りが、削除された・リマインドをやめた時は、予約を取り消す
/// - リマインドが新しく設定された・日数が変わった・日数を数え始めた日時が変わった (数え直した) 時は、予約し直す
/// - リマインドが変わっていない時は何も返さない。名前だけを変えた時も予約し直さない (予約し直すと、通知が届く時刻が、日数を数え始めた日時からの日数ごとではなくなるため)
func reminderNotificationChanges(before: [Favorite], after: [Favorite]) -> [ReminderNotificationChange] {
    var changes: [ReminderNotificationChange] = []
    for beforeFavorite in before where beforeFavorite.reminder != nil {
        if !after.contains(where: { $0.id == beforeFavorite.id && $0.reminder != nil }) {
            changes.append(.cancel(favoriteID: beforeFavorite.id))
        }
    }
    for afterFavorite in after where afterFavorite.reminder != nil {
        if before.first(where: { $0.id == afterFavorite.id })?.reminder != afterFavorite.reminder {
            changes.append(.schedule(favorite: afterFavorite))
        }
    }
    return changes
}
