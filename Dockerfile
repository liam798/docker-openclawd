# OpenClaw Gateway 镜像
# 从官方仓库克隆并构建，无需本地源码
# 文档: https://docs.clawd.bot/install/docker

FROM node:22-bookworm

# 构建时可选：指定 OpenClaw 版本（分支或 tag）
ARG OPENCLAW_VERSION=main
# 构建时可选：额外安装的 apt 包，空格分隔
ARG OPENCLAW_DOCKER_APT_PACKAGES=""

# Bun（构建脚本需要）
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# 克隆官方仓库并保留构建所需文件
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && git clone --depth 1 --branch "${OPENCLAW_VERSION}" https://github.com/openclaw/openclaw.git . \
    && rm -rf .git \
    && apt-get purge -y git && apt-get autoremove -y --purge && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# 可选：安装额外系统依赖（如 ffmpeg、build-essential）
RUN if [ -n "${OPENCLAW_DOCKER_APT_PACKAGES}" ]; then \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${OPENCLAW_DOCKER_APT_PACKAGES} \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# 依赖与构建（与官方 Dockerfile 一致）
RUN pnpm install --frozen-lockfile
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# 以非 root 用户运行
USER node

WORKDIR /app
CMD ["node", "dist/index.js"]
