# 0004. お問い合わせだけを Firestore に保存し、Functions で Slack に通知する

## Status
Accepted (2026-11-29)

## Context
設定の画面の「お問い合わせ」は、宛先と件名を入れたメールの作成を端末の既定のメールアプリで開くだけだった (`documents/DIRECTION.md`「決めたこと」の 2026-11-18 の行)。メールアプリを設定していない利用者は問い合わせを送れず、届いた問い合わせにはアプリのバージョンも付かない。

bannzai の発言 (2026-11-29、https://github.com/bannzai/quickbuy/issues/100 の背景): 「お問い合わせは既存のbannzai/Focusあたりを参考にして作ろう」。bannzai/Focus は、アプリの中のフォームで種別・内容・返信先のメールアドレスを入れてもらい、Firestore の `contactInquiries` に保存し、文書の作成で起動する Functions が Slack に通知する。

ADR 0001 は、最初の版がサーバーの DB・ホスティング・認証を持たないと決めた。Focus と同じ作りにするには、Firestore・Firebase Auth・Functions を持つ必要がある。

## Decision
- **保存**: お問い合わせだけを Firestore のコレクション `contactInquiries` に 1 件 1 文書で保存する。文書の形は `QuickBuy/ContactInquiry.swift` の `ContactInquiry` と、サーバーの時刻の `createdDateTime`。お気に入りは今までどおり端末内だけに保存し、Firestore に置かない (ADR 0001 の「DB / ストレージ」はお気に入りについて変えない)
- **セキュリティルール** (`firebase/firestore.rules`): `contactInquiries` の作成だけを許し、送った人の ID を本人の uid に限る。読み取り・更新・削除は誰にも許さない。ほかのパスはすべて拒否する。運営者は Slack の通知と Firebase のコンソールで読む
- **認証**: 問い合わせを送る時にだけ Firebase Auth の匿名のサインインをする (ルールが送った人の uid を求めるため)。ログイン・会員登録の画面は作らない (ADR 0001 の「認証」の画面を持たない決まりは変えない)。起動の時にサインインしないのは、問い合わせを送らない利用者の匿名のアカウントを作らないため
- **通知** (`firebase/functions/src/notifyContactInquiry.ts`): 文書の作成で起動する Functions (第 2 世代、asia-northeast1) が内容を Slack の Incoming Webhook に送る。送り先は `#quickbuy-notification` で、DEBUG ビルドからの問い合わせ (`test` が true) はテスト用の `#test-notification` に送る。webhook の URL は Secret Manager の `SLACK_WEBHOOK_URL`・`SLACK_WEBHOOK_URL_TEST` に置き、リポジトリに書かない
- **Firestore のデータベースの場所**: asia-northeast1 (東京)。利用者と運営者が日本にいるため、bannzai/Focus のデータベースと同じ場所。データベースを作った後は場所を変えられない
- **メールアドレスの扱い**: 返信先のメールアドレスは、問い合わせへの返信にだけ使う。Slack の通知に載せ、Functions のログには載せない
- **テスト**: セキュリティルールは Firestore のエミュレータ (`firebase/rules-test/`)、Functions は通知の本文と送り先の選び方の単体のテスト (`firebase/functions/src/contactInquiry.test.ts`) で確かめ、どちらも `.github/workflows/firebase-test.yml` で回す

## Consequences

**良い点:**
- メールアプリの有無にかかわらず、アプリの中から問い合わせを送れる
- 問い合わせにアプリのバージョンと送った人の匿名の ID が付き、運営者は Slack で受け取れる
- bannzai/Focus と同じ作りのため、受け取り方と運用がそろう

**悪い点 / 引き受けるリスク:**
- Firebase のプロジェクト `quickbuy-app-prod` に、Firestore のデータベース・匿名のサインイン・Functions (と、それが使う Cloud Build・Artifact Registry・Secret Manager) が要る。利用量で費用がかかり得る (`documents/DIRECTION.md`「費用」の固定費の上限 0 は、Functions の常駐のインスタンスを持たないことで守る)
- 返信先のメールアドレスと内容を Firestore と Slack に保存するため、プライバシーポリシーと「App のプライバシー」の回答に、その収集を書く
- フォームに書かれた内容は利用者が自由に入れるため、個人情報が書かれることがある。読めるのはルールにより運営者 (Firebase のコンソールと Slack) だけ
