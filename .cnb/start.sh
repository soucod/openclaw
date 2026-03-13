#!/bin/bash

set -e

# 获取当前脚本所在目录（.cnb 目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Docker 镜像中 openclaw 的安装目录
# cnb.cool 会 clone 仓库到工作目录，但 dist/ 目录只存在于镜像的 /app 中
OPENCLAW_DIR="/app"

# 复制配置文件到 openclaw 默认配置目录
# 使用 .cnb 目录下的 openclaw.json
mkdir -p ~/.openclaw
cp "${SCRIPT_DIR}/openclaw.json" ~/.openclaw/openclaw.json


print_openclaw_log() {
  echo "[openclaw] ===== log (last 200 lines) ====="
  if [ -f openclaw.log ]; then
    tail -n 200 openclaw.log || true
  else
    echo "[openclaw] log file not found: openclaw.log"
  fi
  echo "[openclaw] ===== log end ====="
}

print_mcp_log() {
  local name="$1"
  local log_file="$2"
  echo "[$name] ===== log (last 120 lines) ====="
  if [ -f "$log_file" ]; then
    tail -n 120 "$log_file" || true
  else
    echo "[$name] log file not found: $log_file"
  fi
  echo "[$name] ===== log end ====="
}

wait_mcp_ready() {
  local name="$1"
  local pid="$2"
  local log_file="$3"
  local timeout="${4:-20}"
  local stable_target="${5:-3}"
  local stable_count=0
  local i

  for ((i = 1; i <= timeout; i++)); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "[$name] process exited before ready"
      print_mcp_log "$name" "$log_file"
      return 1
    fi

    # Fast path: proceed immediately when common ready markers appear.
    if [ -f "$log_file" ] && grep -Eiq \
      "ready|started|listening|running|server starting|server connected|已启动|等待来自MCP客户端的请求" \
      "$log_file"; then
      echo "[$name] ready (detected from log)"
      return 0
    fi

    # Fallback for quiet stdio servers: alive for a few consecutive seconds means healthy startup.
    stable_count=$((stable_count + 1))
    if [ "$stable_count" -ge "$stable_target" ]; then
      echo "[$name] running (no ready marker, process stable ${stable_target}s)"
      return 0
    fi

    sleep 1
  done

  echo "[$name] startup timeout (${timeout}s)"
  print_mcp_log "$name" "$log_file"
  return 1
}

cat > /etc/nginx/nginx.conf <<EOF
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }

    map "\$http_upgrade\$arg_token" \$should_redirect {
        default 0;
        "" 1;
    }

    server {
        listen 8686;
        server_name _;

        location = / {
            if (\$should_redirect = 1) {
                return 302 \$scheme://\$http_host/?token=${CNB_TOKEN};
            }
            proxy_pass http://127.0.0.1:18789/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;

            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 86400;
            proxy_connect_timeout 86400;
        }

        location / {
            proxy_pass http://127.0.0.1:18789/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;

            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 86400;
            proxy_connect_timeout 86400;
        }
    }
}
EOF

nginx

BIND_MODE="loopback"
if [ "${CNB_EVENT:-}" = "vscode" ]; then
  BIND_MODE="lan"
fi

TEMPLATE_CONFIG="$(dirname "$0")/openclaw.json"
CONFIG_DIR="${HOME}/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

mkdir -p "$CONFIG_DIR"
if [ -f "$TEMPLATE_CONFIG" ]; then
  cp "$TEMPLATE_CONFIG" "$CONFIG_FILE"
  API_URL_VALUE="${PLUGIN_API_URL:-}"
  API_KEY_VALUE="${PLUGIN_API_KEY:-}"
  MODEL_VALUE="${PLUGIN_MODEL:-}"
  PRIMARY_VALUE=""
  PIPELINE_ORIGIN=""

  if [ -n "${CNB_BUILD_ID:-}" ]; then
    PIPELINE_ORIGIN="http://${CNB_BUILD_ID}-001.cnb.space"
  fi

  if [ -n "${MODEL_VALUE}" ]; then
    PRIMARY_VALUE="cnb/${MODEL_VALUE}"
  fi

  TMP_CONFIG="${CONFIG_FILE}.tmp"
  jq \
    --arg bind "$BIND_MODE" \
    --arg apiUrl "${API_URL_VALUE}" \
    --arg apiKey "${API_KEY_VALUE}" \
    --arg modelId "${MODEL_VALUE}" \
    --arg primary "${PRIMARY_VALUE}" \
    --arg origin1 "http://127.0.0.1:18789" \
    --arg origin2 "$PIPELINE_ORIGIN" \
    '
      .gateway.bind = $bind
      | .gateway.controlUi.allowedOrigins = [$origin1, $origin2]
      | if $apiUrl != "" then .models.providers.cnb.baseUrl = $apiUrl else . end
      | if $apiKey != "" then .models.providers.cnb.apiKey = $apiKey else . end
      | if $modelId != "" then .models.providers.cnb.models[0].id = $modelId else . end
      | if $primary != "" then .agents.defaults.model.primary = $primary else . end
    ' \
    "$CONFIG_FILE" > "$TMP_CONFIG"
  mv "$TMP_CONFIG" "$CONFIG_FILE"
fi
echo "[start] openclaw gateway bind mode: $BIND_MODE"
if [ -n "${API_URL_VALUE:-}" ] || [ -n "${API_KEY_VALUE:-}" ] || [ -n "${MODEL_VALUE:-}" ]; then
  echo "[start] custom provider overrides applied (PLUGIN_API_URL/PLUGIN_API_KEY/PLUGIN_MODEL)"
fi

npx -y -p @cnbcool/mcp-server cnb-mcp-stdio > mcp-stdio.log 2>&1 &
MCP_PID=$!
echo "[mcp] cnb-mcp-stdio started, pid=$MCP_PID"
wait_mcp_ready "mcp-stdio" "$MCP_PID" "mcp-stdio.log" 20 3

npx -y bing-cn-mcp > bing-cn-mcp.log 2>&1 &
BING_CN_PID=$!
echo "[mcp] bing-cn-mcp started, pid=$BING_CN_PID"
wait_mcp_ready "bing-cn-mcp" "$BING_CN_PID" "bing-cn-mcp.log" 20 3

sleep 2

openclaw gateway --allow-unconfigured > openclaw.log 2>&1 &

PID=$!
echo "[openclaw] started, pid=$PID"

for i in {1..120}; do
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "[openclaw] process exited before ready"
    print_openclaw_log
    exit 1
  fi

  if curl -sf http://127.0.0.1:18789 >/dev/null; then
    echo "[openclaw] service is up"
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "[openclaw] startup timeout"
    print_openclaw_log
    exit 1
  fi
  sleep 1
done

if [ "${CNB_EVENT:-}" = "vscode" ]; then
  echo "[start] cloud dev mode detected (CNB_EVENT=vscode), service ready, exiting"
  exit 0
fi

echo "[start] running node app..."
echo "[start] pipeline mode detected, running node app..."
if node /srv/dist/app.js; then
  :
else
  code=$?
  echo "[start] node app exited with code=$code"
  print_openclaw_log
  exit "$code"
fi
