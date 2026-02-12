#!/usr/bin/env node

import fs from "node:fs";

/**
 * Synchronize runtime env decisions into config on startup.
 *
 * Design goals:
 * - idempotent: re-running should converge to the same config state
 * - additive: only set/normalize fields owned by this template
 * - low surprise: avoid overriding explicit user choices unless they no longer fit available providers
 */
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

function ensureArray(target, key) {
  if (!Array.isArray(target[key])) {
    target[key] = [];
  }
  return target[key];
}

function providerFromModel(model) {
  const normalizedModel = trimValue(model);
  if (!normalizedModel.includes("/")) {
    return "";
  }
  return normalizedModel.slice(0, normalizedModel.indexOf("/"));
}

function toUniqueStrings(values) {
  const unique = [];
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }
    const normalized = trimValue(value);
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    unique.push(normalized);
  }
  return unique;
}

function arraysEqual(left, right) {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

// Order matters: first available provider becomes default primary model when current primary is missing/unusable.
const providerDefaults = [
  {
    provider: "openai",
    envVar: "OPENAI_API_KEY",
    profileKey: "openai:default",
    primaryModel: "openai/gpt-5.2",
    fallbackModels: ["openai/gpt-4o"],
  },
  {
    provider: "anthropic",
    envVar: "ANTHROPIC_API_KEY",
    profileKey: "anthropic:default",
    primaryModel: "anthropic/claude-opus-4-5",
    fallbackModels: ["anthropic/claude-sonnet-4-5"],
  },
  {
    provider: "google",
    envVar: "GEMINI_API_KEY",
    profileKey: "google:default",
    primaryModel: "google/gemini-3-pro-preview",
    fallbackModels: [],
  },
];
const providerDefaultsByName = new Map(providerDefaults.map((entry) => [entry.provider, entry]));

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

const auth = ensureObject(config, "auth");
const authProfiles = ensureObject(auth, "profiles");
const availableProviders = [];
for (const providerConfig of providerDefaults) {
  if (!trimValue(process.env[providerConfig.envVar])) {
    continue;
  }
  availableProviders.push(providerConfig.provider);
  const existingProfile = authProfiles[providerConfig.profileKey];
  if (
    !existingProfile ||
    typeof existingProfile !== "object" ||
    Array.isArray(existingProfile) ||
    existingProfile.mode !== "token" ||
    existingProfile.provider !== providerConfig.provider
  ) {
    authProfiles[providerConfig.profileKey] = {
      mode: "token",
      provider: providerConfig.provider,
    };
    console.log(`Set auth.profiles.${providerConfig.profileKey} from ${providerConfig.envVar}`);
    changed = true;
  }
}

if (availableProviders.length > 0) {
  const modelDefaults = ensureObject(config.agents.defaults, "model");
  if (typeof modelDefaults.primary !== "string") {
    modelDefaults.primary = "";
  }
  const currentPrimary = trimValue(modelDefaults.primary);
  const currentPrimaryProvider = providerFromModel(currentPrimary);

  let primaryModelUpdated = false;
  // Preserve explicit primary choices when still supported by available provider keys.
  // Only reset when primary is absent or points to a provider with no key in this deployment.
  if (!currentPrimary || !availableProviders.includes(currentPrimaryProvider)) {
    const preferredProvider = availableProviders[0];
    const preferredProviderDefaults = providerDefaultsByName.get(preferredProvider);
    if (preferredProviderDefaults && modelDefaults.primary !== preferredProviderDefaults.primaryModel) {
      modelDefaults.primary = preferredProviderDefaults.primaryModel;
      primaryModelUpdated = true;
      changed = true;
      console.log(`Set agents.defaults.model.primary=${preferredProviderDefaults.primaryModel}`);
    }
  }

  const activePrimaryProvider = providerFromModel(modelDefaults.primary);
  const recommendedFallbacks = toUniqueStrings(
    availableProviders
      .filter((provider) => provider !== activePrimaryProvider)
      .flatMap((provider) => {
        const providerConfig = providerDefaultsByName.get(provider);
        if (!providerConfig) {
          return [];
        }
        return [providerConfig.primaryModel, ...providerConfig.fallbackModels];
      })
      .filter((model) => providerFromModel(model) && providerFromModel(model) !== activePrimaryProvider),
  );

  const existingFallbacks = Array.isArray(modelDefaults.fallbacks) ? modelDefaults.fallbacks : [];
  const filteredExistingFallbacks = toUniqueStrings(
    existingFallbacks.filter((model) => {
      const provider = providerFromModel(model);
      return provider && availableProviders.includes(provider) && model !== modelDefaults.primary;
    }),
  );

  const fallbackProviders = new Set(
    filteredExistingFallbacks.map((model) => providerFromModel(model)).filter(Boolean),
  );
  const missingFallbackProviders = availableProviders.filter(
    (provider) => provider !== activePrimaryProvider && !fallbackProviders.has(provider),
  );
  const missingRecommendedFallbacks =
    missingFallbackProviders.length === 0
      ? []
      : recommendedFallbacks.filter((model) =>
          missingFallbackProviders.includes(providerFromModel(model)),
        );
  const mergedFallbacks =
    missingRecommendedFallbacks.length > 0
      ? toUniqueStrings([...filteredExistingFallbacks, ...missingRecommendedFallbacks])
      : filteredExistingFallbacks;

  const desiredFallbacks =
    // When we just changed primary (or no usable fallbacks exist), rebuild fallbacks from active providers.
    // Otherwise preserve the operator's existing, valid fallback ordering.
    primaryModelUpdated || filteredExistingFallbacks.length === 0
      ? recommendedFallbacks
      : mergedFallbacks;

  if (!arraysEqual(existingFallbacks, desiredFallbacks)) {
    modelDefaults.fallbacks = desiredFallbacks;
    changed = true;
    console.log(`Set agents.defaults.model.fallbacks=${JSON.stringify(desiredFallbacks)}`);
  }
}

const discordBotToken = trimValue(process.env.DISCORD_BOT_TOKEN);
const discordGuildId = trimValue(process.env.DISCORD_GUILD_ID);
const discordChannelId = trimValue(process.env.DISCORD_CHANNEL_ID);
if (discordBotToken && discordGuildId) {
  // Zero-touch Discord bootstrapping:
  // token + guild id are enough for a working default integration.
  const plugins = ensureObject(config, "plugins");
  const pluginEntries = ensureObject(plugins, "entries");
  const discordPlugin = ensureObject(pluginEntries, "discord");
  if (discordPlugin.enabled !== true) {
    discordPlugin.enabled = true;
    console.log("Set plugins.entries.discord.enabled=true");
    changed = true;
  }

  const bindings = ensureArray(config, "bindings");
  const hasDiscordBinding = bindings.some(
    (binding) =>
      binding &&
      typeof binding === "object" &&
      binding.agentId === "main" &&
      binding.match &&
      typeof binding.match === "object" &&
      binding.match.channel === "discord",
  );
  if (!hasDiscordBinding) {
    bindings.push({
      agentId: "main",
      match: {
        channel: "discord",
      },
    });
    console.log("Added default Discord binding for agent main");
    changed = true;
  }

  const channels = ensureObject(config, "channels");
  const discordChannel = ensureObject(channels, "discord");
  if (discordChannel.enabled !== true) {
    discordChannel.enabled = true;
    console.log("Set channels.discord.enabled=true");
    changed = true;
  }
  if (discordChannel.groupPolicy !== "open") {
    // Requested template default: permit chat in any guild channel out of the box.
    discordChannel.groupPolicy = "open";
    console.log("Set channels.discord.groupPolicy=open");
    changed = true;
  }

  const guilds = ensureObject(discordChannel, "guilds");
  const guildConfig = ensureObject(guilds, discordGuildId);
  if (guildConfig.requireMention !== false) {
    guildConfig.requireMention = false;
    console.log(`Set channels.discord.guilds.${discordGuildId}.requireMention=false`);
    changed = true;
  }

  const guildChannels = ensureObject(guildConfig, "channels");
  const defaultChannelKey = discordChannelId || "general";

  const wildcardChannel = ensureObject(guildChannels, "*");
  if (wildcardChannel.allow !== true) {
    // Wildcard entry keeps "any channel" behavior even when explicit channels are present.
    wildcardChannel.allow = true;
    console.log(`Set channels.discord.guilds.${discordGuildId}.channels.*.allow=true`);
    changed = true;
  }
  if (wildcardChannel.requireMention !== false) {
    wildcardChannel.requireMention = false;
    console.log(`Set channels.discord.guilds.${discordGuildId}.channels.*.requireMention=false`);
    changed = true;
  }

  const defaultChannel = ensureObject(guildChannels, defaultChannelKey);
  if (defaultChannel.allow !== true) {
    // Seed one explicit channel key for clarity/discoverability in config and UI.
    defaultChannel.allow = true;
    console.log(`Set channels.discord.guilds.${discordGuildId}.channels.${defaultChannelKey}.allow=true`);
    changed = true;
  }
  if (defaultChannel.requireMention !== false) {
    defaultChannel.requireMention = false;
    console.log(
      `Set channels.discord.guilds.${discordGuildId}.channels.${defaultChannelKey}.requireMention=false`,
    );
    changed = true;
  }
} else if (discordBotToken || discordGuildId) {
  // Keep this non-fatal so deployment succeeds while workflow warnings call out the missing pair.
  console.log("Skipping Discord auto-wiring: set both DISCORD_BOT_TOKEN and DISCORD_GUILD_ID.");
}

if (changed) {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
} else {
  console.log("Runtime config already matches desired state.");
}
