# TestFlight への配布

Quick Buy の iOS アプリを TestFlight (App Store Connect) に上げる手順と決まり。配布の workflow は `.github/workflows/ios-deploy.yml` (castle の ios-deploy-actions skill が生成したもの)。

## 起動

- main へのマージ (push) で自動で起動する
- 配布し直す時だけ、手動で起動する。environment `ios-deploy` がデプロイできるブランチを main に絞っているため、`--ref` は main にする

```sh
gh workflow run ios-deploy.yml -R bannzai/quickbuy --ref main
RUN_ID="$(gh run list -R bannzai/quickbuy --workflow ios-deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch -R bannzai/quickbuy "$RUN_ID"
```

- 配布は同時に 1 本だけ。先に動いている run が終わっていない時は、最初の step (Reject concurrent dispatch) で失敗する

## ビルド番号

`github.run_number + BUILD_NUMBER_OFFSET`。`BUILD_NUMBER_OFFSET` は 0 (2026-11-20 に配布を用意した時点で、App Store Connect に上がったビルドが無かったため)。workflow を作り直して run_number が戻った時は、上がっている最大のビルド番号を超えるように offset を上げる。

## 失敗した run のやり直し

- Upload to TestFlight まで進んで失敗した run は、Re-run しない。原因を直して、新しく起動する (Re-run は run_number が変わらず、上げ済みと同じビルド番号の再送になって拒否される)
- Upload より前の step で失敗した run は、Re-run してよい (その番号はまだ上がっていない)

## 署名

手動署名。Release かつ実機向け (`[sdk=iphoneos*]`) のビルドだけを手動署名にしていて、Debug と simulator 向けのビルドは変えていない。

| ターゲット | bundle ID | provisioning profile | secret |
| --- | --- | --- | --- |
| QuickBuy | `com.bannzai.QuickBuy` | `QuickBuy.AppStore` | `IOS_PROVISIONING_PROFILE_BASE64` |
| QuickBuyWidget | `com.bannzai.QuickBuy.QuickBuyWidget` | `QuickBuy.QuickBuyWidget.AppStore` | `IOS_WIDGET_PROVISIONING_PROFILE_BASE64` |
| QuickBuyShare | `com.bannzai.QuickBuy.QuickBuyShare` | `QuickBuy.QuickBuyShare.AppStore` | `IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_BASE64` |

- profile の名前は、`QuickBuy.xcodeproj/project.pbxproj` の `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]` と、workflow の ExportOptions の両方に一致させる
- 配布の資格情報 (証明書・profile・App Store Connect の API キー) は、environment `ios-deploy` の secret に置く。リポジトリの secret には置かない
- 3 つのターゲットは App Group `group.com.bannzai.QuickBuy` を使う。App Group は Developer Portal に登録して、3 つの App ID に割り当ててある

### profile の再発行

証明書の期限 (2027-01-17) が切れた時や、entitlements を変えた時は、**3 つの profile をまとめて**発行し直し、3 つの secret をすべて更新する。workflow は 3 つとも必須にしているため、1 つだけ直すと残りが古いままで archive が失敗する。

```sh
skill=~/.agents/skills/ios-deploy-actions/scripts
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.AppStore --bundle-id com.bannzai.QuickBuy --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuy/QuickBuy.entitlements --recreate
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.QuickBuyWidget.AppStore --bundle-id com.bannzai.QuickBuy.QuickBuyWidget --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuyWidget/QuickBuyWidget.entitlements --recreate
bash "$skill/signing-assets.sh" create-profile --name QuickBuy.QuickBuyShare.AppStore --bundle-id com.bannzai.QuickBuy.QuickBuyShare --certificate-id 68L9PY6PX2 --out ./tmp/signing --entitlements QuickBuyShare/QuickBuyShare.entitlements --recreate
bash "$skill/register-secrets.sh" --repo bannzai/quickbuy --env ios-deploy \
  --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_AppStore.mobileprovision \
  --secret-base64-file IOS_WIDGET_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_QuickBuyWidget_AppStore.mobileprovision \
  --secret-base64-file IOS_SHARE_EXTENSION_PROVISIONING_PROFILE_BASE64=./tmp/signing/QuickBuy_QuickBuyShare_AppStore.mobileprovision
```

3 つとも `entitlements-check=ok` が出ることを確かめてから secret を更新する。証明書を替えた時は `--certificate-id` を新しい証明書の id にする。

## Firebase の設定ファイル

アプリは `GoogleService-Info.plist` を Resources に持つが、リポジトリには入れていない。workflow は archive の前に、リポジトリの secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` から `scripts/restore-google-service-info-plist.sh` で書き出す。

## 輸出コンプライアンス

アプリ本体の Info.plist に `ITSAppUsesNonExemptEncryption = NO` を入れている (`project.pbxproj` の `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`)。上げたビルドは、App Store Connect の画面で輸出コンプライアンスの質問に答えなくても TestFlight で配れる。

`NO` にした根拠 (2026-11-20 に確かめた):

- アプリのコード (`QuickBuy`・`Shared`・`QuickBuyWidget`・`QuickBuyShare`) を `CryptoKit|CommonCrypto|CCCrypt|SecKey|AES|ChaCha|openssl|libsodium|BoringSSL` で検索して 0 件。アプリは暗号を自分で扱っておらず、通信は `URLSession` の HTTPS だけ
- 依存パッケージは firebase-ios-sdk 13.1.1 (`FirebaseAnalyticsCore`・`FirebaseCrashlytics`) だけ。Firebase の SDK の中身までは調べていない
- Apple の文書「Complying with Encryption Export Regulations」(https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations ) は、OS に組み込まれた暗号の利用 (HTTPS の通信など) だけなら `NO` にすると書いている

独自の暗号や、OS のもの以外の暗号の実装を使う変更を入れる時は、この値を見直す。
