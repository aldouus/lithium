import Config

config :lithium, ecto_repos: [Lithium.Repo, Lithium.Accounts.Repo]

config :phoenix, :json_library, Jason

config :lithium, Lithium.Repo,
  database: ":memory:",
  pool_size: 1,
  journal_mode: :wal

config :lithium, Lithium.Web.Auth,
  issuer: "lithium",
  secret_key: {Lithium.Secret, :get_or_create!, []},
  ttl: {30, :days}

config :lithium, Lithium.Web.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "127.0.0.1"],
  http: [ip: {0, 0, 0, 0}, port: 4000],
  server: true,
  check_origin: false,
  render_errors: [formats: [html: Lithium.Web.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("d", 64)

config :oauth2, serializers: %{"application/json" => Jason}

import_config "#{config_env()}.exs"
