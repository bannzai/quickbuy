# TestFlight への配布

Quick Buy の iOS アプリを TestFlight (App Store Connect) に上げる手順と決まり。配布の workflow は `.github/workflows/ios-deploy.yml` (castle の ios-deploy-actions skill が生成したもの)。

## 起動

- main へのマージ (push) で自動で起動する
- 配布し直す時だけ、手動で起動する。environment `ios-deploy` がデプロイできるブランチを main に絞っているため、`--ref` は main にする

```sh
gh workflow run ios-deploy.yml -R bannzai/quickbuy --ref main
gh run list -R bannzai/quickbuy --workflow ios-deploy.yml --event workflow_dispatch --limit 3
gh run watch -R bannzai/quickbuy <上の一覧で、今起動した run の ID>
```

- 起動してから run が一覧に出るまでに数秒の遅れがある。一覧の作成の時刻を見て、今起動した run を選ぶ (先頭が前の run のことがある)
- 配布は同時に 1 本だけ。先に動いている run が終わっていない時は、最初の step (Reject concurrent dispatch) で失敗する。main へのマージが続いて、push で起動した run がこの理由で失敗した時は、先の run が終わってから上のコマンドで手動で起動し直す (そのままでは最新の main が上がらない)
- IPA は artifact に残さない (このリポジトリは public で、artifact は誰でも取得できるため)。上がったビルドは App Store Connect で確かめる

## テスター

TestFlight の内部グループ「App Store Connect Users」(すべてのビルドにアクセスできる設定。同じチームのほかのアプリと同じ名前) に owner を入れてある。上がったビルドは、処理が終わると内部グループのテスターの TestFlight アプリに出る。外部のテスターへの配布 (Apple のベータ版の審査が要る) は設定していない。

## ビルド番号

`github.run_number + BUILD_NUMBER_OFFSET`。`BUILD_NUMBER_OFFSET` は 0 (2026-11-20 に配布を用意した時点で、App Store Connect に上がったビルドが無かったため)。workflow を作り直して run_number が戻った時は、上がっている最大のビルド番号を超えるように offset を上げる。

## 失敗した run のやり直し

- Upload to TestFlight まで進んで失敗した run は、Re-run しない。原因を直して、新しく起動する (Re-run は run_number が変わらず、上げ済みと同じビルド番号の再送になって拒否される)
- Upload より前の step で失敗した run は、その後に新しい run がビルドを上げていない時だけ Re-run してよい (その番号はまだ上がっていない)。後から起動した run が同じバージョンのビルドを上げた後は、Re-run せず新しく起動する (Re-run は古い run_number のままで、上がっているビルド番号より小さくなって拒否される)

## 署名

手動署名。Release かつ実機向け (`[sdk=iphoneos*]`) のビルドだけを手動署名にしていて、Debug と simulator 向けのビルドは変えていない。

Release の実機向けのビルドは配布専用になる。App Store 用の profile の無い Mac では署名で止まり、profile があっても Apple Distribution の署名のため実機には入らない。実機での開発の実行は Debug (自動署名) で行う。Xcode の Profile アクション (既定は Release) を実機で使う時は、Scheme の構成を一時的に Debug に変える。

| ターゲット | bundle ID | provisioning profile | secret |
| --- | --- | --- | --- |
| QuickBuy | `com.bannzai.QuickBuy` | `QuickBuy.AppStore` | `IOS_PROVISIONING_PROFILE_BASE64` |
| QuickBuyWidget | `com.bannzai.QuickBuy.QuickBuyWidget` | `QuickBuy.QuickBuyWidget.AppStore` | `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` |
| QuickBuyShare | `com.bannzai.QuickBuy.QuickBuyShare` | `QuickBuy.QuickBuyShare.AppStore` | `IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_BASE64` |

- profile の名前は、`QuickBuy.xcodeproj/project.pbxproj` の `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]` と、workflow の ExportOptions の両方に一致させる
- 配布の資格情報 (証明書・profile・App Store Connect の API キー) は、environment `ios-deploy` の secret に置く。リポジトリの secret には置かない
- 3 つのターゲットは App Group `group.com.bannzai.QuickBuy` を使う。App Group は Developer Portal に登録して、3 つの App ID に割り当ててある

