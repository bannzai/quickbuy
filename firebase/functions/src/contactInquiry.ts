import { z } from "zod";

/**
 * Firestore の `contactInquiries/{contactInquiryID}` の文書のうち、Slack の通知に使うキーの形。
 * 書くのはアプリの `QuickBuy/ContactFormView.swift` の `sendContactInquiry` で、キーと値の決まりは `firebase/firestore.rules` が正。
 * 送った時刻 `createdDateTime` は通知に出さないため読まない。
 */
export const ContactInquirySchema = z.object({
  /** 問い合わせの種別。値の並びは `QuickBuy/ContactInquiry.swift` の `ContactInquiryType` と同じ */
  inquiryType: z.enum(["bug", "feedback", "other"]),
  /** 利用者が書いた内容 */
  content: z.string(),
  /** 返信先のメールアドレス。運営者が返信する時にだけ使う */
  emailAddress: z.string(),
  /** 送った人の Firebase Auth の匿名の uid */
  userID: z.string(),
  /** 送ったアプリのバージョン (例: `1.0.0 (15)`)。アプリが読めなかった時は無い */
  appVersion: z.string().optional(),
  /** アプリの DEBUG ビルドから送った時に true。通知をテスト用のチャンネルに送る */
  test: z.boolean(),
});

/** Slack に通知する問い合わせ 1 件 */
export type ContactInquiry = z.infer<typeof ContactInquirySchema>;

/** 種別ごとの、通知に出す日本語の名前。アプリのフォームの選択肢の名前 (`ContactInquiryType.title`) と同じ */
const inquiryTypeLabels: Record<ContactInquiry["inquiryType"], string> = {
  bug: "バグ・不具合",
  feedback: "ご意見・ご要望",
  other: "その他",
};

/**
 * 問い合わせ 1 件を Slack に投稿する本文にして返す。
 * 本文はメールアドレスと内容を含むため、ログに出さない。
 * @param inquiry 問い合わせの文書の中身
 * @param contactInquiryID 文書の ID。Firebase のコンソールで文書を開く URL に使う
 * @param projectID 文書のある Firebase のプロジェクトの ID
 * @return Slack の投稿の本文 (Incoming Webhook の `text`)
 */
export function contactInquiryMessage(inquiry: ContactInquiry, contactInquiryID: string, projectID: string): string {
  return [
    "📬 新しいお問い合わせ",
    "",
    `[種別] ${inquiryTypeLabels[inquiry.inquiryType]}`,
    `[返信先] ${inquiry.emailAddress}`,
    `[UserID] ${inquiry.userID}`,
    `[AppVersion] ${inquiry.appVersion ?? "不明"}`,
    // コンソールの URL はパスの `/` を `~2F` にした形 (Firebase のコンソールで文書を開いた時のアドレスバーの形)
    `[Firestore] https://console.firebase.google.com/project/${projectID}/firestore/databases/-default-/data/~2FcontactInquiries~2F${contactInquiryID}`,
    "",
    "━━━━━━━━━━━━━━━━━━━━",
    inquiry.content,
    "━━━━━━━━━━━━━━━━━━━━",
  ].join("\n");
}

/**
 * 通知を送る Incoming Webhook の URL を選ぶ。
 * DEBUG ビルドからの問い合わせ (`test` が true) はテスト用のチャンネル `#test-notification`、それ以外は `#quickbuy-notification` に送る
 * (決まりは bannzai/castle の `home/.claude/documents/rules/slack-test-notification-channel.md`)。
 * @param test 問い合わせの `test`
 * @param webhookURLs 本番 (`production`) とテスト用 (`test`) の webhook の URL
 * @return 送り先の webhook の URL
 */
export function contactInquiryWebhookURL(test: boolean, webhookURLs: { production: string; test: string }): string {
  return test ? webhookURLs.test : webhookURLs.production;
}
