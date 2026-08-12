const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

const admin = require("firebase-admin");

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
});

exports.sendNotificationPush = onDocumentCreated(
    "users/{userId}/notifications/{notificationId}",
    async (event) => {
      const snapshot = event.data;

      if (!snapshot) {
        logger.warn("Notification document has no data.");
        return;
      }

      const notificationData = snapshot.data();

      const userId = event.params.userId;

      const title =
        notificationData.title || "SplitUP";

      const body =
        notificationData.message ||
        "You have a new SplitUP update.";

      try {
        const userDocument = await admin
            .firestore()
            .collection("users")
            .doc(userId)
            .get();

        if (!userDocument.exists) {
          logger.warn(
              `User document not found for ${userId}`,
          );
          return;
        }

        const userData = userDocument.data() || {};

        const notificationsEnabled =
          userData.notificationsEnabled !== false;

        if (!notificationsEnabled) {
          logger.info(
              `Notifications disabled for ${userId}`,
          );
          return;
        }

        const rawTokens = userData.fcmTokens;

        const tokens = Array.isArray(rawTokens) ?
          rawTokens.filter(
              (token) =>
                typeof token === "string" &&
                token.trim().length > 0,
          ) :
          [];

        if (tokens.length === 0) {
          logger.info(
              `No FCM tokens found for ${userId}`,
          );
          return;
        }

        const data = {
          type: notificationData.type ?
            notificationData.type.toString() : "",

          groupId: notificationData.groupId ?
            notificationData.groupId.toString() : "",

          expenseId: notificationData.expenseId ?
            notificationData.expenseId.toString() : "",

          settlementId: notificationData.settlementId ?
            notificationData.settlementId.toString() : "",

          notificationId:
            event.params.notificationId,
        };

        const message = {
          notification: {
            title,
            body,
          },

          data,

          android: {
            priority: "high",
            notification: {
              channelId:
                "splitup_high_importance",
              sound: "default",
            },
          },

          tokens,
        };

        const response = await admin
            .messaging()
            .sendEachForMulticast(message);

        logger.info(
            `Push result for ${userId}`,
            {
              successCount:
                response.successCount,
              failureCount:
                response.failureCount,
            },
        );

        const invalidTokens = [];

        response.responses.forEach(
            (result, index) => {
              if (result.success) {
                return;
              }

              const errorCode =
                result.error ?
                  result.error.code || "" :
                  "";

              logger.warn(
                  "FCM delivery failure",
                  {
                    userId,
                    token: tokens[index],
                    errorCode,
                  },
              );

              if (
                errorCode ===
                  "messaging/registration-token-not-registered" ||
                errorCode ===
                  "messaging/invalid-registration-token"
              ) {
                invalidTokens.push(
                    tokens[index],
                );
              }
            },
        );

        if (invalidTokens.length > 0) {
          await admin
              .firestore()
              .collection("users")
              .doc(userId)
              .update({
                fcmTokens:
                  admin.firestore
                      .FieldValue
                      .arrayRemove(
                          ...invalidTokens,
                      ),
              });

          logger.info(
              "Removed invalid FCM tokens",
              {
                userId,
                count:
                  invalidTokens.length,
              },
          );
        }
      } catch (error) {
        logger.error(
            "Unable to send SplitUP push notification",
            error,
        );
      }
    },
);

