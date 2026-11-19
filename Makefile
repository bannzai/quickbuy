XCODEPROJ := QuickBuy.xcodeproj
SCHEME := QuickBuy
CONFIGURATION := Debug
DERIVED_DATA := tmp/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/QuickBuy.app
IOS_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/QuickBuy.app
BUNDLE_ID := com.bannzai.QuickBuy
# Firebase の設定ファイル。リポジトリに入れない (.gitignore) ため、手元に無ければ Firebase CLI で書き出す
# (手順: firebase-project-setup skill「アプリの Firebase 設定ファイル」。CI は scripts/restore-google-service-info-plist.sh で secret から書き出す)
FIREBASE_PROJECT := quickbuy-app-prod
FIREBASE_IOS_APP_ID := 1:916145290189:ios:6052f313a11d7b2736e284
GOOGLE_SERVICE_INFO_PLIST := QuickBuy/GoogleService-Info.plist
SIMULATOR_UDID ?= $(shell SCRIPT_QUIET=1 sim-boot | sed -n 's/^DEVICE_UDID=//p' | tail -n 1)
DESTINATION ?= platform=iOS Simulator,id=$(SIMULATOR_UDID)

.PHONY: build-ios device install-device ios test clean

$(GOOGLE_SERVICE_INFO_PLIST):
	firebase apps:sdkconfig IOS $(FIREBASE_IOS_APP_ID) --project $(FIREBASE_PROJECT) --out $@

# Simulator 向けビルド。generic destination なら simulator の起動なしでビルドできる
build-ios: $(GOOGLE_SERVICE_INFO_PLIST)
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# 実機向けビルド。code signing が必要なため、provisioning profile の自動生成とこの Mac へのデバイス登録を CLI から行えるようにする
device: $(GOOGLE_SERVICE_INFO_PLIST)
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# 実機ビルドを実機にインストールして起動する。インストール先の解決順: DEVICE 変数 (名前 / UDID) > 環境変数 IOS_DEVICE_UDID > devicectl の JSON から実機を自動解決
# devicectl は起動中の simulator も一覧に載せるため、先に実機 (reality == physical) に絞る。実機が 1 台ならそれ、複数台なら接続中の 1 台。決められなければ指定を求める
install-device: device
	@set -e; \
	mkdir -p tmp; \
	device="$(DEVICE)"; \
	[ -n "$$device" ] || device="$(IOS_DEVICE_UDID)"; \
	if [ -z "$$device" ]; then \
		xcrun devicectl list devices --json-output tmp/devices.json > /dev/null; \
		device=$$(jq -r '[.result.devices[] | select(.hardwareProperties.reality == "physical")] | if length == 1 then .[0] else (map(select(.connectionProperties.tunnelState == "connected")) | if length == 1 then .[0] else empty end) end | .identifier // empty' tmp/devices.json); \
	fi; \
	[ -n "$$device" ] || { echo "Error: 実機が見つかりません (IOS_DEVICE_UDID を export するか DEVICE=<名前|UDID> で指定してください)" >&2; exit 1; }; \
	xcrun devicectl device install app --device "$$device" "$(IOS_APP)"; \
	xcrun devicectl device process launch --device "$$device" $(BUNDLE_ID)

# Simulator 向けビルドを sim-boot で起動したプロジェクト固有の simulator にインストールして起動する
ios: build-ios
	@set -e; \
	simulator_udid="$(SIMULATOR_UDID)"; \
	[ -n "$$simulator_udid" ] || { echo "Error: sim-boot で simulator を解決できません (sim-boot が PATH にあるか確認するか、SIMULATOR_UDID=<UDID> を指定してください)" >&2; exit 1; }; \
	xcrun simctl install "$$simulator_udid" $(APP); \
	xcrun simctl launch "$$simulator_udid" $(BUNDLE_ID)

test: $(GOOGLE_SERVICE_INFO_PLIST)
	@set -e; \
	destination="$(DESTINATION)"; \
	[ -n "$$destination" ] && [ "$$destination" != "platform=iOS Simulator,id=" ] || { echo "Error: sim-boot で simulator を解決できません (sim-boot が PATH にあるか確認するか、DESTINATION='<destination>' または SIMULATOR_UDID=<UDID> を指定してください)" >&2; exit 1; }; \
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) -destination "$$destination" CODE_SIGNING_ALLOWED=NO test

clean:
	rm -rf $(DERIVED_DATA)

# 引数なしの make で ios を実行する (人が手で動作確認するための入口。検査・テストは CI が行う)
.DEFAULT_GOAL := ios

# build-ios と test は同じ DerivedData を使うため、-j 指定でも並列に起動させない (各 target は xcodebuild 1 本で、make 側の並列化で速くなるものは無い)
.NOTPARALLEL:
