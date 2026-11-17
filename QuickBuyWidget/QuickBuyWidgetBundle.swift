import SwiftUI
import WidgetKit

/// Quick Buy のウィジェット拡張の入口。
@main
struct QuickBuyWidgetBundle: WidgetBundle {
    /// この拡張が提供するウィジェットの一覧。
    var body: some Widget {
        FavoritesWidget()
    }
}
