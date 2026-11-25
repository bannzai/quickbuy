import Foundation
import WidgetKit

/// お気に入りを並べるウィジェット (`QuickBuyWidget/FavoritesWidget.swift`) の種類の識別子。
let favoritesWidgetKind = "FavoritesWidget"

/// アプリとウィジェット拡張が共有する領域 (App Group) の識別子。
/// `QuickBuy/QuickBuy.entitlements` と `QuickBuyWidget/QuickBuyWidget.entitlements` の `com.apple.security.application-groups` と同じ値にする (documents/adr/0001)。
let favoritesAppGroupIdentifier = "group.com.bannzai.QuickBuy"

/// お気に入りの保存の操作が、保存せずに終わった理由。
enum FavoriteStoreError: Error, Equatable {
    /// 個数が 1 未満のお気に入りがある。
    case quantityLessThanOne
    /// リマインドの日数が 1 未満のお気に入りがある。
    case reminderIntervalDaysLessThanOne
    /// 指定した識別子のお気に入りが保存されていない。
    case favoriteNotFound
    /// 並べ替えの移動先が、保存されているお気に入りの並びの範囲に無い。
    case destinationIndexOutOfRange
}

/// アプリとウィジェット拡張が共有する領域にある、お気に入りの保存先のファイルの URL を返す。
///
/// 保存するのは `[Favorite]` を JSON にしたファイル 1 つ。
/// 実行しているターゲットに App Group の設定が無く、共有する領域を得られない時は nil を返す。
func sharedFavoritesFileURL() -> URL? {
    FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: favoritesAppGroupIdentifier)?
        .appending(path: "favorites.json")
}

/// 保存先のファイルからお気に入りを、保存した並びのまま読んで返す。
///
/// ファイルがまだ無い時 (1 件も保存していない時) は空の配列を返す。
/// ファイルがあるのに読めない・`[Favorite]` として解釈できない時は、空の配列にせずエラーを投げる (保存済みのお気に入りを、次の保存で黙って上書きしないため)。
func loadFavorites(fileURL: URL) throws -> [Favorite] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return []
    }
    return try JSONDecoder().decode([Favorite].self, from: Data(contentsOf: fileURL))
}

/// お気に入りの並びを、保存先のファイルの中身と置き換える。配列の並びが一覧とウィジェットの並び順になる。
///
/// 個数が 1 未満、またはリマインドの日数が 1 未満のお気に入りが 1 つでもあれば、何も書かずにエラーを投げる。
/// 書き込みは一時ファイルを経て置き換えるため、ウィジェット拡張が書きかけのファイルを読むことは無い。
/// 書いた後に、お気に入りを並べるウィジェットの表示の更新を OS に頼む (追加・変更・並べ替え・削除はすべてこの関数を通る)。
func saveFavorites(favorites: [Favorite], fileURL: URL) throws {
    guard favorites.allSatisfy({ $0.quantity >= 1 }) else {
        throw FavoriteStoreError.quantityLessThanOne
    }
    guard favorites.allSatisfy({ $0.reminder.map { $0.intervalDays >= 1 } != false }) else {
        throw FavoriteStoreError.reminderIntervalDaysLessThanOne
    }
    try JSONEncoder().encode(favorites).write(to: fileURL, options: .atomic)
    WidgetCenter.shared.reloadTimelines(ofKind: favoritesWidgetKind)
}

/// お気に入りを並びの末尾に足して保存する。
///
/// 同じ識別子のお気に入りが保存済みの時は何も変えない (同じ追加を 2 回呼んでも 1 件のまま)。
/// 同じ店・同じ種類のお気に入りが保存済みでも、識別子が違えば別の行として足し、保存済みの行は変えない
/// (開発者メニューの見本の出し入れが、利用者が入れた行の個数を書き換えないため)。
func addFavorite(favorite: Favorite, fileURL: URL) throws {
    try addFavorites(favorites: [favorite], updatesSavedQuantity: false, fileURL: fileURL)
}

