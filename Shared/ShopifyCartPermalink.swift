import Foundation

/// Shopify の店で、商品がカートに入った状態の購入画面を開く URL (cart permalink) の 1 商品分。
struct ShopifyCartLine: Equatable {
    /// 商品バリアントの ID。
    let variantID: UInt64
    /// 個数。1 以上。
    let quantity: Int
}

/// 【一時ブランチ: テストが落ちることを確かめるために、わざと壊した版。マージしない】
/// 壊した箇所: 店のドメインの検査と個数の検査をどちらも外す (1 回目の版で落ちなかった、空文字・空白・改行を含む店のドメインと、個数 -1 のケースを確かめるため)。
func shopifyCartPermalinkURL(shopDomain: String, lines: [ShopifyCartLine]) -> URL? {
    guard !lines.isEmpty else {
        return nil
    }
    return URL(string: "https://\(shopDomain.lowercased())/cart/\(lines.map { "\($0.variantID):\($0.quantity)" }.joined(separator: ","))")
}
