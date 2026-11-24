# lithium

Keeps a music and podcast library in sync between Apple and Spotify. Elixir.

Each account gets its own library. Lithium diffs favorites, shows, and named playlists against the last snapshot and applies the changes. Sign in with an email link, then connect Spotify, Apple Music, and Apple Podcasts. A worker runs due syncs in the background. Data lives under `LITHIUM_DATA_ROOT` or `~/.lithium`.

## Install

```sh
mix deps.get
mix phx.server
```

Requires Elixir 1.20. The app listens on port 4000.

## Use

Open `http://127.0.0.1:4000`, sign in, and connect each service.

Spotify, Apple, Listen Notes, and Resend credentials come from the environment. See `config/runtime.exs`.
