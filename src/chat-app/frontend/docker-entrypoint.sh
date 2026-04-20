#!/bin/sh
set -e

# Default to empty (relative path) if BACKEND_URL is not set.
# When deploying to Azure Container Apps, set BACKEND_URL to the
# backend's external or internal FQDN, e.g.
# https://myapi.gentlebush-xxx.eastus2.azurecontainerapps.io
BACKEND_URL="${BACKEND_URL:-}"

# Extract the hostname from the URL for the Host header and SNI.
BACKEND_HOST=$(echo "$BACKEND_URL" | sed -E 's|https?://([^/:]+).*|\1|')

# Replace placeholders in the nginx config.
sed -i "s|__BACKEND_URL__|${BACKEND_URL}|g" /etc/nginx/conf.d/default.conf
sed -i "s|__BACKEND_HOST__|${BACKEND_HOST}|g" /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
