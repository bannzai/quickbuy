import SwiftUI
import WidgetKit

/// ホーム画面に置くウィジェットの雛形。お気に入りの表示とタップの処理は必要な機能の実装で置き換える。
struct FavoritesWidget: Widget {
    /// ウィジェットの構成 (種類の識別子・表示名・対応するサイズ)。
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FavoritesWidget", provider: FavoritesTimelineProvider()) { _ in
            FavoritesWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("お気に入り")
        .description("いつもの商品をホーム画面から買い直す")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// ウィジェットの 1 回分の表示内容。雛形では表示する時刻だけを持つ。
struct FavoritesTimelineEntry: TimelineEntry {
    /// この内容を表示し始める時刻。
    let date: Date
}

/// ウィジェットに表示内容を渡す。雛形では現在時刻の 1 件だけを返し、更新を予約しない。
struct FavoritesTimelineProvider: TimelineProvider {
    /// 読み込み中に出す仮の表示内容を返す。
    func placeholder(in _: Context) -> FavoritesTimelineEntry {
        FavoritesTimelineEntry(date: .now)
    }

    /// ウィジェットの一覧などに出す見本の表示内容を completion に渡す。
    func getSnapshot(in _: Context, completion: @escaping (FavoritesTimelineEntry) -> Void) {
        completion(FavoritesTimelineEntry(date: .now))
    }

    /// 表示内容の並びを completion に渡す。
    func getTimeline(in _: Context, completion: @escaping (Timeline<FavoritesTimelineEntry>) -> Void) {
        completion(Timeline(entries: [FavoritesTimelineEntry(date: .now)], policy: .never))
    }
}

/// お気に入りが無い状態のウィジェットの見た目。
struct FavoritesWidgetView: View {
    /// カートのアイコンと案内の文言。
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart")
                .font(.title2)
            Text("お気に入りはまだありません")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}
