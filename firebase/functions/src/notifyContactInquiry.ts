import { logger } from "firebase-functions";
import { defineSecret, projectID } from "firebase-functions/params";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { ContactInquirySchema, contactInquiryMessage, contactInquiryWebhookURL } from "./contactInquiry";

/** `#quickbuy-notification` 宛ての Incoming Webhook の URL (Secret Manager に置く) */
const slackWebhookURL = defineSecret("SLACK_WEBHOOK_URL");
/** bannzai のプロジェクト共通のテスト用チャンネル `#test-notification` 宛ての Incoming Webhook の URL (Secret Manager に置く) */
const slackWebhookURLTest = defineSecret("SLACK_WEBHOOK_URL_TEST");

/**
 * お問い合わせの文書が作られた時に、その内容を Slack に 1 件投稿する。
 * 形の合わない文書は投稿せずにログに残して終える。投稿に失敗した時は throw し、関数の失敗として Cloud Logging に残す
 * (再試行はしない。再試行を有効にすると、Slack が受け取ってから応答が失敗した時に同じ通知が 2 回届くため)。
 * リージョンは Firestore のデータベースと同じ asia-northeast1 (ADR 0004)。
 */
export const notifyContactInquiry = onDocumentCreated(
  {
    document: "contactInquiries/{contactInquiryID}",
    region: "asia-northeast1",
    secrets: [slackWebhookURL, slackWebhookURLTest],
  },
  async (event) => {
    const result = ContactInquirySchema.safeParse(event.data?.data());
    if (!result.success) {
      // 文書の中身はメールアドレスと内容を含むため、ログには文書の ID と形の誤りだけを残す
      logger.error("contact inquiry has unexpected shape", {
        contactInquiryID: event.params.contactInquiryID,
        issues: result.error.issues.map((issue) => ({ path: issue.path, code: issue.code })),
      });
      return;
    }
    const response = await fetch(
      contactInquiryWebhookURL(result.data.test, { production: slackWebhookURL.value(), test: slackWebhookURLTest.value() }),
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: contactInquiryMessage(result.data, event.params.contactInquiryID, projectID.value()) }),
      }
    );
    if (!response.ok) {
      throw new Error(`Slack webhook responded ${response.status} for contact inquiry ${event.params.contactInquiryID}`);
    }
    logger.info("contact inquiry notified", { contactInquiryID: event.params.contactInquiryID, test: result.data.test });
  }
);
