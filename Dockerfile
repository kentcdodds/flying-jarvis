FROM node:22-bookworm

# Install Bun (required for build scripts) — pinned version to mitigate supply-chain risk
ARG BUN_VERSION=1.2.2
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
ENV PATH="/app/node_modules/.bin:/root/.bun/bin:${PATH}"

RUN corepack enable

# Install build/runtime dependencies and cloudflared for tunnel access.
# Keep git + vim available for SSH-based diagnostics inside the container.
RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates curl gnupg lsof python3 python-is-python3 ripgrep vim && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main" \
      | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends cloudflared && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

# Fetch OpenClaw sources from a single explicit ref.
# OPENCLAW_VERSION can be a branch, tag, or commit SHA.
ARG OPENCLAW_VERSION=main
RUN test -n "$OPENCLAW_VERSION" && \
    curl -fsSL "https://codeload.github.com/openclaw/openclaw/tar.gz/${OPENCLAW_VERSION}" | tar -xz --strip-components=1

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

RUN pnpm install --frozen-lockfile

RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Copy default config template and entrypoint script
COPY default-config.json /app/default-config.json
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
COPY scripts/sync-runtime-config.mjs /app/scripts/sync-runtime-config.mjs
COPY docs/agent /app/docs/agent
RUN chmod +x /app/docker-entrypoint.sh

ENV NODE_ENV=production

# Ensure /data is accessible to non-root user at runtime
RUN mkdir -p /data && chown node:node /data

# Runtime runs as non-root (node user = uid 1000) to limit container-escape impact
USER node

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "run", "--allow-unconfigured", "--port", "3000", "--bind", "loopback"]
