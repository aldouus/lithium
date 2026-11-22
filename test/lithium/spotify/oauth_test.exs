defmodule Lithium.Spotify.OAuthTest do
  use ExUnit.Case, async: false

  defmodule Adapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(env, _opts) do
      send(self(), {:request, env})

      body =
        Jason.encode!(%{
          "access_token" => "access",
          "refresh_token" => "refresh",
          "expires_in" => 3600,
          "token_type" => "Bearer"
        })

      {:ok, %{env | status: 200, headers: [{"content-type", "application/json"}], body: body}}
    end
  end

  test "exchanges the code as a form and reads the refresh token" do
    previous = Application.get_env(:oauth2, :adapter)
    Application.put_env(:oauth2, :adapter, __MODULE__.Adapter)
    Application.put_env(:lithium, :spotify_client_id, "spotify-client")
    Application.put_env(:lithium, :spotify_client_secret, "spotify-secret")

    on_exit(fn ->
      if previous do
        Application.put_env(:oauth2, :adapter, previous)
      else
        Application.delete_env(:oauth2, :adapter)
      end
    end)

    assert {:ok, token} =
             Lithium.Spotify.OAuth.exchange(
               "auth-code",
               "https://lithium.aldous.cc/spotify/callback"
             )

    assert token.access_token == "access"
    assert token.refresh_token == "refresh"
    assert_received {:request, env}
    assert env.url == "https://accounts.spotify.com/api/token"
    assert env.body =~ "grant_type=authorization_code"
    assert env.body =~ "code=auth-code"

    assert Enum.any?(env.headers, fn {key, value} ->
             String.downcase(key) == "content-type" and
               String.starts_with?(value, "application/x-www-form-urlencoded")
           end)
  end
end
