#!/bin/sh
set -e

# Default to empty (relative path) if BACKEND_URL is not set.
# When deploying to Azure Container Apps, set BACKEND_URL to the
# backend's internal FQDN, e.g. http://iot-wall-api.internal.kindocean-xxx.eastus.azurecontainerapps.io
BACKEND_URL="${BACKEND_URL:-}"

# Replace the placeholder in the nginx config with the actual backend URL.
sed -i "s|__BACKEND_URL__|${BACKEND_URL}|g" /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
