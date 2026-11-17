import SwiftUI
import WidgetKit

/// ホーム画面に置く、お気に入りを保存した並びで出すウィジェット。お気に入りをタップすると、アプリを通ってその商品の店の購入画面が開く。
struct FavoritesWidget: Widget {
    /// ウィジェットの構成 (種類の識別子・表示名・対応するサイズ)。
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: favoritesWidgetKind, provider: FavoritesTimelineProvider()) { favoritesTimelineEntry in
            FavoritesWidgetView(favorites: favoritesTimelineEntry.favorites)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("お気に入り")
        .description("いつもの商品をホーム画面から買い直す")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// ウィジェットの 1 回分の表示内容。
struct FavoritesTimelineEntry: TimelineEntry {
    /// この内容を表示し始める時刻。
    let date: Date
    /// 保存済みのお気に入りの並び。保存先を読めなかった時は nil。
    let favorites: [Favorite]?
}

/// ウィジェットに表示内容を渡す。保存済みのお気に入りの今の並びを 1 件だけ返し、時刻での更新を予約しない (表示が変わるのは `saveFavorites(favorites:fileURL:)` が更新を頼んだ時)。
struct FavoritesTimelineProvider: TimelineProvider {
    /// 読み込み中に出す仮の表示内容を返す。お気に入りが無い時の表示を仮の表示にする。
    func placeholder(in _: Context) -> FavoritesTimelineEntry {
        FavoritesTimelineEntry(date: .now, favorites: [])
    }

    /// ウィジェットの一覧などに出す表示内容を completion に渡す。
    func getSnapshot(in _: Context, completion: @escaping (FavoritesTimelineEntry) -> Void) {
        completion(savedFavoritesTimelineEntry())
    }

    /// 表示内容の並びを completion に渡す。
    func getTimeline(in _: Context, completion: @escaping (Timeline<FavoritesTimelineEntry>) -> Void) {
        completion(Timeline(entries: [savedFavoritesTimelineEntry()], policy: .never))
    }

    /// 保存先から今のお気に入りを読んだ表示内容を返す。保存先を得られない・読めない時は、お気に入りを nil にする。
    private func savedFavoritesTimelineEntry() -> FavoritesTimelineEntry {
        FavoritesTimelineEntry(date: .now, favorites: sharedFavoritesFileURL().flatMap { try? loadFavorites(fileURL: $0) })
    }
}

/// ウィジェットの見た目。お気に入りを大きさに入る数だけ並べる。お気に入りが無い時は登録を促し、保存先を読めなかった時はその旨を出す。
struct FavoritesWidgetView: View {
    /// 保存済みのお気に入りの並び。保存先を読めなかった時は nil。
    let favorites: [Favorite]?

    /// ウィジェットの大きさ。
    @Environment(\.widgetFamily) private var widgetFamily

    /// 大きさと、お気に入りの有無ごとの表示。
    var body: some View {
        if let favorites {
            if favorites.isEmpty {
                FavoritesWidgetMessage(
                    systemImageName: "cart",
                    title: "お気に入りはまだありません",
                    description: "アプリで商品を登録すると\nここに並びます"
                )
            } else if widgetFamily == .systemSmall {
                ForEach(widgetFavorites(favorites: favorites, widgetFamily: widgetFamily)) { favorite in
                    FavoriteWidgetTile(favorite: favorite, iconSideLength: 52, nameFont: .subheadline.bold()) {
                        Text("タップで購入画面")
                            .font(.footnote.bold())
                            .foregroundStyle(quickBuyAccentColor)
                    }
                    .widgetURL(favoriteTapURL(favoriteID: favorite.id))
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(widgetFavorites(favorites: favorites, widgetFamily: widgetFamily)) { favorite in
                        Link(destination: favoriteTapURL(favoriteID: favorite.id)) {
                            FavoriteWidgetTile(favorite: favorite, iconSideLength: 44, nameFont: .footnote.bold()) {
                                Text("\(favorite.quantity) 個")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    // お気に入りが上限より少ない時も、1 件の幅を上限の数で割った幅のままにする。
                    ForEach(
                        min(favorites.count, favoritesWidgetCapacity(widgetFamily: widgetFamily)) ..< favoritesWidgetCapacity(widgetFamily: widgetFamily),
                        id: \.self
                    ) { _ in
                        Color.clear
                    }
                }
            }
        } else {
            FavoritesWidgetMessage(systemImageName: "exclamationmark.triangle", title: "お気に入りを読み込めません", description: nil)
        }
    }
}

/// ウィジェットのお気に入り 1 件の表示。買い物袋のアイコン・名前・その下の 1 行を、左上から縦に並べる。
struct FavoriteWidgetTile<Caption: View>: View {
    /// 表示するお気に入り。
    let favorite: Favorite
    /// アイコンの枠の 1 辺の長さ。
    let iconSideLength: CGFloat
    /// 名前の文字の大きさと太さ。
    let nameFont: Font
    /// 名前の下に出す 1 行 (個数や、タップで何が起きるかの案内)。
    @ViewBuilder let caption: Caption

    /// 上にアイコン、下に名前とその下の 1 行。
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "bag")
                .font(.system(size: iconSideLength / 2))
                .foregroundStyle(quickBuyAccentColor)
                .frame(width: iconSideLength, height: iconSideLength)
                .background(quickBuyAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 0)
            Text(favorite.name)
                .font(nameFont)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
            caption
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
