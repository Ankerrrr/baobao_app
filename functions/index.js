const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendPartnerNotification = onDocumentCreated(
  "relationships/{rid}/notifications/{nid}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    // 防止重複送
    if (data.sent === true) return;

    const toUid = data.toUid;
    const text = data.text;

    if (!toUid || !text) return;

    // 讀取對方的 FCM token
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(toUid)
      .get();

    const token = userDoc.data()?.fcmToken;
    if (!token) {
      console.log("No FCM token for user:", toUid);
      return;
    }

    // 發送通知
    await admin.messaging().send({
      token,
      notification: {
        title: "💌 來自寶寶的訊息",
        body: text,
      },
      data: {
        type: "baby_message",
        relationshipId: event.params.rid,
      },
    });

    // 標記為已送出（避免重送）
    await snap.ref.update({
      sent: true,
    });

    console.log("Notification sent to", toUid);
  },
);