/// お気に入りの並び `favorites` のうち、Shopify の店の商品 `shopifyProduct` と同じ店・同じ種類 (店のドメインと商品バリアントの ID が同じ) の最初の 1 件を返す。無ければ nil。
///
/// 追加の画面が、選んでいる種類が保存済みかを見分けるのに使う。Amazon の商品のお気に入りは返さない。
func shopifyFavorite(favorites: [Favorite], shopifyProduct: ShopifyProduct) -> Favorite? {
    favorites.first { $0.product == .shopify(shopifyProduct) }
}

/// 複数のお気に入りを、渡された並びのまま、保存済みの並びの末尾に足して保存する。`updatesSavedQuantity` が true の時は、同じ店・同じ種類のお気に入りが保存済みのものを、足さずにその個数の書き換えにする。
///
/// 書き込みは 1 回で、全部が保存されるか 1 件も保存されないかのどちらかになる。
/// 渡された並びに個数が 1 未満のお気に入りが 1 つでもあれば (保存済みと同じ識別子のものでも)、どれも保存せずにエラーを投げる。
/// 同じ識別子のお気に入りが保存済みのものは足さず、書き換えもしない (同じ追加を 2 回呼んでも結果は変わらない)。
/// 渡された並びの中に同じ識別子のお気に入りが複数ある時は、最初の 1 件だけを使う (保存する並びに同じ識別子を 2 つ置かず、個数の書き換えも最初の 1 件の個数で行う)。
/// `updatesSavedQuantity` が true (追加の画面からの保存) の時、識別子は違うが、Shopify の店の同じ店・同じ種類 (`shopifyFavorite(favorites:shopifyProduct:)`) のお気に入りが並びにある時は、行を増やさず、その最初の 1 件の個数だけを渡された個数にする
/// (名前・種類の名前・画像・リマインド・並びの位置は変えない。同じ商品の行を 2 つ作らないため。https://github.com/bannzai/quickbuy/issues/84 )。
/// Amazon の商品は、同じ ASIN が保存済みでも足す (個数を持たず、書き換える値が無いため今までどおり)。
/// `updatesSavedQuantity` が false の時は、同じ店・同じ種類が保存済みでも別の行として足す (`addFavorite(favorite:fileURL:)`)。
/// 保存済みの並びと変わらない時は何も書かない。
func addFavorites(favorites addedFavorites: [Favorite], updatesSavedQuantity: Bool, fileURL: URL) throws {
    guard addedFavorites.allSatisfy({ $0.quantity >= 1 }) else {
        throw FavoriteStoreError.quantityLessThanOne
    }
    let savedFavorites = try loadFavorites(fileURL: fileURL)
    let mergedFavorites = addedFavorites.enumerated().reduce(into: savedFavorites) { mergedFavorites, enumeratedFavorite in
        let (addedIndex, addedFavorite) = enumeratedFavorite
        // 個数の書き換えに使ったお気に入りの識別子は並びに残らないので、渡された並びの前の方に同じ識別子があるかも見る (最初の 1 件だけを使う)。
        guard !mergedFavorites.contains(where: { $0.id == addedFavorite.id }),
              !addedFavorites[..<addedIndex].contains(where: { $0.id == addedFavorite.id })
        else {
            return
        }
        if updatesSavedQuantity,
           case .shopify = addedFavorite.product,
           let sameProductIndex = mergedFavorites.firstIndex(where: { $0.product == addedFavorite.product })
        {
            mergedFavorites[sameProductIndex].quantity = addedFavorite.quantity
        } else {
            mergedFavorites.append(addedFavorite)
        }
    }
    guard mergedFavorites != savedFavorites else {
        return
    }
    try saveFavorites(favorites: mergedFavorites, fileURL: fileURL)
}

