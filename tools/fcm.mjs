#!/usr/bin/env node
// Send through Firebase Cloud Messaging (HTTP v1). The legacy "server key" API was shut down in 2024.
//
//   node tools/fcm.mjs payloads/order-shipped.apns              # alert
//   node tools/fcm.mjs payloads/silent-sync.apns background     # silent
//   node tools/fcm.mjs --print-token                            # OAuth token for Postman
//
// Needs FCM_SERVICE_ACCOUNT (path to the JSON from Firebase ▸ Project settings ▸ Service accounts)
// and FCM_TOKEN (copy it from the Orders tab once Firebase is added).
import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { loadEnv, requireEnv, readPayload, headersFor, root } from "./lib/apns.mjs";

loadEnv();
requireEnv("FCM_SERVICE_ACCOUNT");
const account = JSON.parse(readFileSync(resolve(root, process.env.FCM_SERVICE_ACCOUNT), "utf8"));

/** Service account → short-lived OAuth2 access token (RS256 JWT bearer grant). */
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const signature = createSign("RSA-SHA256").update(unsigned).sign(account.private_key, "base64url");
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${signature}`,
    }),
  });
  const json = await response.json();
  if (!json.access_token) throw new Error(`OAuth failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

if (process.argv.includes("--print-token")) {
  console.log(await accessToken());
  process.exit(0);
}

const [file, type = "alert"] = process.argv.slice(2);
if (!file) {
  console.error("usage: node tools/fcm.mjs <payload file> [alert|marketing|background]");
  process.exit(1);
}
requireEnv("FCM_TOKEN");

// The whole APNs payload goes in apns.payload. FCM passes it through to APNs unchanged,
// so custom keys (orderId, status, image) arrive at the top level on the device.
const apnsHeaders = headersFor(type, "ignored");
delete apnsHeaders["apns-topic"]; // FCM sets the topic from the iOS app you registered
const message = {
  message: {
    token: process.env.FCM_TOKEN,
    apns: { headers: apnsHeaders, payload: readPayload(file) },
  },
};

const response = await fetch(
  `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
  {
    method: "POST",
    headers: { authorization: `Bearer ${await accessToken()}`, "content-type": "application/json" },
    body: JSON.stringify(message),
  },
);
const result = await response.json();
console.log(response.status, JSON.stringify(result, null, 2));
// 200 { name: "projects/…/messages/…" } = accepted by FCM (then FCM hands it to APNs).
// 404 UNREGISTERED → delete this FCM token.
// 401 THIRD_PARTY_AUTH_ERROR → the APNs key uploaded to Firebase is missing or wrong.
