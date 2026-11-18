import Foundation

/// お気に入り: 利用者が「また買う」ために登録した 1 つの商品。
struct Favorite: Codable, Identifiable, Equatable {
    /// お気に入りの識別子 (端末内で作る)。
    let id: UUID
    /// 一覧とウィジェットに出す名前。利用者が編集できる。
    var name: String
    /// 商品バリアントの名前 (例: `200g / 豆のまま`)。一覧とウィジェットで、同じ商品の商品バリアントごとのお気に入りを見分けるために出す。
    /// 商品バリアントが 1 つだけの商品と、商品バリアントの名前を取っていない商品 (Amazon の商品) では nil。
    var variantName: String?
    /// 商品の画像の URL。取得できなかった時は nil。
    var imageURL: URL?
    /// 1 回に買う個数。1 以上。
    var quantity: Int
    /// どの店のどの商品か。
    var product: Product
    /// リマインド。設定していなければ nil。
    var reminder: Reminder?

    /// 購入画面を開くのに要る、店の種類ごとの商品の指し方。
    enum Product: Codable, Equatable {
        /// Shopify の店の商品。
        case shopify(ShopifyProduct)
        /// Amazon (amazon.co.jp) の商品。
        case amazon(AmazonProduct)
    }
}

/// Shopify の店の商品。
struct ShopifyProduct: Codable, Equatable {
    /// 店のドメイン (例: example.myshopify.com)。
    var shopDomain: String
    /// 商品バリアントの ID。数字だけの文字列。
    var variantID: String
}

/// Amazon (amazon.co.jp) の商品。
struct AmazonProduct: Codable, Equatable {
    /// ASIN。
    var asin: String
}

/// リマインド: 設定した日数ごとに、買う頃だと通知する設定。
struct Reminder: Codable, Equatable {
    /// 何日ごとに知らせるか。1 以上。
    var intervalDays: Int
    /// 日数を数え始めた日時。リマインドを設定した時と購入画面を開いた時に、その時刻へ更新する。通知はこの日時から intervalDays 日ごとに出す。
    var countedFrom: Date
}
