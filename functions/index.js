const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Sends an FCM push whenever a new Notification document is created.
 *
 * Requirements:
 * - Parents_Guardian/{parentGuardianId} contains field: fcmTokens: [token1, token2, ...]
 * - Notification document contains: ParentGuardianID, Message, EmergencySOS
 */
exports.pushOnNotificationCreate = functions.firestore
  .document("Notification/{notificationId}")
  .onCreate(async (snap, context) => {
    const notif = snap.data() || {};
    const parentId = notif.ParentGuardianID;
    const message = notif.Message || "New alert";
    const emergency = notif.EmergencySOS === true;

    console.log("🔔 [FCM CLOUD FUNCTION] New notification detected!");
    console.log("📋 [FCM] Notification ID:", context.params.notificationId);
    console.log("📧 [FCM] Parent ID:", parentId);
    console.log("💬 [FCM] Message:", message);
    console.log("🚨 [FCM] Emergency:", emergency);

    if (!parentId) {
      console.log("❌ [FCM] Missing ParentGuardianID on notification:", context.params.notificationId);
      return null;
    }

    const parentDoc = await admin.firestore().collection("Parents_Guardian").doc(parentId).get();
    const parentData = parentDoc.exists ? parentDoc.data() : null;
    const tokens = (parentData && parentData.fcmTokens) ? parentData.fcmTokens : [];

    console.log("🔍 [FCM] Found", tokens.length, "token(s) for parent");

    if (!Array.isArray(tokens) || tokens.length === 0) {
      console.log("❌ [FCM] No tokens for parent:", parentId);
      console.log("⚠️  [FCM] Make sure the parent app has initialized FCM and saved token!");
      return null;
    }

    const title = emergency ? "🚨 EMERGENCY SOS" : "UBSafeStep Alert";
    console.log("📬 [FCM] Preparing to send notification:", title);

    const payload = {
      notification: {
        title,
        body: message,
      },
      data: {
        route: "alerts",
        notificationId: context.params.notificationId,
        parentGuardianId: String(parentId),
        emergency: emergency ? "true" : "false",
      },
    };

    console.log("🚀 [FCM] Sending notification to", tokens.length, "device(s)...");
    
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      ...payload,
      android: {
        priority: "high",
        notification: {
          channelId: "ub_safestep_alerts",
        },
      },
    });

    console.log("✅ [FCM] Send complete!");
    console.log("📊 [FCM] Success:", res.successCount, "| Failed:", res.failureCount);

    // Clean up invalid tokens
    const invalid = [];
    res.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error && r.error.code;
        if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
          invalid.push(tokens[i]);
        }
      }
    });

    if (invalid.length > 0) {
      console.log("🧹 [FCM] Removing", invalid.length, "invalid token(s)");
      await admin.firestore().collection("Parents_Guardian").doc(parentId).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
      });
    }

    console.log("🎉 [FCM] Notification delivery complete!");
    console.log("═══════════════════════════════════════════════════");
    return null;
  });


