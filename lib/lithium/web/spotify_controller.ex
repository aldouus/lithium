defmodule Lithium.Web.SpotifyController do
  use Phoenix.Controller, formats: [:html]

  require Logger

  import Plug.Conn

  def connect(conn, _params) do
    if Lithium.Spotify.OAuth.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      redirect_uri = Lithium.Web.Origin.join(conn, "/spotify/callback")
      url = Lithium.Spotify.OAuth.authorize_url!(redirect_uri, state)

      conn
      |> put_session(:spotify_state, state)
      |> put_session(:spotify_redirect_uri, redirect_uri)
      |> redirect(external: url)
    else
      redirect(conn, to: "/")
    end
  end

  def callback(conn, %{"error" => _error}) do
    fail(conn)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, :spotify_state)
    redirect_uri = get_session(conn, :spotify_redirect_uri)
    user = Guardian.Plug.current_resource(conn)

    if state_ok?(state, expected) and is_binary(redirect_uri) and user do
      case Lithium.Spotify.OAuth.exchange(code, redirect_uri) do
        {:ok, token} ->
          fields = %{
            "access_token" => token.access_token,
            "refresh_token" => token.refresh_token,
            "expires_at" => token.expires_at
          }

          case Lithium.Credentials.put_service(user.tenant_id, "spotify", fields) do
            :ok ->
              conn
              |> delete_session(:spotify_state)
              |> delete_session(:spotify_redirect_uri)
              |> redirect(to: "/?notice=spotify")

            {:error, reason} ->
              Logger.warning("spotify credentials were not saved: #{inspect(reason)}")
              fail(conn)
          end

        {:error, reason} ->
          Logger.warning("spotify token exchange failed: #{inspect(reason)}")
          fail(conn)
      end
    else
      fail(conn)
    end
  end

  def callback(conn, _params), do: fail(conn)

  defp fail(conn) do
    conn
    |> delete_session(:spotify_state)
    |> delete_session(:spotify_redirect_uri)
    |> redirect(to: "/?notice=spotify_failed")
  end

  defp state_ok?(state, expected) when is_binary(state) and is_binary(expected) do
    byte_size(state) == byte_size(expected) and Plug.Crypto.secure_compare(state, expected)
  end

  defp state_ok?(_state, _expected), do: false
end
