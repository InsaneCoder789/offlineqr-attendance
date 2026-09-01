FROM node:22-alpine AS dependencies
WORKDIR /workspace/faculty-portal
COPY faculty-portal/package.json faculty-portal/package-lock.json ./
RUN npm ci

FROM node:22-alpine AS build
WORKDIR /workspace/faculty-portal
COPY --from=dependencies /workspace/faculty-portal/node_modules ./node_modules
COPY faculty-portal ./
# The portal validates the shared presence protocol vector at build time.
COPY shared /workspace/shared
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /workspace/faculty-portal/package.json ./package.json
COPY --from=build /workspace/faculty-portal/package-lock.json ./package-lock.json
COPY --from=build /workspace/faculty-portal/node_modules ./node_modules
COPY --from=build /workspace/faculty-portal/.next ./.next
COPY --from=build /workspace/faculty-portal/next.config.ts ./next.config.ts
EXPOSE 5173
CMD ["npm", "run", "start"]
