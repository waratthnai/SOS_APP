const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

/**
 * ส่ง FCM push notification จริง เมื่อมี doc ใหม่ใน collection "notifications"
 * (เขียนมาจาก FCMService.sendNotificationToFriend ใน lib/core/fcm_service.dart)
 */
exports.sendFriendMessageNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();

    const message = data.message || "";
    const fromUserId = data.fromUserId || "";
    const toUserId = data.to || "";
    const type = data.type || "friend_message";

    if (!toUserId || !fromUserId) {
      logger.warn("ไม่มี to/fromUserId ใน notification doc, ข้าม", { id: event.params.notificationId });
      return;
    }

    // ดึง fcmToken ของผู้รับ และชื่อผู้ส่งจาก Firestore เอง (ผ่าน admin SDK)
    // แทนที่จะเชื่อ toToken/senderName ที่ client ส่งมา ป้องกันการปลอมแจ้งเตือน
    const [toDoc, fromDoc] = await Promise.all([
      admin.firestore().collection("users").doc(toUserId).get(),
      admin.firestore().collection("users").doc(fromUserId).get(),
    ]);

    const toToken = toDoc.data()?.fcmToken;
    const senderName = fromDoc.data()?.name || "เพื่อน";

    if (!toToken) {
      logger.warn("ผู้รับไม่มี fcmToken, ข้าม", { id: event.params.notificationId });
      return;
    }

    const title = type === "sos" ? "🆘 SOS ฉุกเฉิน" : "💬 ข้อความใหม่";
    const body = type === "sos" ? message : `${senderName}: ${message}`;

    const payload = {
      token: toToken,
      notification: { title, body },
      data: {
        type,
        fromUserId,
        senderName,
        message,
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: { channelId: "chat_messages", sound: "default" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    };

    try {
      await admin.messaging().send(payload);
      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info("ส่ง FCM สำเร็จ", { to: data.to });
    } catch (error) {
      logger.error("ส่ง FCM ไม่สำเร็จ", error);

      // โทเค็นไม่ถูกต้อง/หมดอายุ - ล้างทิ้งเพื่อไม่ให้ลองส่งซ้ำไปเรื่อยๆ
      if (
        error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered"
      ) {
        if (data.to) {
          await admin.firestore().collection("users").doc(data.to).update({
            fcmToken: admin.firestore.FieldValue.delete(),
          });
        }
      }

      await snap.ref.update({
        sent: false,
        error: error.message,
      });
    }
  }
);
