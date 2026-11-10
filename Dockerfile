# syntax=docker/dockerfile:1
#
# Self-hostable web version of BetterBetterUntis.
#   docker build -t better-betteruntis-web .
#   docker run -p 8080:8080 better-betteruntis-web
# See docs/WEB.md.

ARG FLUTTER_VERSION=3.47.9
ARG DART_VERSION=3.13.7
# Release channel baked into the web app: alpha keeps the Debug screen.
ARG BBU_CHANNEL=beta

# ---------------------------------------------------------------------------
# Stage 1: build the Flutter web app.
#
# ghcr.io/cirruslabs/flutter has no 3.47.x tag (its newest is 3.44.0, which
# ships a Dart SDK too old for this pubspec), so Flutter is installed from
# the official git tag instead. The output is platform independent, so this
# stage always runs on the build host's native architecture.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM debian:trixie-slim AS web
ARG FLUTTER_VERSION
ARG BBU_CHANNEL
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/opt/pub-cache
RUN flutter config --no-analytics --no-cli-animations \
      --no-enable-android --no-enable-ios \
 && flutter precache --web \
 && flutter --version

WORKDIR /src
# Resolve dependencies first so this layer is cached across source changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter pub get \
 && flutter build web --release --no-web-resources-cdn \
      --dart-define=BBU_CHANNEL=${BBU_CHANNEL}

# ---------------------------------------------------------------------------
# Stage 2: compile the Dart server to a native executable.
# ---------------------------------------------------------------------------
FROM dart:${DART_VERSION} AS server
WORKDIR /server
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/ ./
RUN mkdir -p /out \
 && dart pub get --offline \
 && dart compile exe bin/server.dart -o /out/bbu_server

# ---------------------------------------------------------------------------
# Stage 3: minimal runtime (no shell, no package manager).
# /runtime/ is the minimal set of libraries the official dart image provides
# for AOT-compiled executables.
# ---------------------------------------------------------------------------
FROM scratch
COPY --from=server /runtime/ /
# Root CAs for the HTTPS connections to WebUntis.
COPY --from=server /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=server /out/bbu_server /app/bbu_server
COPY --from=web /src/build/web/ /app/web/

WORKDIR /app
ENV PORT=8080 \
    BBU_WEB_ROOT=/app/web
# Unprivileged numeric UID/GID (scratch has no /etc/passwd).
USER 65532:65532
EXPOSE 8080
# The binary has a built-in probe because scratch has no shell or curl.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/app/bbu_server", "--healthcheck"]
ENTRYPOINT ["/app/bbu_server"]
