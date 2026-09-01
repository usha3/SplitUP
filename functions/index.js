const {onCall, HttpsError} = require("firebase-functions/v2/https");

exports.parseReceiptWithAI = onCall(
    {
      region: "us-central1",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to scan a receipt.",
        );
      }

      const data = request.data || {};

      const rawText =
          typeof data.rawText === "string" ?
              data.rawText.trim() :
              "";

      if (!rawText) {
        throw new HttpsError(
            "invalid-argument",
            "Receipt OCR text is required.",
        );
      }

      return {
        success: true,
        message: "AI receipt function is connected.",
        rawTextLength: rawText.length,
      };
    },
);
