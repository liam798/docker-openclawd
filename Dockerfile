# OpenClaw Gateway 镜像
# 使用 npm 安装 OpenClaw（无需克隆源码）
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

# 安装的 OpenClaw 版本：latest、或具体版本号如 2026.1.30
ARG OPENCLAW_VERSION=latest
# 构建时可选：额外安装的 apt 包，空格分隔
ARG OPENCLAW_DOCKER_APT_PACKAGES=""

# 可选：安装额外系统依赖（如 ffmpeg、build-essential）
RUN if [ -n "${OPENCLAW_DOCKER_APT_PACKAGES}" ]; then \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${OPENCLAW_DOCKER_APT_PACKAGES} \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# 使用 npm 全局安装 OpenClaw（无需源码与构建）
RUN npm install -g openclaw@${OPENCLAW_VERSION}

ENV NODE_ENV=production

# 以非 root 用户运行
USER node

# 默认启动 Gateway（具体 bind/port 由 docker-compose command 覆盖）
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
