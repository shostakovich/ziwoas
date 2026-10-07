# syntax=docker/dockerfile:1
# check=error=true

# The production image: a Mix release on Debian (mix phx.gen.release, adapted).
#
#   docker build -t ziwoas .
#   docker compose up -d
#
# Erlang/OTP and Elixir match .tool-versions. Images:
# https://hub.docker.com/r/hexpm/elixir/tags
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=28.5.0.7
ARG DEBIAN_VERSION=trixie-20261005-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# The build runs on the build host's architecture; only the release is per platform.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS assets

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY config/config.exs config/${MIX_ENV}.exs config/
COPY assets assets
COPY priv priv
COPY lib lib

# esbuild is a standalone binary for the build host; the bundles are platform-free.
RUN mix assets.setup && mix assets.deploy

FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time config first, so a change to runtime.exs does not recompile the deps.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY --from=assets /app/priv/static priv/static

RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libstdc++6 openssl libncurses6 ca-certificates tzdata curl && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    MIX_ENV="prod" \
    PORT=3000 \
    ZIWOAS_CONFIG=/app/config/ziwoas.yml \
    ZIWOAS_DB=/app/storage/production.sqlite3

WORKDIR /app

RUN groupadd --system --gid 1000 ziwoas && \
    useradd ziwoas --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /app/storage /app/config && chown ziwoas:ziwoas /app/storage

COPY --from=build --chown=ziwoas:ziwoas /app/_build/prod/rel/ziwoas ./

USER ziwoas

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl -fsS -o /dev/null "http://localhost:${PORT}/up" || exit 1

# Adopt or migrate the database, then serve.
CMD ["/bin/sh", "-c", "/app/bin/migrate && exec /app/bin/server"]
