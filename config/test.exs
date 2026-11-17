import Config

config :lithium, data_root: Path.join(System.tmp_dir!(), "lithium-test")

config :lithium, Lithium.Repo, log: false

config :lithium, Lithium.Accounts.Repo, log: false

config :lithium, Lithium.Web.Endpoint,
  server: false,
  secret_key_base: String.duplicate("t", 64)

config :lithium, Lithium.Web.Auth, secret_key: String.duplicate("t", 64)
