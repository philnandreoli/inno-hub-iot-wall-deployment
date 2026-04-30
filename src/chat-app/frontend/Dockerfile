FROM --platform=linux/amd64 node:22-alpine AS build

ARG VITE_AZURE_CLIENT_ID
ARG VITE_AZURE_TENANT_ID
ARG VITE_AZURE_API_SCOPE
ENV VITE_AZURE_CLIENT_ID=$VITE_AZURE_CLIENT_ID
ENV VITE_AZURE_TENANT_ID=$VITE_AZURE_TENANT_ID
ENV VITE_AZURE_API_SCOPE=$VITE_AZURE_API_SCOPE

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

FROM --platform=linux/amd64 nginxinc/nginx-unprivileged:alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=0755 docker-entrypoint.sh /docker-entrypoint.sh

# Allow the non-root nginx user (UID 101) to overwrite config.js at startup
RUN chmod 0666 /usr/share/nginx/html/config.js

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
