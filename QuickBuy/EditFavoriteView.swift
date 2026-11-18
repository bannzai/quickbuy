import SwiftUI

/// お気に入りの編集の画面。名前と個数を変えて保存する、またはお気に入りから外す。
struct EditFavoriteView: View {
    /// 編集中のお気に入り。開く時に保存済みの値を渡す。「保存」を押すまで保存先には書かない。
    @State var favorite: Favorite
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL
    /// この画面を閉じる処理。保存・削除の後と、戻る時に呼ぶ。
    let onFinish: () -> Void

    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false

    /// 店のドメイン・名前と個数の入力・お気に入りから外すボタン。
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
                    QuantityStepperRow(quantity: $favorite.quantity)
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
                            try updateFavorite(id: favorite.id, name: favorite.name, quantity: favorite.quantity, fileURL: favoritesFileURL)
                        }
                    }
                    .disabled(!isFavoriteNameSavable(name: favorite.name))
                }
            }
            .alert("保存できませんでした", isPresented: $isSaveFailed) {}
        }
        .tint(quickBuyAccentColor)
    }

    /// 保存の操作を実行し、成功したら画面を閉じる。失敗した時は画面を閉じずにその旨を知らせる。
    private func finish(operation: () throws -> Void) {
        do {
            try operation()
            onFinish()
        } catch {
            isSaveFailed = true
        }
    }
}
