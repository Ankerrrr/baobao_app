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
    const { toUid, title = "新訊息", text, sent } = data;

    if (sent === true) return;
    if (!toUid || !text) {
      console.log("⛔ skip: missing toUid or text");
      return;
    }

    // ⭐ 取得 relationshipId（就是路徑裡的 rid）
    const relationshipId = event.params.rid;

    const userDoc = await db.collection("users").doc(toUid).get();
    const token = userDoc.get("fcmToken");
    if (!token) {
      console.log("⛔ skip: no fcmToken for", toUid);
      return;
    }

    try {
      await admin.messaging().send({
        token,

        // ✅ 背景 / 關閉 App → Android 會自動顯示
        notification: {
          title,
          body: text,
        },

        // ✅ 點擊後 Flutter 用來導頁
        data: {
          relationshipId,
          type: "message",
        },

        android: {
          priority: "high",
          notification: {
            channelId: "baby_channel",
            visibility: "public",
            sound: "default",
          },
        },
      });

      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("📨 immediate sent:", snap.ref.path);
    } catch (e) {
      console.error("🔥 immediate send failed:", e);
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

      if (!toUid || !text) continue;

      // ⭐ 從路徑反推出 relationshipId
      const relationshipId = doc.ref.parent.parent.id;

      const userDoc = await db.collection("users").doc(toUid).get();
      const token = userDoc.get("fcmToken");
      if (!token) continue;

      try {
        await admin.messaging().send({
          token,

          notification: {
            title,
            body: text,
          },

          data: {
            relationshipId,
            type: "message",
          },

          android: {
            priority: "high",
            notification: {
              channelId: "baby_channel", // ⭐ 關鍵！！
              visibility: "public",
              sound: "default",
            },
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

exports.sendDailyCountdownNotifications = onSchedule(
  {
    schedule: "0 8 * * *", // 每天 08:00
    // schedule: "*/2 * * * *",
    timeZone: "Asia/Taipei",
  },
  async () => {
    console.log("⏰ daily countdown job start");

    const now = new Date();

    // 撈所有 relationships（資料量不大時 OK）
    const snap = await db.collection("relationships").get();
    if (snap.empty) {
      console.log("ℹ️ no relationships");
      return;
    }
    const TITLE_POOL = [
      "撐著點兄弟 ",
      "加油!",
      "就快到ㄌ",
      "ㄟㄟ",
      "快來我這裡",
      "嘿嘿",
    ];

    const BODY_POOL = {
      far: [
        "距離「{title}」還有 {days} 天，慢來即可",
        "{days} 天後就是「{title}」，好臍帶",
        "這邊提醒你一下，「{title}」還有 {days} 天",
        "「{title}」在不來，就要扁掉了，還有 {days} 天",
      ],
      mid: [
        "再 {days} 天就是「{title}」了 ",
        "「{title}」痾痾 {days}天 撐著點",
        "「{title}」 is close，剩 {days} 天 (興奮到飛起)",
      ],
      near: [
        "{title}只剩 {days} 天了，撐住",
        "{days} 天… 越來越近了，好臍帶",
        "那是一個美好的日子，花兒綻放著，鳥兒在鳴叫，在這樣的日子裡{title} 只剩 {days}天",
      ],
      last: [
        "{title} 只剩 {days} 天?? ㄟ就是明天!",
        "{title} is tommorow，我準備好ㄌ",
      ],
      today: ["今天就是「{title}」的日子了 耶比!!"],
    };

    function pickCountdownText(eventTitle, remainDays, seedKey) {
      const title = TITLE_POOL[Math.abs(hashCode(seedKey)) % TITLE_POOL.length];

      let pool;

      if (remainDays <= 0) {
        pool = BODY_POOL.today;
      } else if (remainDays <= 1) {
        pool = BODY_POOL.last;
      } else if (remainDays <= 5) {
        pool = BODY_POOL.near;
      } else if (remainDays <= 10) {
        pool = BODY_POOL.mid;
      } else {
        pool = BODY_POOL.far;
      }

      const template =
        pool[Math.abs(hashCode(seedKey + remainDays)) % pool.length];

      const body = template
        .replace("{title}", eventTitle ?? "活動")
        .replace("{days}", remainDays);

      return { title, body };
    }

    function hashCode(str) {
      let hash = 0;
      for (let i = 0; i < str.length; i++) {
        hash = (hash << 5) - hash + str.charCodeAt(i);
        hash |= 0;
      }
      return hash;
    }
    function calcRemainDays(targetAt) {
      const now = new Date();

      // 今天 00:00（local）
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

      // 目標日 00:00（local）
      const targetDay = new Date(
        targetAt.getFullYear(),
        targetAt.getMonth(),
        targetAt.getDate(),
      );

      const diffMs = targetDay.getTime() - Date.now();
      const diffDays = Math.max(0, Math.floor(diffMs / 86400000));

      return Math.max(0, diffDays);
    }

    for (const doc of snap.docs) {
      const data = doc.data();
      const countdown = data.countdown;

      if (!countdown) continue;
      if (countdown.enabled !== true) continue;
      if (countdown.notifyEnabled !== true) continue;
      if (!countdown.targetAt) continue;

      const targetAt = countdown.targetAt.toDate();

      const remainDays = calcRemainDays(targetAt);

      const seedKey = `${doc.id}_${new Date().toDateString()}`;
      const { title, body } = pickCountdownText(
        countdown.eventTitle,
        remainDays,
        seedKey,
      );
      // ===== 取得雙方 UID =====
      const [uidA, uidB] = doc.id.split("_");

      for (const uid of [uidA, uidB]) {
        const userDoc = await db.collection("users").doc(uid).get();
        const token = userDoc.get("fcmToken");
        if (!token) continue;

        try {
          await admin.messaging().send({
            token,
            notification: {
              title,
              body,
            },
            data: {
              type: "countdown",
              relationshipId: doc.id,
            },
            android: {
              priority: "high",
              notification: {
                channelId: "baby_channel",
                sound: "default",
              },
            },
          });

          console.log(`📤 countdown sent to ${uid}`);
        } catch (e) {
          console.error(`🔥 countdown send failed to ${uid}`, e);
        }
      }
    }

    console.log("✅ daily countdown job end");
  },
);
