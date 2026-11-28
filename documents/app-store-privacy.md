# 「App のプライバシー」の回答の一覧

App Store Connect の「App のプライバシー」(App Privacy) に何と答えるかと、その根拠。2026-11-20 時点の main のコード (Firebase の SDK は `firebase-ios-sdk` 13.1.1 の `FirebaseAnalyticsCore` と `FirebaseCrashlytics`) で決め、2026-11-29 にお問い合わせのフォーム (`FirebaseFirestore` と `FirebaseAuth` を足した。https://github.com/bannzai/quickbuy/issues/100 ) の分を足した。SDK・通信先・送る値を変えた時は、この一覧と `docs/PrivacyPolicy-ja.md`、App Store Connect に反映する回答のファイル `fastlane/app_privacy_details.json` を合わせて直す。

回答の項目の意味は Apple の定義 (https://developer.apple.com/app-store/app-privacy-details/ ) に従う。下の「Apple の項目」の名前は App Store Connect の英語の表記。

## 結論

- データを収集するか: はい (Data Collection: Yes, we collect data from this app)
- トラッキング (Tracking): すべての項目で「いいえ」。広告識別子 (IDFA) を集めず (`FirebaseAnalyticsCore` は AdSupport を組み込まない構成)、App Tracking Transparency の許可も求めない。集めたデータを他社のデータと結び付けて広告に使うことも、データブローカーへ渡すこともしない
- ユーザーに紐付けるか (Linked to the User): Firebase (Analytics・Crashlytics) に送る項目は「はい」、Shopify Catalog に送る検索語は「いいえ」。Apple の定義は紐付けを「via their account, device, or other details」と書き、紐付けないと言えるのは「Stripping data of any direct identifiers, such as user ID or name, before collection」のように収集の前に識別子を外した時だけとしている (https://developer.apple.com/app-store/app-privacy-details/ の「Data linked to the user」。2026-11-20 に取得して確かめた)。アカウントの登録は無く、Firebase に利用者の ID (`Analytics.setUserID`・Crashlytics の `setUserID`) も渡していない (`grep -rn "setUserID" QuickBuy Shared QuickBuyWidget QuickBuyShare` が 0 件)。しかし Firebase に送るデータには、端末ごとの識別子 (app instance ID・IDFV・インストールごとの識別子) が付いたまま届く。そのため、端末を介して紐付くものとして「はい」と答える。検索語は、アプリが端末の識別子を付けずに送る (`QuickBuy/ShopifyCatalog.swift` の `searchShopifyCatalog` の document コメント「送るのは検索語・絞り込み・件数・`context`・プロフィールの URL だけ」。`context` は国・言語・通貨)

| Apple の項目 | 集めるもの | 送り先 | 利用目的 (Purposes) | 紐付け | トラッキング |
| --- | --- | --- | --- | --- | --- |
| Identifiers > Device ID | アプリのインストールごとの識別子 (app instance ID)、IDFV | Google Analytics for Firebase | Analytics | はい | いいえ |
| Identifiers > Device ID | インストールごとの識別子 | Firebase Crashlytics | App Functionality | はい | いいえ |
| Usage Data > Product Interaction | 購入画面を開いた入口と店の種類 (`purchase_screen_open`)、置いているウィジェットの大きさ (`widget_placed`)、起動・画面の表示・セッション | Google Analytics for Firebase | Analytics | はい | いいえ |
| Usage Data > Product Interaction | 異常終了の前に記録された同じイベントと画面の表示 (breadcrumb logs) | Firebase Crashlytics | App Functionality | はい | いいえ |
| Location > Coarse Location | IP アドレスから Google が推定するおおよその地域 | Google Analytics for Firebase | Analytics | はい | いいえ |
| Diagnostics > Crash Data | 異常終了の発生箇所の記録 (stack trace) とその時のアプリの状態 | Firebase Crashlytics | App Functionality | はい | いいえ |
| Diagnostics > Other Diagnostic Data | 端末と OS の情報 | Firebase Crashlytics、Google Analytics for Firebase | App Functionality (Crashlytics)、Analytics (Analytics) | はい | いいえ |
| Search History | トップページの商品の検索語 | Shopify Catalog (catalog.shopify.com) | App Functionality | いいえ | いいえ |
| Contact Info > Email Address | お問い合わせのフォームに入れた返信先のメールアドレス | Cloud Firestore、Slack (Functions が通知) | App Functionality | はい | いいえ |
| Identifiers > User ID | お問い合わせを送る時に Firebase Authentication が発行する匿名の uid | Cloud Firestore、Slack (Functions が通知) | App Functionality | はい | いいえ |
| User Content > Customer Support | お問い合わせの種別・内容と、付けて送るアプリのバージョン | Cloud Firestore、Slack (Functions が通知) | App Functionality | はい | いいえ |

集めないと答える項目: Contact Info のうち Email Address 以外・Health & Fitness・Financial Info・Contacts・User Content のうち Customer Support 以外・Browsing History・Purchases・Sensitive Info・Precise Location・Other Data。理由は下の「集めないと答える項目の根拠」。

## 項目ごとの根拠

### Google Analytics for Firebase

- アプリが送るイベントは `QuickBuy/AppAnalytics.swift` の `purchase_screen_open` (引数は入口の種類 `entry_point` と店の種類 `store` だけ) と `widget_placed` (引数はウィジェットの大きさ `widget_families` だけ)。商品・店・お気に入りの名前と開いた URL は送らない (同ファイルの `AnalyticsEvent` の document コメント)。これを Product Interaction と答える
- SDK が自動で集めるもの: Google の文書 (https://support.google.com/analytics/answer/10285841 「Prepare for Apple's App Store data-disclosure requirements」) に次の記述がある
  - 「An app instance id is automatically assigned to each instance of an app, for purposes of computing user metrics」。既定では「is not associated with a user identifier, like screen name or account ID, or with a device's advertising identifier」。利用者の ID と広告識別子には結び付かないが、端末ごとの識別子なので、Device ID (紐付けあり) と答える (上の「結論」の紐付けの行)
  - 「Analytics derives general location data from users' masked IP addresses」。これを Coarse Location と答える
  - 画面の表示とセッションは「are automatically measured」。これを Product Interaction に含める
- 広告識別子が無い時の識別子: Firebase の文書 (https://support.google.com/firebase/answer/6318039 「Data collection」) に「If the Advertising Identifier is unavailable, the SDK collects the Vendor Identifier.」とある。IDFA は「a developer has to link in the AdSupport.framework library」の時だけ集まり、本アプリは AdSupport を組み込まない `FirebaseAnalyticsCore` を使う (`QuickBuy.xcodeproj/project.pbxproj` の `productName = FirebaseAnalyticsCore`)。IDFV は Device ID に含めて答える
- 同じ文書の既定で集めるもの (「Operating systems」「Device models」等) を Other Diagnostic Data に含める。端末と OS の情報を Analytics の目的で Other Diagnostic Data と答えるか、Product Interaction の付随の情報として答えないかは、Google も Apple も対応を示していない (未確認)。多めに答える側に倒した
- 上の 2 つの Google の文書は、Apple の項目の名前 (Device ID・Product Interaction・Coarse Location 等) への対応を示していない。対応は agent が Apple の定義に照らして決めた (2026-11-20 に 2 つの文書を取得して確かめた)
- 「In-app purchase and subscription events are measured via StoreKit」(同じ文書) は、本アプリにアプリ内課金が無いため当たらない (Purchases は集めない)

### Firebase Crashlytics

- Firebase の文書 (https://firebase.google.com/docs/ios/app-store-data-collection の `FirebaseCrashlytics`) に「Collects stack traces and relevant application state when an application crashes.」と「Collects device and OS information to assist with debugging crashes.」がある。前者を Crash Data、後者を Other Diagnostic Data と答える
- 同じ文書の「Collects any custom keys, logs, and free-text user IDs that developers attach to crash reports.」は、本アプリが custom key・log・user ID を付けていないため当たらない (`grep -rn "Crashlytics" QuickBuy Shared QuickBuyWidget QuickBuyShare --include=*.swift` が 0 件)
- インストールごとの識別子: `docs/PrivacyPolicy-ja.md`「利用状況の解析と不具合の記録」は Crashlytics がインストールごとの識別子を集めると書いている (出典 https://firebase.google.com/support/privacy )。上の Firebase の文書の `FirebaseCrashlytics` の節は識別子を挙げていない。プライバシーポリシーと食い違わないよう Device ID と答える
- breadcrumb logs: Firebase の文書 (https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports の「Get breadcrumb logs」。2026-11-20 に取得して確かめた) に「Breadcrumb logs are powered by Google Analytics」とあり、Firebase の SDK for Google Analytics を組み込んだアプリでは、異常終了の前の `screen_view` と「any custom events that you manually log within the user's session, including the event's parameter data」が異常終了の記録に付く。本アプリは Analytics を組み込んでいるため、Analytics に送るイベント (`purchase_screen_open`・`widget_placed`) と画面の表示が Crashlytics にも届く。これを Crashlytics の Product Interaction と答える
- 利用目的は、Apple の定義の App Functionality に「minimize app crashes」が入るため App Functionality と答える
- Firebase の文書は、Firebase Installations が既定で集める Firebase user agent を「is never linked to a user or device identifier」と書いており、上の Other Diagnostic Data に含めて答える

### Shopify Catalog の検索

- トップページの検索と、トップページを表示した時の決まった語の検索で、検索語を Shopify Catalog (catalog.shopify.com) に送る (`QuickBuy/ShopifyCatalog.swift`。`docs/PrivacyPolicy-ja.md`「商品を検索する時に Shopify へ送られる情報」)。検索語は提供者のサーバーに送らず、端末にも保存しない
- Apple の定義の「収集」は、要求に応える間だけ使い続けて保持しないデータを含まない。Shopify が受け取った検索語を応答の後に保持するかは、Shopify の文書で確かめていない (未確認)。保持される場合に答え漏れにならないよう、Search History を「集める」側に倒して答えた。利用目的は検索の結果を出すための App Functionality
- 商品ページの URL を入れた時と、検索の結果からお気に入りに入れる時に、その店へ店のドメイン・商品の識別子・選んだ種類を送る通信は、商品の情報を表示するために画面の要求に応えるもので、検索の履歴でも閲覧の履歴でもないため答えない (agent の判断)

### お問い合わせのフォーム

- 設定の画面のお問い合わせのフォーム (`QuickBuy/ContactFormView.swift` の `sendContactInquiry`) は、種別・内容・返信先のメールアドレス・アプリのバージョン・匿名の uid・DEBUG ビルドかの印を Firestore の `contactInquiries` に 1 文書で書き、Functions (`firebase/functions/src/notifyContactInquiry.ts`) が同じ内容を運営者の Slack に通知する (ADR 0004。`docs/PrivacyPolicy-ja.md`「お問い合わせのフォームで送られる情報」)
- メールアドレスを Email Address、内容と種別を Customer Support (Apple の定義「Data generated by the user during a customer support request」) と答える。アプリのバージョンは問い合わせに付けて送るもので、Customer Support に含める (agent の判断)
- 匿名の uid は Apple の定義の User ID の「assigned user ID」に当たると読み、User ID と答える (agent の判断)
- 3 つとも、1 つの文書に uid とメールアドレスが一緒に入るため、紐付けは「はい」。利用目的は問い合わせに答えるための App Functionality (Apple の定義の App Functionality は「customer support」を含む)。保存するのは利用者が送信を押した時だけ

## 集めないと答える項目の根拠

- Contact Info (Email Address 以外)・Financial Info・Purchases: アカウントの登録・アプリ内課金・決済の処理が無い。店の画面で入力する情報は店の運営者が取り扱い、本アプリは受け取らない (`docs/PrivacyPolicy-ja.md`「商品を検索する時に Shopify へ送られる情報」の最後の段落)。氏名・電話番号・住所は、お問い合わせのフォームにも欄が無い
- User Content (Customer Support 以外): お気に入り (店のドメイン・商品の識別子・名前・個数・リマインド) は端末の中にだけ保存し、外へ送らない (`Shared/FavoriteStore.swift`。ADR 0001)
- Browsing History: 購入画面と商品ページは Safari で開き、開いた URL をアプリから外へ送らない (Analytics に URL を入れないことは上の `AnalyticsEvent` を参照)
- Precise Location: 位置情報の API を使わない
- Health & Fitness・Contacts・Sensitive Info・Other Data: 扱うコードが無い

## 未確認の点

- Google Analytics for Firebase と Firebase Crashlytics が集めるデータを Apple の項目のどれに当てるかを、Google が示した文書は見つからなかった。上の対応は agent が Apple の定義に照らして決めた
- Shopify が検索語を保持するか
- 提出の後に Apple の審査で項目の追加を求められた時は、この一覧を直す

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/quickbuy/issue-58
claude --resume 20c90b6a-7b64-481d-996d-f985fd6ed6b2
```
