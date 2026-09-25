#!/usr/bin/env node
// Prints an APNs provider token (valid for up to 60 min). Used by apns.sh and Postman.
//   node tools/jwt.mjs
import { loadEnv, requireEnv, makeJWT } from "./lib/apns.mjs";

loadEnv();
requireEnv("TEAM_ID", "KEY_ID", "KEY_PATH");
process.stdout.write(makeJWT({
  teamId: process.env.TEAM_ID,
  keyId: process.env.KEY_ID,
  keyPath: process.env.KEY_PATH,
}));
