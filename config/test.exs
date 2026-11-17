import Config

config :lithium, data_root: Path.join(System.tmp_dir!(), "lithium-test")

config :lithium, Lithium.Repo, log: false
