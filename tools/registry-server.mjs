#!/usr/bin/env node
// A tiny "your server": stores device tokens and sends pushes, cleaning up dead tokens.
//
//   node tools/registry-server.mjs            → http://localhost:8080
//
//   POST /devices                 the app uploads its tokens here (upsert by deviceID)
//   GET  /devices                 list what we have
//   POST /send  {"file":"payloads/order-shipped.apns","type":"alert","collapseId":"order-1042"}
//                                 send to every device (type and collapseId are optional)
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { loadEnv, requireEnv, makeJWT, readPayload, sendToAPNs, verdict, root } from "./lib/apns.mjs";

loadEnv();
const PORT = Number(process.env.PORT ?? 8080);
const dbFile = resolve(root, "tools", ".data", "devices.json");
mkdirSync(resolve(root, "tools", ".data"), { recursive: true });

const load = () => (existsSync(dbFile) ? JSON.parse(readFileSync(dbFile, "utf8")) : {});
const save = (db) => writeFileSync(dbFile, JSON.stringify(db, null, 2));

// The app re-uploads at least weekly. Firebase suggests treating a month of silence as stale;
// we give a device two months to come back before we stop sending to it.
const STALE_DAYS = 60;

function pruneStale(db) {
  const cutoff = Date.now() - STALE_DAYS * 24 * 3600 * 1000;
  for (const [id, device] of Object.entries(db)) {
    if (Date.parse(device.lastSeenAt) < cutoff) delete db[id];
  }
}

async function readBody(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

function reply(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body, null, 2));
}

async function sendToAll({ file, type = "alert", collapseId }) {
  requireEnv("TEAM_ID", "KEY_ID", "KEY_PATH", "BUNDLE_ID");
  const db = load();
  pruneStale(db);
  const jwt = makeJWT({ teamId: process.env.TEAM_ID, keyId: process.env.KEY_ID, keyPath: process.env.KEY_PATH });
  const payload = readPayload(file);
  const results = [];

  for (const device of Object.values(db)) {
    const token = type === "voip" ? device.voipToken : device.apnsToken;
    if (!token) continue;
    const result = await sendToAPNs({
      deviceToken: token,
      payload,
      type,
      // The token decides the endpoint. A development token only works with the sandbox.
      env: device.environment === "production" ? "production" : "sandbox",
      bundleId: process.env.BUNDLE_ID,
      jwt,
      collapseId,
    });
    const action = verdict(result);
    // 410: dead token. Delete it, unless the device uploaded it again after APNs gave up on it.
    const uploadedSince = result.timestamp && Date.parse(device.lastSeenAt) > result.timestamp;
    if (action === "delete" && !uploadedSince) delete db[device.deviceID];
    results.push({ deviceID: device.deviceID, ...result, action });
  }
  save(db);
  return results;
}

createServer(async (req, res) => {
  try {
    if (req.method === "POST" && req.url === "/devices") {
      const record = await readBody(req);
      if (!record.deviceID) return reply(res, 400, { error: "deviceID is required" });
      const db = load();
      db[record.deviceID] = { ...db[record.deviceID], ...record, lastSeenAt: new Date().toISOString() };
      save(db);
      console.log(`↑ ${record.deviceID}  apns=${record.apnsToken?.slice(0, 8)}…  env=${record.environment}`);
      return reply(res, 200, { ok: true });
    }
    if (req.method === "GET" && req.url === "/devices") return reply(res, 200, load());
    if (req.method === "POST" && req.url === "/send") return reply(res, 200, await sendToAll(await readBody(req)));
    reply(res, 404, { error: "not found" });
  } catch (error) {
    reply(res, 500, { error: error.message });
  }
}).listen(PORT, () => {
  console.log(`NotifyLab registry on http://localhost:${PORT}`);
  console.log(`In the app: Orders tab → "Your server" → http://localhost:${PORT} (Simulator) or http://<your Mac's IP>:${PORT} (device)`);
});
