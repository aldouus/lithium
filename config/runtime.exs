import Config

if config_env() != :test do
  data_root = System.get_env("LITHIUM_DATA_ROOT") || Path.expand("~/.lithium")
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :lithium,
    data_root: data_root,
    spotify_client_id: System.get_env("SPOTIFY_CLIENT_ID"),
    spotify_client_secret: System.get_env("SPOTIFY_CLIENT_SECRET"),
    apple_team_id: System.get_env("APPLE_TEAM_ID"),
    apple_key_id: System.get_env("APPLE_KEY_ID"),
    apple_private_key_path: System.get_env("APPLE_PRIVATE_KEY_PATH"),
    apple_podcasts_developer_token: System.get_env("APPLE_PODCASTS_DEVELOPER_TOKEN"),
    listen_notes_api_key: System.get_env("LISTEN_NOTES_API_KEY"),
    resend_api_key: System.get_env("RESEND_API_KEY"),
    resend_from: System.get_env("RESEND_FROM") || "Lithium <onboarding@resend.dev>",
    base_url: System.get_env("LITHIUM_BASE_URL")

  config :lithium, Lithium.Web.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: Lithium.Secret.get_or_create!(),
    server: true
end
