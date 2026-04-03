FROM node:22 AS builder

WORKDIR /srv

COPY package.json ./
RUN npm config set registry https://mirrors.cloud.tencent.com/npm/ && \
    npm install

COPY tsconfig.json env.d.ts ./
COPY src ./src
RUN npm run build

# ---

FROM node:22 AS skills

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN git clone --depth 1 https://cnb.cool/cnb/sdk/cnb-openapi-skills /tmp/cnb-openapi-skills && \
    rm -rf /tmp/cnb-openapi-skills/.git

FROM node:22 AS runtime-base

RUN sed -i 's/deb.debian.org/mirrors.cloud.tencent.com/g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's/security.debian.org/mirrors.cloud.tencent.com/g' /etc/apt/sources.list.d/debian.sources && \
    npm config set registry https://npm.cnb.cool/avwq/npm-cnb/-/packages/

RUN apt update && \
    apt install -y nginx curl git chromium chromium-sandbox jq && \
    rm -rf /var/lib/apt/lists/*

RUN OPENCLAW_VERSION="$(npm view openclaw version)" && \
    npm i -g "openclaw@${OPENCLAW_VERSION}" && \
    npm cache clean --force

ENV OPENCLAW_PLUGIN_ALLOW_DANGEROUS=1
ENV OPENCLAW_DISABLE_PLUGIN_SANDBOX=1
    
RUN openclaw plugins install openclaw-mcp-adapter@latest

RUN openclaw plugins install @wecom/wecom-openclaw-plugin@latest

RUN openclaw plugins install @tencent-connect/openclaw-qqbo@latest

RUN npx -y @larksuite/openclaw-lark-tools install

FROM runtime-base

WORKDIR /workspace

COPY --from=builder /srv/dist /srv/dist
RUN mkdir -p /root/.openclaw/skills
COPY --from=skills /tmp/cnb-openapi-skills /root/.openclaw/skills/cnb-openapi-skills
COPY openclaw.json /srv/openclaw.json
COPY start.sh /srv/start.sh
RUN chmod +x /srv/start.sh

EXPOSE 8686
CMD ["/srv/start.sh"]
