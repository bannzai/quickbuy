import Foundation

/// Shopify の店で、商品がカートに入った状態の購入画面を開く URL (cart permalink) の 1 商品分。
struct ShopifyCartLine: Equatable {
    /// 商品バリアントの ID。
    let variantID: UInt64
    /// 個数。1 以上。
    let quantity: Int
}

/// 店のドメインと商品の一覧から、Shopify の cart permalink を組み立てて返す (この関数は壊していない)。
func shopifyCartPermalinkURL(shopDomain: String, lines: [ShopifyCartLine]) -> URL? {
    guard isHostName(text: shopDomain), !lines.isEmpty, lines.allSatisfy({ $0.quantity >= 1 }) else {
        return nil
    }
    return URL(string: "https://\(shopDomain.lowercased())/cart/\(lines.map { "\($0.variantID):\($0.quantity)" }.joined(separator: ","))")
}

/// 【一時ブランチ: テストが落ちることを確かめるために、わざと壊した版。マージしない】
/// 壊した箇所: 全体の長さの上限だけ (253 → 254)。1 回目の版はラベルの上限も同時に壊していて、全体が 254 文字のケースが落ちるかを確かめられなかったため。
private func isHostName(text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    return text.utf8.count <= 254
        && labels.count >= 2
        && labels.last?.contains(where: \.isLetter) == true
        && labels.allSatisfy { label in
            !label.isEmpty
                && label.utf8.count <= 63
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
}
