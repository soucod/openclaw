#!/bin/bash

set -e

# Docker 镜像中 openclaw 的安装目录
# cnb.cool 会 clone 仓库到工作目录，但 dist/ 目录只存在于镜像的 /app 中
OPENCLAW_DIR="/app"

# 复制配置文件到 openclaw 默认配置目录
mkdir -p ~/.openclaw
cp "${OPENCLAW_DIR}/openclaw.json" ~/.openclaw/openclaw.json

# 配置 nginx 反向代理
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

# 在 Docker 镜像的 /app 目录下启动 openclaw gateway
# 使用 node dist/index.js 而不是 openclaw 命令（因为后者需要全局安装）
cd "${OPENCLAW_DIR}"
node dist/index.js gateway --allow-unconfigured > openclaw.log 2>&1 &

PID=$!
echo "[openclaw] started, pid=$PID"

# 健康检查：等待服务启动
for i in {1..120}; do
  if curl -sf http://127.0.0.1:18789 >/dev/null; then
    echo "[openclaw] service is up"
    exit 0
  fi
  sleep 1
done

echo "[openclaw] startup timeout"
# 输出日志帮助调试
echo "[openclaw] last 50 lines of log:"
tail -50 openclaw.log 2>/dev/null || echo "[openclaw] no log file found"
exit 1
