import Foundation
import WidgetKit

/// ウィジェットの大きさごとの、表示するお気に入りの数の上限を返す。
///
/// 小サイズは 1 件、中サイズは 3 件 (画面の見本 documents/design/mock-2026-11-17/project/Widget.dc.html の並べ方)。
/// ウィジェットが対応していない大きさ (`FavoritesWidget` の `supportedFamilies` に無いもの) は、並べ方を決めていないため 0 を返す。
func favoritesWidgetCapacity(widgetFamily: WidgetFamily) -> Int {
    switch widgetFamily {
    case .systemSmall:
        1
    case .systemMedium:
        3
    default:
        0
    }
}

/// 保存済みのお気に入りの並びから、ウィジェットに表示するものを返す。並びの先頭から、その大きさの上限までを保存した並びのまま返す。
func widgetFavorites(favorites: [Favorite], widgetFamily: WidgetFamily) -> [Favorite] {
    Array(favorites.prefix(favoritesWidgetCapacity(widgetFamily: widgetFamily)))
}

/// ウィジェットのお気に入りをタップした時に、アプリへ渡す URL を返す。形は `quickbuy://favorite/{お気に入りの識別子}`。
///
/// 載せるのはお気に入りの識別子だけで、店のドメイン・商品・個数は載せない。
/// 購入画面の URL は、アプリが保存済みのお気に入りから組み立てる (documents/adr/0003)。
func favoriteTapURL(favoriteID: UUID) -> URL {
    // UUID の文字列は英数字とハイフンだけなので、URL として解釈できない値にはならない。
    URL(string: "quickbuy://favorite/\(favoriteID.uuidString)")!
}

/// アプリに渡された URL が `favoriteTapURL(favoriteID:)` の形の時に、そのお気に入りの識別子を返す。
///
/// 同関数が組み立てる URL と 1 文字でも違うもの (別のスキーム・別のホスト・余分なパスやクエリ・識別子の形でない値) では nil を返す。
func tappedFavoriteID(tapURL: URL) -> UUID? {
    UUID(uuidString: tapURL.lastPathComponent).flatMap { favoriteTapURL(favoriteID: $0) == tapURL ? $0 : nil }
}
