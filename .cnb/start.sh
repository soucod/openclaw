#!/bin/bash

set -e

cd ..

mkdir -p ~/.openclaw
cp .cnb/openclaw.json ~/.openclaw/openclaw.json

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


openclaw gateway --allow-unconfigured \
  > openclaw.log 2>&1 &

PID=$!
echo "[openclaw] started, pid=$PID"

for i in {1..120}; do
  if curl -sf http://127.0.0.1:18789 >/dev/null; then
    echo "[openclaw] service is up"
    exit 0
  fi
  sleep 1
done

echo "[openclaw] startup timeout"
exit 1