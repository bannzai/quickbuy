import Foundation
import Testing
import UserNotifications
@testable import QuickBuy

/// ウィジェットの「カートイン」が出す「購入画面を開きますか？」の確認の通知の内容と、その通知をタップした時に開く購入画面・リマインドの数え直しを確かめる。
struct CartInConfirmationNotificationTests {
    /// 日数を数え始めた日時として使う、固定の日時 (2026-11-17 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)
    /// 確認の通知をタップした時刻として使う、`countedFrom` の 10 日後。
    private let tappedAt = Date(timeIntervalSince1970: 1_794_873_600 + 10 * 86400)

    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// 識別子の末尾の 1 文字・商品バリアントの名前・店のドメイン・商品バリアントの ID・個数を指定した、30 日ごとのリマインドを持つ Shopify の商品のお気に入りを返す。
    private func shopifyFavorite(idSuffix: String, variantName: String?, shopDomain: String, variantID: String, quantity: Int) -> Favorite {
        Favorite(
            id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA\(idSuffix)")!,
            name: "コーヒー豆",
            variantName: variantName,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: shopDomain, variantID: variantID)),
            reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)
        )
    }

    // MARK: - 通知の内容

    /// 見出しは「購入画面を開きますか？」、本文は「名前 種類 を N 個」と、どの店の購入画面が開くか (画面の見本 WidgetPush.dc.html の通知)。
    @Test func 通知の文言は見出しと何を何個とどの店か() throws {
        let content = try #require(
            cartInConfirmationNotificationContent(
                favorite: shopifyFavorite(idSuffix: "1", variantName: "200g / 豆のまま", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
            )
        )
        #expect(content.title == "購入画面を開きますか？")
        #expect(content.body == "コーヒー豆 200g / 豆のまま を 2 個\nタップすると mori-coffee.example の購入画面が開きます")
    }

    /// 商品バリアントの名前を持たないお気に入りの本文は、名前の後ろに空白を 1 つ置いて個数が続く (空白を 2 つにしない)。個数が 1 の時も「1 個」と出す。
    @Test func 種類の名前の無いお気に入りの本文は名前と個数() throws {
        #expect(
            try #require(
                cartInConfirmationNotificationContent(
                    favorite: shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 1)
                )
            ).body == "コーヒー豆 を 1 個\nタップすると sukoyaka-soap.example の購入画面が開きます"
        )
    }

    /// 付加情報に載せるのはお気に入りの識別子だけで、そのお気に入りの購入画面の URL はどこにも載せない。
    @Test func 載せるのはお気に入りの識別子だけ() throws {
        let content = try #require(
            cartInConfirmationNotificationContent(
                favorite: shopifyFavorite(idSuffix: "1", variantName: "200g / 豆のまま", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
            )
        )
        #expect(content.userInfo.count == 1)
        #expect(content.userInfo["favoriteID"] as? String == "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")
        let allText = "\(content.title)\(content.subtitle)\(content.body)\(content.userInfo)"
        #expect(!allText.contains("https://mori-coffee.example/cart/70881412:2"))
        #expect(!allText.contains("/cart/"))
    }

    /// Amazon の商品の通知は、見出しを「Amazon の商品ページを開きますか？」にし、本文に個数を出さずに商品ページが開くことを書く。商品ページの URL は載せない。
    @Test func Amazonの商品の通知は商品ページが開くことを書く() throws {
        let content = try #require(
            cartInConfirmationNotificationContent(
                favorite: Favorite(id: UUID(), name: "単3電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil)
            )
        )
        #expect(content.title == "Amazon の商品ページを開きますか？")
        #expect(content.body == "単3電池\nタップすると www.amazon.co.jp の商品ページが開きます")
        #expect(!"\(content.title)\(content.body)\(content.userInfo)".contains("/dp/"))
    }

    /// 開く URL を組み立てられないお気に入り (ASIN の形でない Amazon の商品・ホスト名の形でない店のドメイン) では、確認の通知を作らない。
    @Test func 開くURLを組み立てられないお気に入りでは通知を作らない() {
        let amazonFavorite = Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPL")), reminder: nil)
        #expect(cartInConfirmationNotificationContent(favorite: amazonFavorite) == nil)
        #expect(cartInConfirmationNotificationRequest(favorite: amazonFavorite) == nil)
        #expect(
            cartInConfirmationNotificationContent(
                favorite: shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "https://evil.example/cart", variantID: "70881412", quantity: 1)
            ) == nil
        )
    }

    // MARK: - 通知の要求

    /// 通知の識別子はお気に入りごとに決まった値で、同じお気に入りでは何度作っても同じ (続けて押しても 1 つに置き換わる)。
    /// 別のお気に入りとは違う値で、リマインドの通知の識別子 (お気に入りの識別子) とも違う。すぐに出す (時刻の条件を持たない)。
    @Test func 通知の識別子はお気に入りごとに1つでリマインドと別() throws {
        let coffeeFavorite = shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        let firstRequest = try #require(cartInConfirmationNotificationRequest(favorite: coffeeFavorite))

        #expect(firstRequest.identifier == "cartInConfirmation-5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")
        #expect(try #require(cartInConfirmationNotificationRequest(favorite: coffeeFavorite)).identifier == firstRequest.identifier)
        #expect(
            try #require(
                cartInConfirmationNotificationRequest(
                    favorite: shopifyFavorite(idSuffix: "2", variantName: nil, shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 1)
                )
            ).identifier == "cartInConfirmation-5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2"
        )
        #expect(firstRequest.trigger == nil)
    }

    // MARK: - 「カートイン」を押した時の要求

    /// 保存済みのお気に入りのうち、指定した識別子のものの確認の通知の要求を作る。保存先は書き換えない (押した時はリマインドを数え直さない)。
    @Test func 押した時は指定したお気に入りの要求を作り保存先を書き換えない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let soapFavorite = shopifyFavorite(idSuffix: "2", variantName: nil, shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 5)
        try saveFavorites(
            favorites: [shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2), soapFavorite],
            fileURL: fileURL
        )
        let savedData = try Data(contentsOf: fileURL)

        let request = try #require(try cartInConfirmationNotificationRequest(favoriteID: soapFavorite.id, fileURL: fileURL))

        #expect(request.identifier == "cartInConfirmation-5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2")
        #expect(request.content.body == "コーヒー豆 を 5 個\nタップすると sukoyaka-soap.example の購入画面が開きます")
        #expect(try Data(contentsOf: fileURL) == savedData)
    }

    /// 保存されていない識別子と、開く URL を組み立てられないお気に入り (ASIN の形でない Amazon の商品) では要求を作らない。
    @Test func 保存されていないお気に入りと組み立てられないお気に入りでは要求を作らない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let amazonFavorite = Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPL")), reminder: nil)
        try saveFavorites(
            favorites: [shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2), amazonFavorite],
            fileURL: fileURL
        )

        #expect(try cartInConfirmationNotificationRequest(favoriteID: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA9")!, fileURL: fileURL) == nil)
        #expect(try cartInConfirmationNotificationRequest(favoriteID: amazonFavorite.id, fileURL: fileURL) == nil)
    }

    /// 保存先を読めない時 (中身が JSON でない) はエラーを投げる。
    @Test func 保存先を読めない時はエラーを投げる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data("not json".utf8).write(to: fileURL)

        #expect(throws: (any Error).self) {
            try cartInConfirmationNotificationRequest(favoriteID: UUID(), fileURL: fileURL)
        }
    }

    // MARK: - 通知のタップ

    /// 確認の通知のタップでは、そのお気に入りの店のドメイン・商品バリアントの ID・個数から組み立てた購入画面の URL を返し、そのお気に入りのリマインドだけをタップした時刻から数え直す。
    @Test func 通知のタップで保存済みのお気に入りから購入画面のURLを組み立てて数え直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let coffeeFavorite = shopifyFavorite(idSuffix: "1", variantName: "200g / 豆のまま", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        let soapFavorite = shopifyFavorite(idSuffix: "2", variantName: nil, shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 5)
        try saveFavorites(favorites: [coffeeFavorite, soapFavorite], fileURL: fileURL)
        var recountedSoapFavorite = soapFavorite
        recountedSoapFavorite.reminder = Reminder(intervalDays: 30, countedFrom: tappedAt)
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(
            try openingURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: #require(cartInConfirmationNotificationContent(favorite: soapFavorite)).userInfo,
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { appliedChanges.append($0) }
            )?.absoluteString == "https://sukoyaka-soap.example/cart/70881382:5"
        )
        #expect(try loadFavorites(fileURL: fileURL) == [coffeeFavorite, recountedSoapFavorite])
        #expect(appliedChanges == [[.schedule(favorite: recountedSoapFavorite)]])
    }

    /// Amazon の商品の確認の通知のタップでは、www.amazon.co.jp の商品ページの URL を返し、リマインドをタップした時刻から数え直す。
    @Test func Amazonの商品の通知のタップで商品ページのURLを返して数え直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        let amazonFavorite = Favorite(
            id: UUID(),
            name: "単3電池",
            imageURL: nil,
            quantity: 1,
            product: .amazon(AmazonProduct(asin: "B0DTESTAB1")),
            reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)
        )
        try saveFavorites(favorites: [amazonFavorite], fileURL: fileURL)
        var recountedAmazonFavorite = amazonFavorite
        recountedAmazonFavorite.reminder = Reminder(intervalDays: 30, countedFrom: tappedAt)

        #expect(
            try openingURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: #require(cartInConfirmationNotificationContent(favorite: amazonFavorite)).userInfo,
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { _ in }
            )?.absoluteString == "https://www.amazon.co.jp/dp/B0DTESTAB1"
        )
        #expect(try loadFavorites(fileURL: fileURL) == [recountedAmazonFavorite])
    }

    /// 確認の通知を出した後に個数を変えた時は、通知の文言の個数ではなく、タップした時に保存されている個数で組み立てる (購入画面の URL を通知に載せないため)。
    @Test func 通知の後に個数を変えたらタップした時の個数で組み立てる() throws {
        let fileURL = temporaryFavoritesFileURL()
        let coffeeFavorite = shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        try saveFavorites(favorites: [coffeeFavorite], fileURL: fileURL)
        try updateFavorite(id: coffeeFavorite.id, name: coffeeFavorite.name, quantity: 3, fileURL: fileURL)

        #expect(
            try openingURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: #require(cartInConfirmationNotificationContent(favorite: coffeeFavorite)).userInfo,
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { _ in }
            )?.absoluteString == "https://mori-coffee.example/cart/70881412:3"
        )
    }

    /// 確認の通知を消す操作 (タップ以外) では購入画面を開かず、リマインドを数え直さない。
    @Test func 通知を消す操作では購入画面を開かず数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let coffeeFavorite = shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        try saveFavorites(favorites: [coffeeFavorite], fileURL: fileURL)
        var appliedChanges: [[ReminderNotificationChange]] = []

        #expect(
            try openingURLForNotificationResponse(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                userInfo: #require(cartInConfirmationNotificationContent(favorite: coffeeFavorite)).userInfo,
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { appliedChanges.append($0) }
            ) == nil
        )
        #expect(try loadFavorites(fileURL: fileURL) == [coffeeFavorite])
        #expect(appliedChanges.isEmpty)
    }

    /// 確認の通知を出した後にお気に入りを削除した時は、通知をタップしても購入画面を開かない。
    @Test func 削除したお気に入りの通知のタップでは購入画面を開かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let coffeeFavorite = shopifyFavorite(idSuffix: "1", variantName: nil, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        try saveFavorites(favorites: [coffeeFavorite], fileURL: fileURL)
        try deleteFavorite(id: coffeeFavorite.id, fileURL: fileURL)

        #expect(
            try openingURLForNotificationResponse(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: #require(cartInConfirmationNotificationContent(favorite: coffeeFavorite)).userInfo,
                now: tappedAt,
                fileURL: fileURL,
                applyChanges: { _ in }
            ) == nil
        )
    }
}
