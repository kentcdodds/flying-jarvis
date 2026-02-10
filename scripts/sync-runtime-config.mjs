#!/usr/bin/env node

import fs from "node:fs";

const truthyValues = new Set(["1", "true", "yes", "on"]);

function trimValue(value) {
  return String(value ?? "").trim();
}

function readConfig(configPath) {
  try {
    return JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (error) {
    console.error(`Failed to read or parse config at ${configPath}: ${error}`);
    process.exit(1);
  }
}

function ensureObject(target, key) {
  if (typeof target[key] !== "object" || target[key] === null || Array.isArray(target[key])) {
    target[key] = {};
  }
  return target[key];
}

const configPath = trimValue(process.env.OPENCLAW_CONFIG_FILE);
if (!configPath) {
  console.error("OPENCLAW_CONFIG_FILE is required.");
  process.exit(1);
}
if (!fs.existsSync(configPath)) {
  console.error(`Config file not found at ${configPath}; skipping runtime sync.`);
  process.exit(0);
}

const config = readConfig(configPath);
let changed = false;

const stateDir = trimValue(process.env.OPENCLAW_STATE_DIR) || "/data";
const desiredWorkspace = trimValue(process.env.OPENCLAW_WORKSPACE_DIR) || `${stateDir}/workspace`;
const agents = ensureObject(config, "agents");
const defaults = ensureObject(agents, "defaults");
if (defaults.workspace !== desiredWorkspace) {
  defaults.workspace = desiredWorkspace;
  console.log(`Set agents.defaults.workspace=${desiredWorkspace}`);
  changed = true;
}

if (Object.prototype.hasOwnProperty.call(process.env, "OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH")) {
  const desiredAllowInsecureAuth = truthyValues.has(
    trimValue(process.env.OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH).toLowerCase(),
  );
  const gateway = ensureObject(config, "gateway");
  const controlUi = ensureObject(gateway, "controlUi");
  if (controlUi.allowInsecureAuth !== desiredAllowInsecureAuth) {
    controlUi.allowInsecureAuth = desiredAllowInsecureAuth;
    console.log(`Set gateway.controlUi.allowInsecureAuth=${desiredAllowInsecureAuth}`);
    changed = true;
  }
}

if (changed) {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
} else {
  console.log("Runtime config already matches desired state.");
}
