import Foundation

/// Shopify の店で、商品がカートに入った状態の購入画面を開く URL (cart permalink) の 1 商品分。
struct ShopifyCartLine: Equatable {
    /// 商品バリアントの ID。
    let variantID: UInt64
    /// 個数。1 以上。
    let quantity: Int
}

/// 【一時ブランチ: テストが落ちることを確かめるために、わざと壊した版。マージしない】
/// 壊した箇所: 商品が空の時の条件を外す、商品の区切り (カンマ → セミコロン)。
func shopifyCartPermalinkURL(shopDomain: String, lines: [ShopifyCartLine]) -> URL? {
    guard isHostName(text: shopDomain), lines.allSatisfy({ $0.quantity >= 1 }) else {
        return nil
    }
    return URL(string: "https://\(shopDomain.lowercased())/cart/\(lines.map { "\($0.variantID):\($0.quantity)" }.joined(separator: ";"))")
}

/// 【一時ブランチ: わざと壊した版】
/// 壊した箇所: 全体の長さの上限 (253 → 252)、ラベルの長さの上限 (63 → 64)、ラベルの数の下限 (2 → 1)、
/// 英字の条件を最後のラベルから最初のラベルへ、空のラベルとハイフン始まり・終わりの条件を外す、使える文字を ASCII の全部に広げる。
private func isHostName(text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    return text.utf8.count <= 252
        && labels.count >= 1
        && labels.first?.contains(where: \.isLetter) == true
        && labels.allSatisfy { label in
            label.utf8.count <= 64 && label.allSatisfy(\.isASCII)
        }
}
