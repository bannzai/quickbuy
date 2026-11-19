import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit

/// ホーム画面に置く、お気に入りを保存した並びで 1 件 1 行に出すウィジェット。行の「カートイン」を押すと「購入画面を開きますか？」の確認の通知が届き、通知をタップした時に店の購入画面が開く。
struct FavoritesWidget: Widget {
    /// ウィジェットの構成 (種類の識別子・表示名・対応するサイズ)。
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: favoritesWidgetKind, provider: FavoritesTimelineProvider()) { favoritesTimelineEntry in
            FavoritesWidgetView(entry: favoritesTimelineEntry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("お気に入り")
        .description("いつもの商品をホーム画面からカートイン")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// ウィジェットの 1 回分の表示内容。
struct FavoritesTimelineEntry: TimelineEntry {
    /// この内容を表示し始める時刻。行の「そろそろ買う頃」は、この時刻でリマインドの日数が過ぎたかで決める。
    let date: Date
    /// 保存済みのお気に入りの並び。保存先を読めなかった時は nil。
    let favorites: [Favorite]?
    /// 通知が許可されているか。許可されていない時は「カートイン」で確認の通知を出せないため、ボタンを出さない。
    let isNotificationAuthorized: Bool
}

/// ウィジェットに表示内容を渡す。保存済みのお気に入りの今の並びを、今と、リマインドの日数が過ぎる各時刻の分だけ返す。
///
/// 並びが変わった時の表示の更新は、`saveFavorites(favorites:fileURL:)` とアプリが前面に来た時の更新の依頼で行う。
struct FavoritesTimelineProvider: TimelineProvider {
    /// 読み込み中に出す仮の表示内容を返す。お気に入りが無い時の表示を仮の表示にする。
    func placeholder(in _: Context) -> FavoritesTimelineEntry {
        FavoritesTimelineEntry(date: .now, favorites: [], isNotificationAuthorized: true)
    }

    /// ウィジェットの一覧などに出す表示内容を completion に渡す。
    func getSnapshot(in _: Context, completion: @escaping (FavoritesTimelineEntry) -> Void) {
        Task {
            await completion(savedFavoritesTimelineEntries(now: .now)[0])
        }
    }

    /// 表示内容の並びを completion に渡す。
    func getTimeline(in _: Context, completion: @escaping (Timeline<FavoritesTimelineEntry>) -> Void) {
        Task {
            await completion(Timeline(entries: savedFavoritesTimelineEntries(now: .now), policy: .never))
        }
    }

    /// 保存先から今のお気に入りを読み、通知の許可の状態と合わせた表示内容を、`favoritesWidgetTimelineDates(favorites:now:)` の時刻ごとに返す。先頭は `now` の表示内容。
    ///
    /// 保存先を得られない・読めない時は、お気に入りを nil にした `now` の表示内容 1 つを返す。
    private func savedFavoritesTimelineEntries(now: Date) async -> [FavoritesTimelineEntry] {
        let favorites = sharedFavoritesFileURL().flatMap { try? loadFavorites(fileURL: $0) }
        let isNotificationAuthorized = await isCartInAvailable(authorizationStatus: UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        return favoritesWidgetTimelineDates(favorites: favorites ?? [], now: now).map {
            FavoritesTimelineEntry(date: $0, favorites: favorites, isNotificationAuthorized: isNotificationAuthorized)
        }
    }
}

/// ウィジェットの見た目。お気に入りを大きさに入る数だけ 1 件 1 行で並べる。お気に入りが無い時は登録を促し、保存先を読めなかった時はその旨を出す。
///
/// 行の「カートイン」以外の場所をタップした時は、アプリのお気に入りの一覧が開く (ウィジェットのタップの既定の動き)。
struct FavoritesWidgetView: View {
    /// 表示する内容。
    let entry: FavoritesTimelineEntry

    /// ウィジェットの大きさ。
    @Environment(\.widgetFamily) private var widgetFamily

    /// 大きさと、お気に入りの有無ごとの表示。
    var body: some View {
        if let favorites = entry.favorites {
            if favorites.isEmpty {
                FavoritesWidgetMessage(
                    systemImageName: "cart",
                    title: "お気に入りはまだありません",
                    description: "アプリで商品を登録すると\nここに並びます"
                )
            } else if widgetFamily == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(widgetFavorites(favorites: favorites, widgetFamily: widgetFamily)) { favorite in
                        FavoriteWidgetSmallRow(favorite: favorite, now: entry.date, isNotificationAuthorized: entry.isNotificationAuthorized)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: widgetFamily == .systemLarge ? 10 : 8) {
                    if widgetFamily == .systemLarge {
                        Text("Quick Buy のお気に入り")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(quickBuyAccentColor)
                    }
                    ForEach(widgetFavorites(favorites: favorites, widgetFamily: widgetFamily)) { favorite in
                        FavoriteWidgetRow(
                            favorite: favorite,
                            now: entry.date,
                            isNotificationAuthorized: entry.isNotificationAuthorized,
                            iconSideLength: widgetFamily == .systemLarge ? 48 : 40
                        )
                    }
                    Spacer(minLength: 0)
                    if !entry.isNotificationAuthorized {
                        FavoritesWidgetNotificationRequiredText()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            FavoritesWidgetMessage(systemImageName: "exclamationmark.triangle", title: "お気に入りを読み込めません", description: nil)
        }
    }
}

/// 中サイズと大サイズのウィジェットの、お気に入り 1 件の行。左に買い物袋のアイコン、中に名前と「種類 ・ 個数」、右に「カートイン」を横に並べる。
struct FavoriteWidgetRow: View {
    /// 表示するお気に入り。
    let favorite: Favorite
    /// 表示している時刻。「そろそろ買う頃」を出すかを決める。
    let now: Date
    /// 通知が許可されているか。許可されていない時は「カートイン」を出さない。
    let isNotificationAuthorized: Bool
    /// アイコンの枠の 1 辺の長さ。
    let iconSideLength: CGFloat

    /// アイコン・名前と説明・「カートイン」。
    var body: some View {
        HStack(spacing: 10) {
            FavoriteWidgetIcon(sideLength: iconSideLength)
            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                FavoriteWidgetRowDetail(favorite: favorite, now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FavoriteWidgetCartInButton(favorite: favorite, isNotificationAuthorized: isNotificationAuthorized)
        }
    }
}

/// 小サイズのウィジェットの、お気に入り 1 件の行。名前・「種類 ・ 個数」・「カートイン」を縦に並べる (横に並べるには幅が足りないため)。
struct FavoriteWidgetSmallRow: View {
    /// 表示するお気に入り。
    let favorite: Favorite
    /// 表示している時刻。「そろそろ買う頃」を出すかを決める。
    let now: Date
    /// 通知が許可されているか。許可されていない時は「カートイン」の代わりに、通知の許可が要ることを出す。
    let isNotificationAuthorized: Bool

    /// 名前と説明・「カートイン」(または通知の許可が要ること)。
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(favorite.name)
                .font(.subheadline.bold())
                .lineLimit(2)
            FavoriteWidgetRowDetail(favorite: favorite, now: now)
            Spacer(minLength: 0)
            if isNotificationAuthorized {
                FavoriteWidgetCartInButton(favorite: favorite, isNotificationAuthorized: isNotificationAuthorized)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FavoritesWidgetNotificationRequiredText()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// ウィジェットの行の、名前の下に出す「種類 ・ 個数」と、リマインドの日数が過ぎた時の「そろそろ買う頃」。
struct FavoriteWidgetRowDetail: View {
    /// 表示するお気に入り。
    let favorite: Favorite
    /// 表示している時刻。
    let now: Date

    /// 「種類 ・ 個数」と、日数が過ぎた時だけ「そろそろ買う頃」。
    var body: some View {
        Text(favoriteWidgetRowCaption(favorite: favorite))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        if let reminder = favorite.reminder, isReminderDue(reminder: reminder, now: now) {
            Text("そろそろ買う頃")
                .font(.caption.bold())
                .foregroundStyle(reminderDueColor)
                .lineLimit(1)
        }
    }
}

/// ウィジェットの行の「カートイン」のボタン。押すとアプリを開かずに確認の通知を出す (`CartInIntent`)。
///
/// 通知が許可されていない時と、購入画面の URL を組み立てられないお気に入り (Amazon の商品。開き方が決まるまで) では出さない。
struct FavoriteWidgetCartInButton: View {
    /// ボタンが指すお気に入り。
    let favorite: Favorite
    /// 通知が許可されているか。
    let isNotificationAuthorized: Bool

    /// 強調の色の地に白い文字の「カートイン」。
    var body: some View {
        if isCartInButtonShown(favorite: favorite, isNotificationAuthorized: isNotificationAuthorized) {
            Button(intent: CartInIntent(favoriteID: favorite.id)) {
                Text("カートイン")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 通知が許可されていない時に出す、「カートイン」には通知の許可が要ることの 1 行。
struct FavoritesWidgetNotificationRequiredText: View {
    /// 補足の色の小さい文字の 1 行。
    var body: some View {
        Text("カートインには通知の許可が要ります")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

/// ウィジェットの行の左に出す買い物袋のアイコン。
struct FavoriteWidgetIcon: View {
    /// アイコンの枠の 1 辺の長さ。
    let sideLength: CGFloat

    /// 強調の色の薄い地に買い物袋。
    var body: some View {
        Image(systemName: "bag")
            .font(.system(size: sideLength / 2))
            .foregroundStyle(quickBuyAccentColor)
            .frame(width: sideLength, height: sideLength)
            .background(quickBuyAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// ウィジェットに並べるお気に入りが無い時の案内。アイコン・見出し・説明を縦に並べる。
struct FavoritesWidgetMessage: View {
    /// 上に出すアイコンの SF Symbols の名前。
    let systemImageName: String
    /// 見出し。
    let title: String
    /// 見出しの下の説明。無ければ nil。
    let description: String?

    /// アイコン・見出し・説明。
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImageName)
                .font(.title2)
                .foregroundStyle(quickBuyAccentColor)
            Text(title)
                .font(.caption.bold())
            if let description {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}
