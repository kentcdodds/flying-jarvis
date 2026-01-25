FROM node:24-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Install git to clone the repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

# Clone the clawdbot repository
RUN git clone https://github.com/clawdbot/clawdbot.git . && \
    git checkout main

ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

RUN pnpm install --frozen-lockfile

RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

CMD ["node", "dist/index.js"]
