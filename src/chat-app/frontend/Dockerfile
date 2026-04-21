FROM --platform=linux/amd64 node:22-alpine AS build

ARG VITE_AZURE_CLIENT_ID
ARG VITE_AZURE_TENANT_ID
ARG VITE_AZURE_API_SCOPE
ARG VITE_APPINSIGHTS_CONNECTION_STRING
ENV VITE_AZURE_CLIENT_ID=$VITE_AZURE_CLIENT_ID
ENV VITE_AZURE_TENANT_ID=$VITE_AZURE_TENANT_ID
ENV VITE_AZURE_API_SCOPE=$VITE_AZURE_API_SCOPE
ENV VITE_APPINSIGHTS_CONNECTION_STRING=$VITE_APPINSIGHTS_CONNECTION_STRING

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

FROM --platform=linux/amd64 nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
