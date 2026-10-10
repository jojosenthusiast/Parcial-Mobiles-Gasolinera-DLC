FROM node:24.15-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY web/package.json ./package.json
COPY web/server.mjs ./server.mjs
COPY web/public ./public
USER node
EXPOSE 4173
CMD ["node","server.mjs"]
