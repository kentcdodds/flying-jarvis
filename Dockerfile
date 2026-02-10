FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Install git to clone the repository, vim for SSH editing, and cloudflared for tunnel access
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

# Clone the OpenClaw repository
# OPENCLAW_VERSION can be:
#   - "latest" (default): Use the latest release tag
#   - "main": Use the main branch
#   - A specific tag or commit SHA
ARG OPENCLAW_VERSION=latest
RUN git clone https://github.com/openclaw/openclaw.git . && \
    if [ "$OPENCLAW_VERSION" = "latest" ]; then \
      echo "Fetching latest release tag..." && \
      LATEST_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null || echo "main") && \
      echo "Using latest release: $LATEST_TAG" && \
      git checkout "$LATEST_TAG"; \
    else \
      echo "Using version: $OPENCLAW_VERSION" && \
      git checkout "$OPENCLAW_VERSION"; \
    fi

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
RUN chmod +x /app/docker-entrypoint.sh

ENV NODE_ENV=production

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "run", "--allow-unconfigured", "--port", "3000", "--bind", "auto"]
