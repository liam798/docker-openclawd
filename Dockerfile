# OpenClaw Gateway 镜像
# 从本地源码构建（避免构建时访问 GitHub）
# 文档: https://docs.clawd.bot/install/docker

FROM node:22-bookworm

# 构建阶段使用宿主机代理（由 docker-compose 传入）
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG NO_PROXY

ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV http_proxy=${HTTP_PROXY}
ENV https_proxy=${HTTPS_PROXY}
ENV ALL_PROXY=${ALL_PROXY}
ENV all_proxy=${ALL_PROXY}
ENV NO_PROXY=${NO_PROXY}
ENV no_proxy=${NO_PROXY}

# 构建时可选：指定 OpenClaw 版本（分支或 tag）
# 保留此参数是为了兼容 docker-compose.yml；本地源码构建时不使用
ARG OPENCLAW_VERSION=main
# 构建时可选：额外安装的 apt 包，空格分隔
ARG OPENCLAW_DOCKER_APT_PACKAGES=""

WORKDIR /app

# 使用本地同步的源码
COPY openclaw-src/ /app/

# 可选：安装额外系统依赖（如 ffmpeg、build-essential）
RUN if [ -n "${OPENCLAW_DOCKER_APT_PACKAGES}" ]; then \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${OPENCLAW_DOCKER_APT_PACKAGES} \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

RUN corepack enable

# 依赖与构建
RUN pnpm install --frozen-lockfile
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# 以非 root 用户运行
USER node

WORKDIR /app
CMD ["node", "dist/index.js"]
