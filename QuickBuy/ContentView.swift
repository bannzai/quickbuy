import SwiftUI

/// アプリの最初の画面。お気に入りの保存先を開ければ一覧を、開けなければその旨を表示する。
struct ContentView: View {
    /// お気に入りの一覧、または保存先を開けないことの表示。
    var body: some View {
        if let favoritesFileURL = sharedFavoritesFileURL() {
            FavoritesListView(favoritesFileURL: favoritesFileURL)
        } else {
            FavoritesStoreUnavailableView()
        }
    }
}

/// お気に入りの一覧の画面。保存した並びで表示し、「買う」で店の購入画面を開く。追加・名前と個数の変更・並べ替え・削除・設定画面の入口を持つ。
struct FavoritesListView: View {
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL

    /// 店の購入画面を開く処理 (既定のブラウザで開く)。
    @Environment(\.openURL) private var openURL
    /// アプリが前面にあるか。共有メニューの拡張で足したお気に入りを、アプリへ戻った時に読み直すために見る。
    @Environment(\.scenePhase) private var scenePhase
    /// 表示しているお気に入りの並び (保存先から読んだもの)。
    @State private var favorites: [Favorite] = []
    /// 保存先のファイルを読めなかった時は true。
    @State private var isLoadFailed = false
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false
    /// 編集の画面で開いているお気に入り (開いた時点の保存済みの値)。開いていない時は nil。
    @State private var editingFavorite: Favorite?
    /// お気に入りの追加の画面を出している間は true。
    @State private var isAddingFavorite = false
    /// 設定画面を出している間は true。
    @State private var isSettingsPresented = false

    /// 一覧と、追加・編集・設定の画面への入口。
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("お気に入り")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingFavorite = true
                        } label: {
                            Label("お気に入りを追加", systemImage: "plus")
                        }
                    }
                }
        }
        .tint(quickBuyAccentColor)
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                reload()
            }
        }
        .sheet(item: $editingFavorite, onDismiss: reload) { favorite in
            EditFavoriteView(favorite: favorite, favoritesFileURL: favoritesFileURL) {
                editingFavorite = nil
            }
        }
        .sheet(isPresented: $isAddingFavorite, onDismiss: reload) {
            AddFavoriteView(initialText: "", favoritesFileURL: favoritesFileURL) {
                isAddingFavorite = false
            }
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: reload) {
            SettingsView(favoritesFileURL: favoritesFileURL) {
                isSettingsPresented = false
            }
        }
        .alert("保存できませんでした", isPresented: $isSaveFailed) {}
    }

    /// お気に入りの並び。読めなかった時と 1 件も無い時は、その旨の表示。
    @ViewBuilder private var content: some View {
        if isLoadFailed {
            ContentUnavailableView("お気に入りを読み込めません", systemImage: "exclamationmark.triangle")
        } else if favorites.isEmpty {
            ContentUnavailableView(
                "お気に入りはまだありません",
                systemImage: "cart",
                description: Text("右上の + から商品ページの URL を入れると\nここに並びます")
            )
        } else {
            List {
                Section {
                    ForEach(favorites) { favorite in
                        row(favorite: favorite)
                    }
                    .onMove { sourceIndexes, destinationOffset in
                        // 一覧のドラッグで動かせるのは 1 行ずつなので、渡される位置は 1 つ。
                        guard let sourceIndex = sourceIndexes.first else {
                            return
                        }
                        save {
                            try moveFavorite(
                                id: favorites[sourceIndex].id,
                                destinationIndex: destinationIndexAfterMove(sourceIndex: sourceIndex, destinationOffset: destinationOffset),
                                fileURL: favoritesFileURL
                            )
                        }
                    }
                    .onDelete { deletedIndexes in
                        save {
                            for deletedFavoriteID in deletedIndexes.map({ favorites[$0].id }) {
                                try deleteFavorite(id: deletedFavoriteID, fileURL: favoritesFileURL)
                            }
                        }
                    }
                } footer: {
                    Text("「買う」を押すと店の購入画面が開きます\n支払いの確定は店の画面で行います")
                }
            }
        }
    }

    /// お気に入り 1 件の行。名前の側を押すと編集の画面、「買う」を押すと店の購入画面が開く。
    private func row(favorite: Favorite) -> some View {
        HStack(spacing: 12) {
            Button {
                editingFavorite = favorite
            } label: {
                HStack(spacing: 12) {
                    FavoriteThumbnail(imageURL: favorite.imageURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(favorite.name)
                            .font(.headline)
                        Text(shopDomainText(favorite: favorite))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(favorite.quantity) 個")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let favoritePurchaseURL = purchaseURL(favorite: favorite) {
                Button("買う") {
                    openURL(favoritePurchaseURL)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// 保存先からお気に入りを読み直して表示に反映する。
    private func reload() {
        do {
            favorites = try loadFavorites(fileURL: favoritesFileURL)
            isLoadFailed = false
        } catch {
            isLoadFailed = true
        }
    }

    /// 保存の操作を実行し、失敗した時はその旨を知らせる。成否にかかわらず、保存先の今の並びを表示に反映する。
    private func save(operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            isSaveFailed = true
        }
        reload()
    }
}

/// 一覧の並べ替え (`onMove`) が渡す移動先を、`moveFavorite(id:destinationIndex:fileURL:)` の `destinationIndex` (移動した後の位置) に直して返す。
///
/// `onMove` の移動先は、移動する前の並びで「この位置の要素の前に差し込む」を表す (末尾の後ろは件数と同じ値)。
/// 元の位置より後ろへ移す時は、移すお気に入り自身が抜ける分だけ 1 つ前にずれる。
func destinationIndexAfterMove(sourceIndex: Int, destinationOffset: Int) -> Int {
    destinationOffset > sourceIndex ? destinationOffset - 1 : destinationOffset
}

#Preview {
    ContentView()
}