/// 指定した識別子のお気に入りの名前と個数を書き換えて保存する。並びとほかの値は変えない。
///
/// その識別子のお気に入りが無い時は `FavoriteStoreError.favoriteNotFound` を投げる。
func updateFavorite(id: UUID, name: String, quantity: Int, fileURL: URL) throws {
    var favorites = try loadFavorites(fileURL: fileURL)
    guard let favoriteIndex = favorites.firstIndex(where: { $0.id == id }) else {
        throw FavoriteStoreError.favoriteNotFound
    }
    favorites[favoriteIndex].name = name
    favorites[favoriteIndex].quantity = quantity
    try saveFavorites(favorites: favorites, fileURL: fileURL)
}

/// 指定した識別子のお気に入りのリマインドを書き換えて保存する。並びとほかの値は変えない。
///
/// `reminder` が保存済みのリマインドと同じ時は何も変えない (日数を数え始めた日時も変えない)。nil の時はリマインドをやめる。
/// 保存済みと違う時は、日数を `reminder.intervalDays`、日数を数え始めた日時を `now` にして保存する。
/// 通知は保存した時刻から日数ごとに予約するため、渡された `countedFrom` ではなく保存の時刻から数え始める。
/// その識別子のお気に入りが無い時は `FavoriteStoreError.favoriteNotFound` を投げる。
func setFavoriteReminder(id: UUID, reminder: Reminder?, now: Date, fileURL: URL) throws {
    var favorites = try loadFavorites(fileURL: fileURL)
    guard let favoriteIndex = favorites.firstIndex(where: { $0.id == id }) else {
        throw FavoriteStoreError.favoriteNotFound
    }
    guard favorites[favoriteIndex].reminder != reminder else {
        return
    }
    favorites[favoriteIndex].reminder = reminder.map { Reminder(intervalDays: $0.intervalDays, countedFrom: now) }
    try saveFavorites(favorites: favorites, fileURL: fileURL)
}

/// 指定した識別子のお気に入りのリマインドの、日数を数え始めた日時を `now` に書き換えて保存する (購入画面を開いた時の数え直し)。
///
/// リマインドを設定していないお気に入りでは何も変えない。
/// その識別子のお気に入りが無い時は `FavoriteStoreError.favoriteNotFound` を投げる。
func recountFavoriteReminder(id: UUID, now: Date, fileURL: URL) throws {
    var favorites = try loadFavorites(fileURL: fileURL)
    guard let favoriteIndex = favorites.firstIndex(where: { $0.id == id }) else {
        throw FavoriteStoreError.favoriteNotFound
    }
    guard favorites[favoriteIndex].reminder != nil else {
        return
    }
    favorites[favoriteIndex].reminder?.countedFrom = now
    try saveFavorites(favorites: favorites, fileURL: fileURL)
}

/// 指定した識別子のお気に入りを、並びの `destinationIndex` 番目 (0 始まり。移動した後の位置) へ移して保存する。
///
/// 移動した後の位置で指定するため、同じ呼び出しを繰り返しても並びは変わらない。
/// その識別子のお気に入りが無い時は `FavoriteStoreError.favoriteNotFound`、
/// `destinationIndex` が並びの範囲に無い時は `FavoriteStoreError.destinationIndexOutOfRange` を投げる。
func moveFavorite(id: UUID, destinationIndex: Int, fileURL: URL) throws {
    var favorites = try loadFavorites(fileURL: fileURL)
    guard let favoriteIndex = favorites.firstIndex(where: { $0.id == id }) else {
        throw FavoriteStoreError.favoriteNotFound
    }
    guard favorites.indices.contains(destinationIndex) else {
        throw FavoriteStoreError.destinationIndexOutOfRange
    }
    favorites.insert(favorites.remove(at: favoriteIndex), at: destinationIndex)
    try saveFavorites(favorites: favorites, fileURL: fileURL)
}

/// 指定した識別子のお気に入りを並びから除いて保存する。
///
/// その識別子のお気に入りが無い時は、残りの並びを変えずに終わる (同じ削除を 2 回呼んでも結果は同じ)。
func deleteFavorite(id: UUID, fileURL: URL) throws {
    try saveFavorites(favorites: loadFavorites(fileURL: fileURL).filter { $0.id != id }, fileURL: fileURL)
}
