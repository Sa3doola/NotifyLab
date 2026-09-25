// Minimal APNs provider: JWT (ES256) from a .p8 key + HTTP/2 request. No dependencies.
import { createPrivateKey, sign, randomUUID } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { connect } from "node:http2";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
export const root = resolve(here, "..", "..");

/** Loads tools/.env (KEY=value lines) into process.env without overriding real env vars. */
export function loadEnv() {
  const file = resolve(root, "tools", ".env");
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
    }
  }
}

export function requireEnv(...names) {
  const missing = names.filter((n) => !process.env[n]);
  if (missing.length) {
    console.error(`Missing ${missing.join(", ")}. Copy tools/.env.example to tools/.env and fill it in.`);
    process.exit(1);
  }
}

const base64url = (input) => Buffer.from(input).toString("base64url");

// APNs rejects a JWT older than 60 min, and one refreshed more often than every 20 min.
// Cache it for 50 min.
let cached = { token: null, issuedAt: 0 };

/** Provider token: header {alg: ES256, kid: Key ID}, claims {iss: Team ID, iat: now}. */
export function makeJWT({ teamId, keyId, keyPath }) {
  const now = Math.floor(Date.now() / 1000);
  if (cached.token && now - cached.issuedAt < 50 * 60) return cached.token;

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const key = createPrivateKey(readFileSync(resolve(root, keyPath)));
  // JWT wants the raw r||s signature (IEEE P1363), not DER. This is the classic bug.
  const signature = sign("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" });

  cached = { token: `${header}.${claims}.${base64url(signature)}`, issuedAt: now };
  return cached.token;
}

/** Reads a payload file and drops the Simulator-only key so it doesn't count toward 4 KB. */
export function readPayload(path) {
  const payload = JSON.parse(readFileSync(resolve(process.cwd(), path), "utf8"));
  delete payload["Simulator Target Bundle"];
  return payload;
}

/** Header presets for each kind of push. */
export function headersFor(type, bundleId) {
  switch (type) {
    case "background":
      return { "apns-push-type": "background", "apns-priority": "5", "apns-topic": bundleId };
    case "voip":
      return { "apns-push-type": "voip", "apns-priority": "10", "apns-topic": `${bundleId}.voip`, "apns-expiration": "0" };
    case "marketing":
      return { "apns-push-type": "alert", "apns-priority": "5", "apns-topic": bundleId };
    default:
      return { "apns-push-type": "alert", "apns-priority": "10", "apns-topic": bundleId };
  }
}

/**
 * Sends one notification. Resolves with { status, apnsId, uniqueId, reason }.
 * status 200 = accepted by APNs (not the same as "shown on screen").
 */
export function sendToAPNs({ deviceToken, payload, type = "alert", env = "sandbox", bundleId, jwt, collapseId }) {
  const host = env === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  const body = JSON.stringify(payload);
  const limit = type === "voip" ? 5120 : 4096;
  if (Buffer.byteLength(body) > limit) {
    return Promise.reject(new Error(`Payload is ${Buffer.byteLength(body)} bytes; the limit is ${limit}.`));
  }

  return new Promise((resolvePromise, reject) => {
    const client = connect(host);
    client.on("error", reject);
    const headers = {
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-id": randomUUID(),
      ...headersFor(type, bundleId),
      ...(collapseId ? { "apns-collapse-id": collapseId } : {}),
    };
    const request = client.request(headers);
    let status = 0;
    let responseHeaders = {};
    let data = "";
    request.on("response", (h) => { status = h[":status"]; responseHeaders = h; });
    request.setEncoding("utf8");
    request.on("data", (chunk) => (data += chunk));
    request.on("end", () => {
      client.close();
      const answer = data ? JSON.parse(data) : {};
      resolvePromise({
        status,
        apnsId: responseHeaders["apns-id"],
        uniqueId: responseHeaders["apns-unique-id"], // sandbox only → Delivery Log in the Push Console
        reason: answer.reason,
        timestamp: answer.timestamp, // 410 only: when APNs stopped accepting the token (ms)
      });
    });
    request.on("error", reject);
    request.end(body);
  });
}

/** What to do with the token after a send. This is the server's cleanup rule. */
export function verdict({ status, reason }) {
  if (status === 200) return "keep";
  if (status === 410 || reason === "Unregistered") return "delete";
  if (reason === "BadDeviceToken") return "check-environment";
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") return "fix-jwt";
  return "retry-or-inspect";
}
