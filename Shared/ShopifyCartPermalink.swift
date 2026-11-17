import Foundation

/// Shopify の店で、商品がカートに入った状態の購入画面を開く URL (cart permalink) の 1 商品分。
struct ShopifyCartLine: Equatable {
    /// 商品バリアントの ID。
    let variantID: UInt64
    /// 個数。1 以上。
    let quantity: Int
}

/// 店のドメインと商品の一覧から、Shopify の cart permalink を組み立てて返す。
///
/// URL の形式の出典: https://shopify.dev/docs/apps/build/checkout/create-cart-permalinks
/// 外から渡された URL をそのまま開かず、決まった形だけを組み立てる (URL に入るのは店のドメイン・商品バリアントの ID・個数だけ)。
/// 店のドメインがホスト名の形でない時、商品が空の時、個数が 1 未満の商品がある時は nil を返す。
func shopifyCartPermalinkURL(shopDomain: String, lines: [ShopifyCartLine]) -> URL? {
    guard isHostName(text: shopDomain), !lines.isEmpty, lines.allSatisfy({ $0.quantity >= 1 }) else {
        return nil
    }
    return URL(string: "https://\(shopDomain.lowercased())/cart/\(lines.map { "\($0.variantID):\($0.quantity)" }.joined(separator: ","))")
}

/// 英数字とハイフンのラベルをドットで 2 つ以上つないだホスト名なら true を返す (スキーム・パス・ポート・認証情報を含む文字列は false)。
private func isHostName(text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    return labels.count >= 2 && labels.allSatisfy { label in
        !label.isEmpty
            && !label.hasPrefix("-")
            && !label.hasSuffix("-")
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
