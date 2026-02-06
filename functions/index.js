/**
 * Cloud Functions for FCM notifications
 * - 即時送：onCreate
 * - 補救送：scheduler retry
 * - payload：data（Flutter 穩定）
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/* =========================================================
 * ① 即時送通知（最重要）
 * 當 Firestore 新增 notifications/{nid} 時立刻送
 * ========================================================= */
exports.sendNotificationOnCreate = onDocumentCreated(
  "relationships/{rid}/notifications/{nid}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const {
      toUid,
      title = "新訊息",
      text, // ⚠️ 你目前用 text
      sent,
    } = data;

    // 已送過就不處理（避免重複）
    if (sent === true) return;

    if (!toUid || !text) {
      console.log("⛔ skip: missing toUid or text");
      return;
    }

    // 取得對方 token
    const userDoc = await db.collection("users").doc(toUid).get();
    const token = userDoc.get("fcmToken");

    if (!token) {
      console.log("⛔ skip: no fcmToken for", toUid);
      return;
    }

    try {
      await admin.messaging().send({
        token,
        data: {
          title,
          body: text,
        },
        android: {
          priority: "high",
        },
      });

      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("📨 immediate sent:", snap.ref.path);
    } catch (e) {
      console.error("🔥 immediate send failed:", e);
      // ❗ 不設 sent，交給 retry
    }
  },
);

/* =========================================================
 * ② 補救重送（每 5 分鐘）
 * 只處理 sent=false 的
 * ========================================================= */
exports.retryUnsentNotifications = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Taipei",
  },
  async () => {
    console.log("🔁 retry job start");

    const snap = await db
      .collectionGroup("notifications")
      .where("sent", "==", false)
      .where("retryCount", "<", 5)
      .get();

    if (snap.empty) {
      console.log("✅ nothing to retry");
      return;
    }

    for (const doc of snap.docs) {
      const data = doc.data();
      const { toUid, title = "新訊息", text, retryCount = 0 } = data;

      console.log("🔍 retry checking:", doc.ref.path);

      if (!toUid || !text) {
        console.log("⛔ skip: missing toUid or text");
        continue;
      }

      const userDoc = await db.collection("users").doc(toUid).get();
      const token = userDoc.get("fcmToken");

      if (!token) {
        console.log("⛔ skip: no token for", toUid);
        continue;
      }

      try {
        await admin.messaging().send({
          token,
          data: {
            title,
            body: text,
          },
          android: {
            priority: "high",
          },
        });

        await doc.ref.update({
          sent: true,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("✅ retried and sent:", doc.ref.path);
      } catch (e) {
        console.error("⚠ retry failed:", e);

        await doc.ref.update({
          retryCount: retryCount + 1,
          lastTriedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  },
);
