import Foundation

/// Shopify の店で、商品がカートに入った状態の購入画面を開く URL (cart permalink) の 1 商品分。
struct ShopifyCartLine: Equatable {
    /// 商品バリアントの ID。
    let variantID: UInt64
    /// 個数。1 以上。
    let quantity: Int
}

/// 【一時ブランチ: テストが落ちることを確かめるために、わざと壊した版。マージしない】
/// 壊した箇所: 個数の下限 (1 → 0)、小文字化を外す、商品バリアントの ID を 32 bit に切り詰める。
func shopifyCartPermalinkURL(shopDomain: String, lines: [ShopifyCartLine]) -> URL? {
    guard isHostName(text: shopDomain), !lines.isEmpty, lines.allSatisfy({ $0.quantity >= 0 }) else {
        return nil
    }
    return URL(string: "https://\(shopDomain)/cart/\(lines.map { "\(UInt32(truncatingIfNeeded: $0.variantID)):\($0.quantity)" }.joined(separator: ","))")
}

/// 【一時ブランチ: わざと壊した版】
/// 壊した箇所: 全体の長さの上限 (253 → 254)、ラベルの長さの上限 (63 → 62)、最後のラベルの英字の条件を外す、ASCII の条件を外す。
private func isHostName(text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    return text.utf8.count <= 254
        && labels.count >= 2
        && labels.allSatisfy { label in
            !label.isEmpty
                && label.utf8.count <= 62
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
}
