import Foundation
import Testing
@testable import QuickBuy

/// 端末の言語が日本語のほかの時の、通知・ウィジェット・画面の文言を返す関数の文言を確かめる (英語は issue #54、ほかの 7 言語は issue #90)。
///
/// 英語は文言ごとの訳、ほかの 7 言語は訳が引けること・差し込む値の語順・単数と複数の形を確かめる。
/// 期待値は文字列カタログ (`Shared/Localizable.xcstrings`) の訳で、「カートイン」は `translate-app.config.json` の用語集の訳。日本語の文言は、各関数のテストが `Locale(identifier: "ja")` を渡して確かめる。
struct LocalizationTests {
    /// 英語の locale。
    private let englishLocale = Locale(identifier: "en")
    /// 日数を数え始めた日時として使う、固定の日時 (2026-11-17 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)

    /// 名前・商品バリアントの名前・個数を指定した、Shopify の店 mori-coffee.example の商品のお気に入りを返す。
    private func shopifyFavorite(name: String, variantName: String?, quantity: Int) -> Favorite {
        Favorite(
            id: UUID(),
            name: name,
            variantName: variantName,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: nil
        )
    }

    // MARK: - 通知

    /// ウィジェットの「カートイン」の確認の通知は、見出しと本文が英語になる。店と商品の名前は訳さない。
    @Test func カートインの確認の通知は英語() throws {
        let shopifyContent = try #require(
            cartInConfirmationNotificationContent(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 2), locale: englishLocale)
        )
        #expect(shopifyContent.title == "Open checkout?")
        #expect(shopifyContent.body == "コーヒー豆 200g ×2\nTap to open checkout on mori-coffee.example")
    }

    /// リマインドの通知は、見出しと本文が英語になる。
    @Test func リマインドの通知は英語() {
        let shopifyContent = reminderNotificationContent(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 1), locale: englishLocale)
        #expect(shopifyContent.title == "Time to buy again")
        #expect(shopifyContent.body == "コーヒー豆 200g\nTap to open checkout")
    }

    // MARK: - ウィジェット

    /// ウィジェットの行のボタンは英語になる。
    @Test func ボタンと確認の見出しは英語() {
        #expect(cartInButtonTitle(locale: englishLocale) == "Add to Cart")
        #expect(cartInConfirmationTitle(locale: englishLocale) == "Open checkout?")
    }

    /// 通知の許可が要ることの文は、ボタンの英語の名前を入れた英語の文になる。
    @Test func 通知の許可が要ることの文は英語() {
        #expect(widgetNotificationRequiredText(locale: englishLocale) == "Add to Cart needs notification permission")
    }

    /// ウィジェットの行の説明は、個数を「×N」で出し、商品バリアントの名前との区切りを「 · 」にする。
    @Test func 行の説明は英語の個数() {
        #expect(favoriteWidgetRowCaption(favorite: shopifyFavorite(name: "豆", variantName: "200g", quantity: 2), locale: englishLocale) == "200g · ×2")
        #expect(favoriteWidgetRowCaption(favorite: shopifyFavorite(name: "豆", variantName: nil, quantity: 1), locale: englishLocale) == "×1")
    }

    /// リマインドの状態は英語で、残りの日数が 1 日の時は単数、2 日以上の時は複数の形になる。
    @Test func リマインドの状態は英語で日数の単数と複数を分ける() {
        let reminder = Reminder(intervalDays: 7, countedFrom: countedFrom)
        #expect(reminderStatusText(reminder: nil, now: countedFrom, locale: englishLocale) == "No reminder")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(7 * 86400), locale: englishLocale) == "Time to buy again")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(6 * 86400), locale: englishLocale) == "Next reminder in 1 day")
        #expect(reminderStatusText(reminder: reminder, now: countedFrom.addingTimeInterval(5 * 86400), locale: englishLocale) == "Next reminder in 2 days")
    }

    // MARK: - 画面

    /// 一覧の確認の 2 行目と、編集の画面の数え直しの文は英語になる。
    @Test func 確認の文と数え直しの文は英語() {
        #expect(cartInConfirmationText(favorite: shopifyFavorite(name: "コーヒー豆", variantName: "200g", quantity: 2), locale: englishLocale) == "Opens with コーヒー豆 200g ×2 in the cart")
        #expect(reminderRecountText(locale: englishLocale) == "The count restarts on the day you open checkout")
    }

    /// 追加の画面の保存するボタンは、選んだ種類が 1 つの時は単数、2 つ以上の時は複数の形になる。
    @Test(arguments: [
        (true, 1, "Add 1 Variant to Favorites"),
        (true, 2, "Add 2 Variants to Favorites"),
        (true, 0, "Add to Favorites"),
        (false, 1, "Add to Favorites"),
    ])
    func 保存するボタンは英語で種類の数の単数と複数を分ける(hasVariantChoices: Bool, selectedVariantCount: Int, expectedTitle: String) {
        #expect(favoriteAdditionButtonTitle(hasVariantChoices: hasVariantChoices, selectedVariantCount: selectedVariantCount, locale: englishLocale) == expectedTitle)
    }

    /// 登録できない理由の文言は、どの理由でも英語になる。
    @Test(arguments: [
        (FavoriteAdditionLoadError.notProductPageURL, "This URL can't be added\nEnter a product page URL from a Shopify store"),
        (.temporarilyUnavailable, "Couldn't get product info\nPlease wait a moment and try again"),
        (.notRegistrable, "This product can't be added\nThe store doesn't share product info or the product wasn't found"),
    ])
    func 登録できない理由は英語(error: FavoriteAdditionLoadError, expectedMessage: String) {
        #expect(favoriteAdditionLoadErrorMessage(error: error, locale: englishLocale) == expectedMessage)
    }

    /// 検索の失敗の文言は、どの理由でも英語になる。待つ秒数は 1 秒の時は単数、2 秒以上の時は複数の形になる。
    @Test(arguments: [
        (ShopifyCatalogError.rateLimited(retryAfterSeconds: 1), "It's busy right now\nPlease wait about 1 second and try again"),
        (.rateLimited(retryAfterSeconds: 120), "It's busy right now\nPlease wait about 120 seconds and try again"),
        (.rateLimited(retryAfterSeconds: nil), "It's busy right now\nPlease wait a moment and try again"),
        (.connectionFailed, "Couldn't connect\nPlease try again where the signal is better"),
        (.failed, "Couldn't load products\nPlease wait a moment and try again"),
    ])
    func 検索の失敗の文言は英語(error: ShopifyCatalogError, expectedMessage: String) {
        #expect(shopifyCatalogErrorMessage(error: error, locale: englishLocale) == expectedMessage)
    }

    /// 通知の要求の文言は、渡した言語になる (アプリは `appTextLocale` を渡す)。
    @Test func 通知の要求は渡した言語の文言() throws {
        let favorite = shopifyFavorite(name: "コーヒー豆", variantName: nil, quantity: 5)
        #expect(try #require(cartInConfirmationNotificationRequest(favorite: favorite, locale: englishLocale)).content.body == "コーヒー豆 ×5\nTap to open checkout on mori-coffee.example")
        #expect(try #require(cartInConfirmationNotificationRequest(favorite: favorite, locale: Locale(identifier: "ja"))).content.body == "コーヒー豆 を 5 個\nタップすると mori-coffee.example の購入画面が開きます")
        var reminderFavorite = favorite
        reminderFavorite.reminder = Reminder(intervalDays: 7, countedFrom: countedFrom)
        #expect(try #require(reminderNotificationRequest(favorite: reminderFavorite, locale: englishLocale)).content.title == "Time to buy again")
        #expect(try #require(reminderNotificationRequest(favorite: reminderFavorite, locale: Locale(identifier: "ja"))).content.title == "そろそろ買う頃です")
    }

    /// ホームの検索語の候補は、英語では英語の語、日本語では今の語になる。先頭の語が最初に検索する語になる。
    @Test func 検索語の候補は言語ごとの語() {
        #expect(homeSuggestedSearchQueries(locale: englishLocale) == ["Coffee beans", "Black tea", "Shampoo", "Laundry detergent", "Protein", "Dog food"])
        #expect(homeSuggestedSearchQueries(locale: Locale(identifier: "ja")) == ["コーヒー豆", "紅茶", "シャンプー", "洗濯洗剤", "プロテイン", "ドッグフード"])
    }

    /// 文言の言語は、bundle が選んだ言語の並びの先頭にする。並びが空の時だけ渡した代わりの locale にする。
    @Test func 文言の言語はbundleが選んだ言語の先頭() {
        #expect(textLocale(preferredLocalizations: ["en", "ja"], fallback: Locale(identifier: "fr")).identifier == "en")
        #expect(textLocale(preferredLocalizations: ["ja"], fallback: Locale(identifier: "fr")).identifier == "ja")
        #expect(textLocale(preferredLocalizations: [], fallback: Locale(identifier: "fr")).identifier == "fr")
    }

    /// アプリの bundle が、文字列カタログの 9 つの言語 (`QuickBuy.xcodeproj` の `knownRegions`) の訳を持ち、足した 7 つの言語で「カートイン」がその言語の訳で引ける。
    ///
    /// 期待値は `translate-app.config.json` の用語集の訳。どれかの言語が bundle に入らないと、その言語の端末で日本語か英語の文言が出る。
    @Test func 九つの言語の訳が引ける() {
        for localization in ["ja", "en", "es", "fr", "de", "pt-BR", "ko", "zh-Hans", "zh-Hant"] {
            #expect(Bundle.main.localizations.contains(localization), "\(localization) \(Bundle.main.localizations)")
        }
        for (localeIdentifier, cartInTitle) in [
            ("es", "Al carrito"), ("fr", "Au panier"), ("de", "In den Korb"), ("pt-BR", "Ao carrinho"),
            ("ko", "장바구니 담기"), ("zh-Hans", "加入购物车"), ("zh-Hant", "加入購物車"),
        ] {
            #expect(String(localized: LocalizedStringResource("カートイン", locale: Locale(identifier: localeIdentifier))) == cartInTitle, "\(localeIdentifier)")
        }
    }

    /// 足した 7 つの言語で、店と商品の名前・個数を差し込む文言が、差し込む値を取り違えずにその言語で出る。
    ///
    /// 期待値は、その言語の文の語順で名前・個数・店を並べた文。翻訳の LLM が `%@` と `%lld` の順を原文と逆にした訳を返したことがあり (PR #93)、順が逆の訳は 1 つ目の引数を整数として読んで壊れる。
    @Test(arguments: [
        ("es", "Kaffee 200g × 2\nToca para abrir la página de pago de mori-coffee.example", "Abre la página de pago con Kaffee 200g ×2 en el carrito", "Al carrito necesita permiso para enviarte notificaciones"),
        ("fr", "Kaffee 200g × 2\nTouchez pour ouvrir la page de paiement de mori-coffee.example", "Ouvre la page de paiement avec Kaffee 200g ×2 dans le panier", "Au panier a besoin de votre autorisation pour vous envoyer des notifications"),
        ("de", "Kaffee 200g × 2\nTippe, um die Kasse von mori-coffee.example zu öffnen", "Öffnet die Kasse mit Kaffee 200g ×2 im Warenkorb", "In den Korb braucht deine Erlaubnis für Mitteilungen"),
        ("pt-BR", "Kaffee 200g × 2\nToque para abrir a página de pagamento de mori-coffee.example", "Abre a página de pagamento com Kaffee 200g ×2 no carrinho", "Ao carrinho precisa da sua permissão para enviar notificações"),
        ("ko", "Kaffee 200g 2개\n탭하면 mori-coffee.example의 결제 화면이 열립니다", "Kaffee 200g 2개를 장바구니에 담고 결제 화면을 엽니다", "장바구니 담기에 알림 권한이 필요합니다"),
        ("zh-Hans", "Kaffee 200g × 2\n轻点后打开 mori-coffee.example 的结账页面", "将 Kaffee 200g × 2 件加入购物车并打开结账页面", "加入购物车需要通知权限"),
        ("zh-Hant", "Kaffee 200g × 2\n點一下即可開啟 mori-coffee.example 的結帳頁面", "將 Kaffee 200g × 2 件加入購物車並開啟結帳頁面", "加入購物車需要通知權限"),
    ])
    func 差し込む値はその言語の語順で出る(localeIdentifier: String, notificationBody: String, confirmationText: String, notificationRequiredText: String) throws {
        let favorite = shopifyFavorite(name: "Kaffee", variantName: "200g", quantity: 2)
        #expect(try #require(cartInConfirmationNotificationContent(favorite: favorite, locale: Locale(identifier: localeIdentifier))).body == notificationBody)
        #expect(cartInConfirmationText(favorite: favorite, locale: Locale(identifier: localeIdentifier)) == confirmationText)
        #expect(widgetNotificationRequiredText(locale: Locale(identifier: localeIdentifier)) == notificationRequiredText)
    }

    /// 足した 7 つの言語で、ウィジェットの行の説明・アプリの一覧の個数・リマインドの次の日付の文が、区切りの記号と差し込む値の順を取り違えずに出る。
    ///
    /// 区切り「 ・ 」は 7 言語とも「 · 」(fb5d542 で足した訳)。ドイツ語の個数は「%lld Stück」では大サイズのウィジェットで見本の説明が「2 Stü…」と切れたため、英語・スペイン語・フランス語・ポルトガル語と同じ「×N」にした (PR #93)。リマインドの 2 つの文は `%@` を 2 つ持ち、順が入れ替わると数え直しの文と日付が入れ替わる。
    @Test(arguments: [
        ("es", "200g · ×2", " · ×2", "Reinicio\nTu próximo recordatorio es 26 nov", "Reinicio\nLa próxima notificación es el 26 nov\nLas notificaciones no están permitidas\nActiva las notificaciones de Quick Buy en Ajustes para recibirlas"),
        ("fr", "200g · ×2", " · ×2", "Reinicio\nVotre prochain rappel est prévu le 26 nov", "Reinicio\nLa prochaine notification est prévue pour 26 nov\nLes notifications ne sont pas autorisées\nAutorisez les notifications de Quick Buy dans Réglages pour les recevoir"),
        ("de", "200g · ×2", " · ×2", "Reinicio\nDeine nächste Erinnerung ist am 26 nov", "Reinicio\nNächste Erinnerung: 26 nov\nMitteilungen sind nicht erlaubt\nErlaube Mitteilungen von Quick Buy in den Einstellungen, um sie zu erhalten"),
        ("pt-BR", "200g · ×2", " · ×2", "Reinicio\nSeu próximo lembrete é em 26 nov", "Reinicio\nA próxima notificação será em 26 nov\nAs notificações não estão permitidas\nAtive as notificações do Quick Buy nos Ajustes para recebê-las"),
        ("ko", "200g · 2개", " · 2개", "Reinicio\n다음 알림은 26 nov입니다", "Reinicio\n다음 알림은 26 nov입니다\n알림이 허용되지 않았습니다\n설정 앱에서 Quick Buy 알림을 허용하면 받을 수 있습니다"),
        ("zh-Hans", "200g · 2 件", " · 2 件", "Reinicio\n下次提醒时间是 26 nov", "Reinicio\n下次通知时间是 26 nov\n通知未获允许\n在“设置”中允许 Quick Buy 发送通知后即可收到"),
        ("zh-Hant", "200g · 2 個", " · 2 個", "Reinicio\n下次提醒時間是 26 nov", "Reinicio\n下次通知時間是 26 nov\n通知未獲允許\n在「設定」中允許 Quick Buy 傳送通知後即可收到"),
    ])
    func 区切りと二つの値を差し込む文はその言語で出る(localeIdentifier: String, widgetRowCaption: String, listQuantityText: String, reminderDateText: String, reminderDateWithoutPermissionText: String) {
        let locale = Locale(identifier: localeIdentifier)
        #expect(favoriteWidgetRowCaption(favorite: shopifyFavorite(name: "Kaffee", variantName: "200g", quantity: 2), locale: locale) == widgetRowCaption)
        #expect(String(localized: LocalizedStringResource(" ・ \(2) 個", locale: locale)) == listQuantityText)
        #expect(String(localized: LocalizedStringResource("\("Reinicio")\n次の知らせは \("26 nov") です", locale: locale)) == reminderDateText)
        #expect(String(localized: LocalizedStringResource("\("Reinicio")\n次の知らせは \("26 nov") です\n通知が許可されていません\n設定アプリで Quick Buy の通知を許可すると届きます", locale: locale)) == reminderDateWithoutPermissionText)
    }

    /// 数で語の形が変わる 4 つの言語では、数を差し込む 4 つの文言が 1 と 2 で単数と複数の形に分かれる。
    @Test(arguments: [
        ("es", ["Cada día", "Cada 2 días"], ["Próximo recordatorio en 1 día", "Próximo recordatorio en 2 días"], ["Añadir 1 variante a favoritos", "Añadir 2 variantes a favoritos"], ["Hay mucho tráfico\nEspera 1 segundo y vuelve a intentarlo", "Hay mucho tráfico\nEspera unos 2 segundos y vuelve a intentarlo"]),
        ("fr", ["Tous les jours", "Tous les 2 jours"], ["Prochain rappel dans 1 jour", "Prochain rappel dans 2 jours"], ["Ajouter 1 variante aux favoris", "Ajouter 2 variantes aux favoris"], ["Le service est très sollicité\nAttendez environ 1 seconde, puis réessayez", "Le service est très sollicité\nAttendez environ 2 secondes, puis réessayez"]),
        ("de", ["Jeden Tag", "Alle 2 Tage"], ["Nächste Erinnerung in 1 Tag", "Nächste Erinnerung in 2 Tagen"], ["1 Variante zu Favoriten hinzufügen", "2 Varianten zu Favoriten hinzufügen"], ["Der Dienst ist gerade stark ausgelastet\nWarte etwa 1 Sekunde und versuche es erneut", "Der Dienst ist gerade stark ausgelastet\nWarte etwa 2 Sekunden und versuche es erneut"]),
        ("pt-BR", ["Todo dia", "A cada 2 dias"], ["Próximo lembrete em 1 dia", "Próximo lembrete em 2 dias"], ["Adicionar 1 variante aos favoritos", "Adicionar 2 variantes aos favoritos"], ["O serviço está sobrecarregado\nEspere cerca de 1 segundo e tente novamente", "O serviço está sobrecarregado\nEspere cerca de 2 segundos e tente novamente"]),
    ])
    func 数で語の形が変わる言語は単数と複数で文言が変わる(localeIdentifier: String, intervalTexts: [String], reminderTexts: [String], additionTitles: [String], rateLimitedMessages: [String]) {
        let locale = Locale(identifier: localeIdentifier)
        for (index, count) in [1, 2].enumerated() {
            #expect(String(localized: LocalizedStringResource("\(count) 日ごと", locale: locale)) == intervalTexts[index])
            // 7 日ごとのリマインドで、残りが count 日になる日時。
            #expect(reminderStatusText(reminder: Reminder(intervalDays: 7, countedFrom: countedFrom), now: countedFrom.addingTimeInterval(Double(7 - count) * reminderDaySeconds), locale: locale) == reminderTexts[index])
            #expect(favoriteAdditionButtonTitle(hasVariantChoices: true, selectedVariantCount: count, locale: locale) == additionTitles[index])
            #expect(shopifyCatalogErrorMessage(error: .rateLimited(retryAfterSeconds: count), locale: locale) == rateLimitedMessages[index])
        }
    }

    /// ホームの案内の見出しが、日本語と英語で引ける。「1 タップ」と言わず、ストアのサブタイトルと同じ言い方にする (issue #64)。
    @Test func ホームの案内の見出しは探さずに買い直す() {
        #expect(String(localized: LocalizedStringResource("いつもの商品を探さずに買い直す", locale: Locale(identifier: "ja"))) == "いつもの商品を探さずに買い直す")
        #expect(String(localized: LocalizedStringResource("いつもの商品を探さずに買い直す", locale: englishLocale)) == "Rebuy your usual items without searching")
    }

    /// 設定画面の、Firebase に送る記録の説明 (PR #51 で足した文言) が英語で引ける。
    @Test func 設定画面の記録の説明は英語() {
        #expect(
            String(localized: LocalizedStringResource("利用の状況とアプリが落ちた時の記録を Google の Firebase に送ります\n商品や店の名前と開いた画面の URL は送りません", locale: englishLocale))
                == "Usage and crash reports are sent to Google Firebase\nProduct names, store names, and URLs of opened pages are not sent"
        )
    }

    /// 画面に直接書いた、数を含む文言のカタログの訳 (編集の画面の「N 日ごと」と次の知らせの日付) が英語で引ける。
    @Test func 画面の数を含む文言は英語() {
        #expect(String(localized: LocalizedStringResource("\(1) 日ごと", locale: englishLocale)) == "1 day")
        #expect(String(localized: LocalizedStringResource("\(7) 日ごと", locale: englishLocale)) == "7 days")
        #expect(String(localized: LocalizedStringResource("\("Restarts")\n次の知らせは \("Nov 26") です", locale: englishLocale)) == "Restarts\nNext reminder: Nov 26")
        #expect(
            String(localized: LocalizedStringResource("\("Restarts")\n次の知らせは \("Nov 26") です\n通知が許可されていません\n設定アプリで Quick Buy の通知を許可すると届きます", locale: englishLocale))
                == "Restarts\nNext reminder: Nov 26\nNotifications aren't allowed\nAllow notifications for Quick Buy in Settings to get reminders"
        )
    }

    /// 追加の画面の URL の説明が英語で引ける。
    @Test func 追加の画面のURLの説明は英語() {
        #expect(
            String(localized: LocalizedStringResource("Shopify の店の商品ページの URL を貼り付けてください", locale: englishLocale))
                == "Paste a product page URL from a Shopify store"
        )
    }

    /// 商品の詳細ページの見出しと在庫の文言 (issue #76) が英語で引ける。
    @Test func 商品の詳細ページの文言は英語() {
        #expect(String(localized: LocalizedStringResource("商品の詳細", locale: englishLocale)) == "Product Details")
        #expect(String(localized: LocalizedStringResource("商品の説明", locale: englishLocale)) == "Description")
        #expect(String(localized: LocalizedStringResource("選べる種類", locale: englishLocale)) == "Available Options")
        #expect(String(localized: LocalizedStringResource("在庫あり", locale: englishLocale)) == "In stock")
    }

    /// お問い合わせのフォームの種別の名前は英語になる。
    @Test func 問い合わせの種別の名前は英語() {
        #expect(
            ContactInquiryType.allCases.map { inquiryType in
                var title = inquiryType.title
                title.locale = englishLocale
                return String(localized: title)
            } == ["Bugs and issues", "Feedback & suggestions", "Other"]
        )
    }

    /// お問い合わせのフォームの、返信の送り元の説明と送れなかった時の説明は、連絡先のメールアドレスを入れた英語の文になる。
    @Test func 問い合わせのフォームの説明は英語() {
        #expect(
            String(localized: LocalizedStringResource("返信は \(contactMailAddress) から届きます\nメールアドレスは返信にだけ使います", locale: englishLocale))
                == "Replies will come from bannzai.app@gmail.com\nWe only use your email address to reply"
        )
        #expect(
            String(localized: LocalizedStringResource("\(contactMailAddress) へメールでご連絡ください", locale: englishLocale))
                == "Please email us at bannzai.app@gmail.com"
        )
    }
}
