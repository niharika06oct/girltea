# syntax=docker/dockerfile:1

# ---- Build stage: compile the Flutter web app ----
# Pinned to the Flutter version used in development (see `flutter --version`).
FROM ghcr.io/cirruslabs/flutter:3.44.8 AS build

WORKDIR /app

# Avoid git "dubious ownership" errors when building as root in CI.
RUN git config --global --add safe.directory '*'

# Supabase connection, injected at build time. Render passes matching service
# env vars as build args automatically (see render.yaml). These are public
# client values, not secrets.
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY

# Resolve dependencies first for better layer caching.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Build the web bundle with the Cloud config baked in.
COPY . .
RUN flutter build web --release \
    --dart-define=SUPABASE_URL=${SUPABASE_URL} \
    --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}

# ---- Serve stage: tiny Node static server ----
FROM node:20-alpine AS serve

WORKDIR /app
COPY --from=build /app/build/web ./build/web
COPY server.js ./

ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.js"]
