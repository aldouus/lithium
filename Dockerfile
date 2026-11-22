FROM hexpm/elixir:1.20.3-erlang-29.0.5-debian-bookworm-20260824 AS build

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY lib lib
COPY config/runtime.exs config/
RUN mix compile && mix release

FROM debian:bookworm-slim

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    RELEASE_DISTRIBUTION=none

COPY --from=build /app/_build/prod/rel/lithium ./
COPY rel/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
