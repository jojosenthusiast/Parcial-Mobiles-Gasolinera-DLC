FROM node:24.15-bookworm-slim AS base
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@11.25.0 --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY server/package.json ./server/package.json
COPY web/package.json ./web/package.json

FROM base AS build
RUN pnpm install --frozen-lockfile
COPY server ./server
COPY scripts ./scripts
RUN pnpm --filter @dlc/server build

FROM base AS production-deps
RUN pnpm install --frozen-lockfile --prod --filter @dlc/server

FROM node:24.15-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=production-deps /app/node_modules ./node_modules
COPY --from=production-deps /app/server/node_modules ./server/node_modules
COPY --from=build /app/server/package.json ./server/package.json
COPY --from=build /app/server/dist ./server/dist
COPY --from=build /app/server/migrations ./server/migrations
COPY --from=build /app/server/certs ./server/certs
COPY --from=build /app/server/scripts ./server/scripts
WORKDIR /app/server
USER node
CMD ["node","dist/main.js"]
