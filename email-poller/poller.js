#!/usr/bin/env node

const DEFAULT_POLL_INTERVAL_MS = 10_000;

function readEnv(name) {
  return String(process.env[name] ?? "").trim();
}

function readIntervalMs() {
  const raw = readEnv("EMAIL_POLL_INTERVAL_MS");
  if (!raw) {
    return DEFAULT_POLL_INTERVAL_MS;
  }

  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed) || parsed <= 0) {
    console.error(
      `[email-poller] invalid EMAIL_POLL_INTERVAL_MS; using default ${DEFAULT_POLL_INTERVAL_MS}ms`,
    );
    return DEFAULT_POLL_INTERVAL_MS;
  }

  return parsed;
}

function buildRecentUrl(baseUrl, secret) {
  let endpoint;
  try {
    endpoint = new URL(baseUrl);
  } catch {
    return null;
  }

  endpoint.searchParams.set("action", "recent");
  endpoint.searchParams.set("maxResults", "5");
  if (secret) {
    endpoint.searchParams.set("secret", secret);
  }

  return endpoint;
}

function countMessages(payload) {
  if (Array.isArray(payload)) {
    return payload.length;
  }

  if (!payload || typeof payload !== "object") {
    return 0;
  }

  const objectPayload = payload;
  const candidateArrays = [
    objectPayload.messages,
    objectPayload.items,
    objectPayload.results,
    objectPayload.emails,
  ];
  for (const candidate of candidateArrays) {
    if (Array.isArray(candidate)) {
      return candidate.length;
    }
  }

  if (typeof objectPayload.count === "number" && Number.isFinite(objectPayload.count)) {
    return objectPayload.count;
  }

  if (typeof objectPayload.total === "number" && Number.isFinite(objectPayload.total)) {
    return objectPayload.total;
  }

  return 0;
}

async function pollProxy(proxy) {
  const endpoint = buildRecentUrl(proxy.url, proxy.secret);
  if (!endpoint) {
    console.error(`[email-poller] ${proxy.name}: invalid URL`);
    return;
  }

  let response;
  try {
    response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    });
  } catch (error) {
    const errorName = error && typeof error === "object" && "name" in error ? error.name : "Error";
    console.error(`[email-poller] ${proxy.name}: request failed (${errorName})`);
    return;
  }

  if (response.status === 401 || response.status === 403) {
    console.error(`[email-poller] ${proxy.name}: unauthorized (${response.status})`);
    return;
  }

  if (!response.ok) {
    console.error(`[email-poller] ${proxy.name}: request failed (${response.status})`);
    return;
  }

  let payload;
  try {
    payload = await response.json();
  } catch {
    console.error(`[email-poller] ${proxy.name}: invalid JSON response`);
    return;
  }

  const count = countMessages(payload);
  console.log(`[email-poller] ${proxy.name}: recent_count=${count}`);
}

const proxies = [
  {
    name: "gmail-proxy",
    url: readEnv("GMAIL_PROXY_URL"),
    secret: readEnv("GMAIL_PROXY_SECRET"),
  },
  {
    name: "gmail2-proxy",
    url: readEnv("GMAIL2_PROXY_URL"),
    secret: readEnv("GMAIL2_PROXY_SECRET"),
  },
];

for (const proxy of proxies) {
  if (!proxy.url) {
    console.error(`[email-poller] ${proxy.name}: skipped (missing URL)`);
  }
}

const configuredProxies = proxies.filter((proxy) => proxy.url);
const pollIntervalMs = readIntervalMs();

console.log(
  `[email-poller] starting poller with interval ${pollIntervalMs}ms (configured_proxies=${configuredProxies.length})`,
);

let tickInFlight = false;
async function pollTick() {
  if (tickInFlight) {
    console.log("[email-poller] tick skipped (previous poll still running)");
    return;
  }

  tickInFlight = true;
  try {
    await Promise.all(configuredProxies.map((proxy) => pollProxy(proxy)));
  } finally {
    tickInFlight = false;
  }
}

void pollTick();
setInterval(() => {
  void pollTick();
}, pollIntervalMs);
