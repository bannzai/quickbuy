import SwiftUI

/// 雛形の最初の画面。お気に入りの一覧は必要な機能の実装で置き換える。
struct ContentView: View {
    /// お気に入りが無い状態の表示。
    var body: some View {
        ContentUnavailableView(
            "お気に入りはまだありません",
            systemImage: "cart",
            description: Text("お気に入りにした商品がここに並びます")
        )
    }
}

#Preview {
    ContentView()
}
