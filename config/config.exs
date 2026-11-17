import Config

config :lithium, ecto_repos: [Lithium.Repo]

config :lithium, Lithium.Repo,
  database: ":memory:",
  pool_size: 1,
  journal_mode: :wal

import_config "#{config_env()}.exs"
