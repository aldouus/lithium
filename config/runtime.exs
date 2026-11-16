import Config

if config_env() != :test do
  config :lithium,
    data_root: System.get_env("LITHIUM_DATA_ROOT") || Path.expand("~/.lithium"),
    spotify_client_id: System.get_env("SPOTIFY_CLIENT_ID"),
    spotify_client_secret: System.get_env("SPOTIFY_CLIENT_SECRET"),
    apple_team_id: System.get_env("APPLE_TEAM_ID"),
    apple_key_id: System.get_env("APPLE_KEY_ID"),
    apple_private_key_path: System.get_env("APPLE_PRIVATE_KEY_PATH"),
    apple_podcasts_developer_token: System.get_env("APPLE_PODCASTS_DEVELOPER_TOKEN"),
    listen_notes_api_key: System.get_env("LISTEN_NOTES_API_KEY")
end
