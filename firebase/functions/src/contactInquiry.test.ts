import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ContactInquiry, ContactInquirySchema, contactInquiryMessage, contactInquiryWebhookURL } from "./contactInquiry";

/** iOS の `sendContactInquiry` が書くのと同じキーの文書の中身 (送った時刻を含む) */
const documentData = {
  inquiryType: "bug",
  content: "カートインを押しても購入画面が開かない\n2 回目から",
  emailAddress: "user@example.com",
  userID: "uid-1",
  appVersion: "1.0.0 (15)",
  test: false,
  createdDateTime: new Date(0),
};

describe("ContactInquirySchema", () => {
  it("アプリが書く文書を読める (送った時刻は読まずに捨てる)", () => {
    assert.deepEqual(ContactInquirySchema.parse(documentData), {
      inquiryType: "bug",
      content: "カートインを押しても購入画面が開かない\n2 回目から",
      emailAddress: "user@example.com",
      userID: "uid-1",
      appVersion: "1.0.0 (15)",
      test: false,
    });
  });

  it("appVersion の無い文書を読める", () => {
    assert.equal(ContactInquirySchema.parse({ ...documentData, appVersion: undefined }).appVersion, undefined);
  });

  it("決まった種別のほかの種別の文書は読まない", () => {
    assert.equal(ContactInquirySchema.safeParse({ ...documentData, inquiryType: "bugs" }).success, false);
  });

  it("test の無い文書は読まない", () => {
    assert.equal(ContactInquirySchema.safeParse({ ...documentData, test: undefined }).success, false);
  });

  it("文書が無い時は読まない", () => {
    assert.equal(ContactInquirySchema.safeParse(undefined).success, false);
  });
});

describe("contactInquiryMessage", () => {
  /** 上の文書を読んだ問い合わせ */
  const inquiry: ContactInquiry = ContactInquirySchema.parse(documentData);

  it("種別・返信先・送った人・バージョン・コンソールの URL・内容を 1 つの本文にする", () => {
    assert.equal(
      contactInquiryMessage(inquiry, "inquiry-1", "quickbuy-app-prod"),
      [
        "📬 新しいお問い合わせ",
        "",
        "[種別] バグ・不具合",
        "[返信先] user@example.com",
        "[UserID] uid-1",
        "[AppVersion] 1.0.0 (15)",
        "[Firestore] https://console.firebase.google.com/project/quickbuy-app-prod/firestore/databases/-default-/data/~2FcontactInquiries~2Finquiry-1",
        "",
        "━━━━━━━━━━━━━━━━━━━━",
        "カートインを押しても購入画面が開かない\n2 回目から",
        "━━━━━━━━━━━━━━━━━━━━",
      ].join("\n")
    );
  });

  it("種別ごとに、アプリの選択肢と同じ名前を出す", () => {
    assert.match(contactInquiryMessage({ ...inquiry, inquiryType: "feedback" }, "i", "p"), /^\[種別\] ご意見・ご要望$/m);
    assert.match(contactInquiryMessage({ ...inquiry, inquiryType: "other" }, "i", "p"), /^\[種別\] その他$/m);
  });

  it("バージョンが無い時は不明と出す", () => {
    assert.match(contactInquiryMessage({ ...inquiry, appVersion: undefined }, "i", "p"), /^\[AppVersion\] 不明$/m);
  });
});

describe("contactInquiryWebhookURL", () => {
  /** 本番とテスト用の webhook の URL */
  const webhookURLs = { production: "https://hooks.slack.com/services/production", test: "https://hooks.slack.com/services/test" };

  it("DEBUG ビルドからの問い合わせはテスト用のチャンネルに送る", () => {
    assert.equal(contactInquiryWebhookURL(true, webhookURLs), "https://hooks.slack.com/services/test");
  });

  it("それ以外は本番のチャンネルに送る", () => {
    assert.equal(contactInquiryWebhookURL(false, webhookURLs), "https://hooks.slack.com/services/production");
  });
});
