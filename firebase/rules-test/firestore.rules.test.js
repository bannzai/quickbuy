import { readFileSync } from "node:fs";
import { after, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

/** 本番に出すのと同じ `firebase/firestore.rules` を読み込んだ Firestore のエミュレータのテスト環境 */
const testEnvironment = await initializeTestEnvironment({
  projectId: "demo-quickbuy",
  firestore: {
    rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
  },
});

after(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

/**
 * iOS の `sendContactInquiry` が書くのと同じキーで、contactInquiries の文書の中身を作る。
 * @param {string} userID 文書に書く送った人の uid
 * @param {object} overrides 差し替える・足すキーと値。値が undefined のキーは消す
 * @return {object} addDoc に渡す文書の中身
 */
function contactInquiry(userID, overrides = {}) {
  const data = {
    inquiryType: "bug",
    content: "カートインを押しても購入画面が開かない",
    emailAddress: "user@example.com",
    userID,
    appVersion: "1.0.0 (15)",
    test: false,
    createdDateTime: serverTimestamp(),
    ...overrides,
  };
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined) {
      delete data[key];
    }
  }
  return data;
}

/**
 * alice としてサインインした時の Firestore を返す。
 * @return {import("firebase/firestore").Firestore} alice の Firestore
 */
function aliceFirestore() {
  return testEnvironment.authenticatedContext("alice").firestore();
}

describe("contactInquiries の作成", () => {
  it("自分の uid を userID に入れた文書は作れる", async () => {
    await assertSucceeds(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice")));
  });

  it("appVersion の無い文書は作れる (アプリがバージョンを読めない時)", async () => {
    await assertSucceeds(
      addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { appVersion: undefined }))
    );
  });

  it("DEBUG ビルドの印 test が true の文書は作れる", async () => {
    await assertSucceeds(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { test: true })));
  });

  for (const inquiryType of ["feedback", "other"]) {
    it(`種別 ${inquiryType} の文書は作れる`, async () => {
      await assertSucceeds(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { inquiryType })));
    });
  }

  it("内容とメールアドレスが上限の文字数ちょうどの文書は作れる (日本語の文字も 1 文字と数える)", async () => {
    const domain = "@example.com";
    await assertSucceeds(
      addDoc(
        collection(aliceFirestore(), "contactInquiries"),
        contactInquiry("alice", { content: "あ".repeat(10000), emailAddress: "a".repeat(254 - domain.length) + domain })
      )
    );
  });

  it("他人の uid を userID に入れた文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("bob")));
  });

  it("サインインしていなければ作れない", async () => {
    await assertFails(
      addDoc(collection(testEnvironment.unauthenticatedContext().firestore(), "contactInquiries"), contactInquiry("alice"))
    );
  });

  it("決まったキーのほかのキーがある文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { error: "x" })));
  });

  for (const key of ["inquiryType", "content", "emailAddress", "userID", "test", "createdDateTime"]) {
    it(`${key} の無い文書は作れない`, async () => {
      await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { [key]: undefined })));
    });
  }

  it("決まった種別のほかの種別の文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { inquiryType: "bugs" })));
  });

  it("内容が空の文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { content: "" })));
  });

  it("内容が上限を 1 文字超える文書は作れない", async () => {
    await assertFails(
      addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { content: "あ".repeat(10001) }))
    );
  });

  it("メールアドレスが空の文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { emailAddress: "" })));
  });

  it("メールアドレスが上限を 1 文字超える文書は作れない", async () => {
    const domain = "@example.com";
    await assertFails(
      addDoc(
        collection(aliceFirestore(), "contactInquiries"),
        contactInquiry("alice", { emailAddress: "a".repeat(255 - domain.length) + domain })
      )
    );
  });

  it("appVersion が文字列でない文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { appVersion: 15 })));
  });

  it("test が真偽値でない文書は作れない", async () => {
    await assertFails(addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { test: "true" })));
  });

  it("createdDateTime がサーバーの時刻でない文書は作れない", async () => {
    await assertFails(
      addDoc(collection(aliceFirestore(), "contactInquiries"), contactInquiry("alice", { createdDateTime: new Date(0) }))
    );
  });
});

describe("contactInquiries の読み取り・更新・削除", () => {
  beforeEach(async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "contactInquiries", "inquiry-1"), contactInquiry("alice"));
    });
  });

  it("送った本人でも読めない", async () => {
    await assertFails(getDoc(doc(aliceFirestore(), "contactInquiries", "inquiry-1")));
  });

  it("送った本人でも一覧を読めない", async () => {
    await assertFails(getDocs(collection(aliceFirestore(), "contactInquiries")));
  });

  it("送った本人でも更新できない", async () => {
    await assertFails(updateDoc(doc(aliceFirestore(), "contactInquiries", "inquiry-1"), { content: "書き換え" }));
  });

  it("送った本人でも削除できない", async () => {
    await assertFails(deleteDoc(doc(aliceFirestore(), "contactInquiries", "inquiry-1")));
  });

  it("ほかの人は読めない", async () => {
    await assertFails(getDoc(doc(testEnvironment.authenticatedContext("bob").firestore(), "contactInquiries", "inquiry-1")));
  });
});

describe("ほかのパス", () => {
  it("match の無いパスには書けない", async () => {
    await assertFails(setDoc(doc(aliceFirestore(), "favorites", "favorite-1"), { name: "コーヒー豆" }));
  });
});
