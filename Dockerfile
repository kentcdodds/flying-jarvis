FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Install build/runtime dependencies and cloudflared for tunnel access.
# Keep git + vim available for SSH-based diagnostics inside Fly machines.
RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates curl gnupg lsof ripgrep vim && \
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
COPY bin/startup-runner.sh /app/bin/startup-runner.sh
COPY startup /app/startup
COPY email-poller /app/email-poller
RUN chmod +x /app/docker-entrypoint.sh /app/bin/startup-runner.sh /app/startup/*.sh

ENV NODE_ENV=production

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["/app/bin/startup-runner.sh"]