### profile の再発行

entitlements を変えた時 (証明書は有効なまま) は、**3 つの profile をまとめて**発行し直し、3 つの secret をすべて更新する。entitlements を変えたターゲットの profile が古いままだと、署名で entitlements が合わずに archive が失敗する。3 つのターゲットは同じ App Group を使うので、変えたターゲットだけを選ばず、まとめて発行し直す。

証明書の期限 (2027-01-17) が切れた時は、profile の再発行だけでは直らない。先に、有効な配布証明書の `.p12` とパスワードで secret `IOS_P12_CERTIFICATE_BASE64`・`IOS_P12_PASSWORD` を更新し (証明書はチームで 1 枚を全プロジェクトで使い回している。新しい証明書の用意と原本の保管は、castle の ios-deploy-actions skill の「署名アセットを用意する」に従う)、その証明書の id を下の `--certificate-id` に渡して 3 つの profile を発行し直す。

```sh
skill=~/.agents/skills/ios-deploy-actions/scripts
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.AppStore --bundle-id com.bannzai.QuickBuy --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuy/QuickBuy.entitlements --recreate
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.QuickBuyWidget.AppStore --bundle-id com.bannzai.QuickBuy.QuickBuyWidget --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuyWidget/QuickBuyWidget.entitlements --recreate
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.QuickBuyShare.AppStore --bundle-id com.bannzai.QuickBuy.QuickBuyShare --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuyShare/QuickBuyShare.entitlements --recreate
```

3 つとも `entitlements-check=ok` が出ることを確かめてから、secret を更新する。

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/quickbuy --env ios-deploy \
  --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_AppStore.mobileprovision \
  --secret-base64-file IOS_WIDGET_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_QuickBuyWidget_AppStore.mobileprovision \
  --secret-base64-file IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_QuickBuyShare_AppStore.mobileprovision
```

## Firebase の設定ファイル

アプリは `GoogleService-Info.plist` を Resources に持つが、リポジトリには入れていない。workflow は archive の前に、リポジトリの secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` から `scripts/restore-google-service-info-plist.sh` で書き出す。

## 輸出コンプライアンス

アプリ本体の Info.plist に `ITSAppUsesNonExemptEncryption = NO` を入れている (`project.pbxproj` の `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`)。Apple の文書 (下の出典) は、このキーを Info.plist に書くと、App Store Connect の輸出コンプライアンスの質問を省けると書いている。最初の配布 (2026-11-20。ビルド 1。 https://github.com/bannzai/quickbuy/actions/runs/44753591393 ) で、質問に答えずに TestFlight で配れる状態になることを確かめた: App Store Connect API のビルドが `processingState=VALID`・`usesNonExemptEncryption=false`・内部の配布の状態 `READY_FOR_BETA_TESTING` になった。拡張のターゲットにはキーを入れていない (入れなくてもこの結果になった)。

`NO` にした根拠 (2026-11-20 に確かめた):

- アプリのコード (`QuickBuy`・`Shared`・`QuickBuyWidget`・`QuickBuyShare`) を `CryptoKit|CommonCrypto|CCCrypt|SecKey|AES|ChaCha|openssl|libsodium|BoringSSL` で検索して 0 件。アプリは暗号を自分で扱っておらず、通信は `URLSession` の HTTPS だけ
- 依存パッケージは firebase-ios-sdk 13.1.1 (`FirebaseAnalyticsCore`・`FirebaseCrashlytics`) だけ。Firebase の SDK の中身までは調べていない
- Apple の文書「Complying with Encryption Export Regulations」(https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations ) は、OS に組み込まれた暗号の利用 (HTTPS の通信など) だけなら `NO` にすると書いている

独自の暗号や、OS のもの以外の暗号の実装を使う変更を入れる時は、この値を見直す。
