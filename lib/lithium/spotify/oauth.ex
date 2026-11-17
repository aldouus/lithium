defmodule Lithium.Spotify.OAuth do
  @moduledoc false

  use OAuth2.Strategy

  @scopes "user-read-private user-library-read user-library-modify playlist-read-private playlist-modify-private playlist-modify-public"

  def configured? do
    present?(Application.get_env(:lithium, :spotify_client_id)) and
      present?(Application.get_env(:lithium, :spotify_client_secret))
  end

  def authorize_url!(redirect_uri, state) do
    redirect_uri
    |> client()
    |> OAuth2.Client.authorize_url!(scope: @scopes, state: state)
  end

  def exchange(code, redirect_uri) do
    case Application.get_env(:lithium, :spotify_exchange) do
      fun when is_function(fun, 2) ->
        fun.(code, redirect_uri)

      _ ->
        exchange_live(code, redirect_uri)
    end
  end

  def client(redirect_uri) do
    OAuth2.Client.new(
      strategy: __MODULE__,
      client_id: Application.get_env(:lithium, :spotify_client_id),
      client_secret: Application.get_env(:lithium, :spotify_client_secret),
      site: "https://api.spotify.com",
      authorize_url: "https://accounts.spotify.com/authorize",
      token_url: "https://accounts.spotify.com/api/token",
      redirect_uri: redirect_uri
    )
  end

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("accept", "application/json")
    |> put_header("authorization", authorization_header(client))
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end

  defp exchange_live(code, redirect_uri) do
    case OAuth2.Client.get_token(client(redirect_uri), code: code, redirect_uri: redirect_uri) do
      {:ok, %{token: %OAuth2.AccessToken{access_token: access, refresh_token: refresh} = token}}
      when is_binary(access) and access != "" and is_binary(refresh) and refresh != "" ->
        {:ok, token}

      {:ok, _client} ->
        {:error, :spotify_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authorization_header(client) do
    "Basic " <> Base.encode64("#{client.client_id}:#{client.client_secret}")
  end

  defp present?(value) when is_binary(value) and value != "", do: true
  defp present?(_value), do: false
end
