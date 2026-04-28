#!/bin/sh
set -e

# Default to empty (relative path) if BACKEND_URL is not set.
# When deploying to Azure Container Apps, set BACKEND_URL to the
# backend's external or internal FQDN, e.g.
# https://myapi.gentlebush-xxx.eastus2.azurecontainerapps.io
BACKEND_URL="${BACKEND_URL:-}"

# Validate BACKEND_URL to prevent shell injection via sed special characters,
# embedded newlines, or malformed nginx config directives. Only validate when
# a value is provided.
if [ -n "$BACKEND_URL" ]; then
    _url_lines=$(printf '%s' "$BACKEND_URL" | wc -l)
    if [ "$_url_lines" -ne 0 ] || \
       ! printf '%s' "$BACKEND_URL" | grep -qE '^https?://[a-zA-Z0-9._-]+(:[0-9]+)?(/[a-zA-Z0-9._/-]*)?$'; then
        echo "ERROR: Invalid BACKEND_URL format — must be a single-line https?:// URL with no special characters" >&2
        exit 1
    fi
fi

# Extract the hostname from the URL for the Host header and SNI.
BACKEND_HOST=$(echo "$BACKEND_URL" | sed -E 's|https?://([^/:]+).*|\1|')

# Replace placeholders in the nginx config.
sed -i "s|__BACKEND_URL__|${BACKEND_URL}|g" /etc/nginx/conf.d/default.conf
sed -i "s|__BACKEND_HOST__|${BACKEND_HOST}|g" /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
