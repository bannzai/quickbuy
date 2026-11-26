import Foundation

/// 店のドメイン・商品バリアントの ID・個数から、Shopify の店のカートにその商品を個数分足して購入画面 (店の `/cart`) を開く URL `https://{店のドメイン}/cart/add?id={商品バリアントの ID}&quantity={個数}` を組み立てて返す。
///
/// 開くたびに、利用者のブラウザに残っているその店のカートへ足す (前に足した物は残り、同じ商品バリアントは個数が増える)。
/// URL の形式の出典: GET の `/cart/add` を説明する公式の文書は見つからなかった (2026-11-26 の検索)。近い公式の文書は Ajax の Cart API の `/cart/add` (https://shopify.dev/docs/api/ajax/reference/cart)、
/// リンクとしての使い方は Shopify のコミュニティの回答 (https://community.shopify.com/t/how-to-create-a-direct-link-to-a-preloaded-cart-page/1665)。
/// 実際に開いて確かめた結果 (2026-11-26、GitHub Actions の Linux Runner の Chromium、https://github.com/bannzai/quickbuy/issues/86 ):
/// chimney-coffee.com で `/cart/add?id=45476745412786&quantity=1`、続けて `/cart/add?id=45476749770930&quantity=2` を開くと、どちらも `https://chimney-coffee.com/cart` に移り、
/// `/cart.js` の `items` に 2 つの商品バリアント (個数 1 と 2、`item_count` 3) が入っていた。続けて 1 つ目をもう一度開くと、行は増えずにその個数が 2 になった (`item_count` 4)。
/// 同じ店の myshopify.com のドメイン (shibuyachimneycoffee.myshopify.com) で開いた時も chimney-coffee.com のカートに移り、前の物が残ったまま足された。
/// 外から渡された URL をそのまま開かず、決まった形だけを組み立てる (URL に入るのは店のドメイン・商品バリアントの ID・個数だけ)。
/// 店のドメインは形だけを検査し、どの店かは見ない。渡してよいのは、お気に入りの登録の画面で利用者が確かめて保存したドメインだけ (documents/adr/0003)。
/// 店のドメインがホスト名の形でない時、個数が 1 未満の時、商品バリアントの ID が ASCII の数字だけでない (空文字を含む) 時は nil を返す。
func shopifyCartAddURL(shopDomain: String, variantID: String, quantity: Int) -> URL? {
    guard isHostName(text: shopDomain), quantity >= 1, isASCIIDigits(text: variantID) else {
        return nil
    }
    return URL(string: "https://\(shopDomain.lowercased())/cart/add?id=\(variantID)&quantity=\(quantity)")
}

/// 1 文字以上で、ASCII の数字 (0〜9) だけからなる文字列なら true を返す。
///
/// 全角の数字・符号・空白・URL の区切りになる文字 (`:` `,` `/` `?` 等) を含む文字列は false。桁数の上限は設けない。
func isASCIIDigits(text: String) -> Bool {
    !text.isEmpty && text.utf8.allSatisfy { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }
}

/// 英数字とハイフンのラベルをドットで 2 つ以上つないだ、DNS の長さの上限に収まるドメイン名なら true を返す。
///
/// スキーム・パス・ポート・認証情報を含む文字列と、IP アドレスの形 (最後のラベルに英字が無い) は false。
/// private にしていないのは、`URL(string:)` も弾く入力 (空白・改行を含む文字列) をこの関数が弾くことを、テストから直接確かめるため。
func isHostName(text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    // 長さの上限は RFC 1035 2.3.4 (ラベルは 63 オクテット以下、名前は 255 オクテット以下で、ドット区切りの表記では 253 文字以下) に合わせる。
    // 最後のラベルに英字を求めるのは、数字だけのラベルが並ぶ IP アドレスを店のドメインとして通さないため。
    return text.utf8.count <= 253
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
