#!/usr/bin/env node
// Checks your APNs key before you have a device: sends to a made-up device token.
//   node tools/check-key.mjs
//
//   400 BadDeviceToken        APNs accepted your key and Team ID, then rejected the fake token. Good.
//   403 InvalidProviderToken  KEY_ID, TEAM_ID or the .p8 file is wrong, or the key was revoked.
//   TLS / certificate error   this machine doesn't trust the APNs server certificate.
//
// It can't check BUNDLE_ID: APNs rejects the fake token before it looks at the topic.
import { loadEnv, requireEnv, makeJWT, sendToAPNs } from "./lib/apns.mjs";

loadEnv();
requireEnv("TEAM_ID", "KEY_ID", "KEY_PATH", "BUNDLE_ID");
const jwt = makeJWT({ teamId: process.env.TEAM_ID, keyId: process.env.KEY_ID, keyPath: process.env.KEY_PATH });
const fakeToken = "0".repeat(64);

for (const env of ["sandbox", "production"]) {
  try {
    const { status, reason } = await sendToAPNs({
      deviceToken: fakeToken,
      payload: { aps: { alert: "key check" } },
      env,
      bundleId: process.env.BUNDLE_ID,
      jwt,
    });
    const verdict =
      reason === "BadDeviceToken" ? "✓ key accepted"
      : reason === "InvalidProviderToken" ? "✗ check KEY_ID, TEAM_ID and KEY_PATH"
      : "✗ unexpected (a key restricted to one environment fails on the other)";
    console.log(`${env.padEnd(10)}  ${status} ${reason}  ${verdict}`);
  } catch (error) {
    console.log(`${env.padEnd(10)}  ${error.message}`);
  }
}
