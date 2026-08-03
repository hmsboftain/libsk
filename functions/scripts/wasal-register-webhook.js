"use strict";

// Registers the deployed wasalWebhook Cloud Function with Wasal and prints
// the webhook secret — SHOWN ONLY ONCE, store it immediately:
//
//   firebase functions:secrets:set WASAL_WEBHOOK_SECRET
//
// Usage (use pk_live_ — the sandbox never fires webhooks):
//
//   WASAL_API_KEY=pk_live_xxx WEBHOOK_URL=https://us-central1-libsk-b68f5.cloudfunctions.net/wasalWebhook \
//     node scripts/wasal-register-webhook.js
//
// Re-running lists existing webhooks first so you don't register duplicates.

const { createWasalClient } = require("../wasal");

const API_KEY = process.env.WASAL_API_KEY || "";
const URL = process.env.WEBHOOK_URL || "";

async function main() {
  if (!API_KEY) {
    console.error("Set WASAL_API_KEY (pk_live_ — sandbox never fires webhooks).");
    process.exit(1);
  }
  const client = createWasalClient(API_KEY);

  const existing = await client.listWebhooks();
  const list = existing.list || existing.webhooks || [];
  if (list.length > 0) {
    console.log("Existing webhooks:");
    for (const w of list) {
      console.log(`  ${w._id}  active=${w.active}  ${w.url}  [${(w.events || []).join(", ")}]`);
    }
    if (list.some((w) => w.url === URL)) {
      console.log("\nThis URL is already registered — nothing to do.");
      console.log("(The secret is only shown at creation. If you lost it, delete and re-register.)");
      return;
    }
  }

  if (!URL.startsWith("https://")) {
    console.error("Set WEBHOOK_URL to the deployed wasalWebhook HTTPS URL.");
    process.exit(1);
  }

  const created = await client.registerWebhook({ url: URL });
  const webhook = created.webhook;
  console.log(`\nWebhook registered: ${webhook._id}`);
  console.log(`Events: ${(webhook.events || []).join(", ") || "all"}`);
  console.log("\n=== WEBHOOK SECRET (shown ONCE — store it now) ===");
  console.log(webhook.secret);
  console.log("==================================================");
  console.log("\nNow run:  firebase functions:secrets:set WASAL_WEBHOOK_SECRET");
  console.log("paste the secret above, then redeploy:  firebase deploy --only functions");
}

main().catch((e) => {
  console.error("Failed:", e.message, e.code ? `(${e.code})` : "");
  process.exit(1);
});
