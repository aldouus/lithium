defmodule Lithium.Spotify do
  @moduledoc """
  Spotify Web API used by the sync.

  `Lithium.Spotify.Client` implements this. Development-mode library writes go
  through `PUT` and `DELETE /v1/me/library` with Spotify URIs. Listing stays on
  `GET /v1/me/tracks`, `GET /v1/me/shows`, and `GET /v1/me/playlists`.
  Playlist items are `GET /v1/playlists/{id}/items`, added with
  `POST /v1/playlists/{id}/items`, and removed with
  `DELETE /v1/playlists/{id}/items`.

  Pass `plug:` through every request so tests can stub Req. Refresh an expired
  access token with the app client id and secret before a library call. A 401
  after a refresh is `{:error, :spotify_auth}`.
  """

  alias Lithium.Catalog

  @callback liked_songs(token :: String.t(), opts :: keyword) ::
              {:ok, [Catalog.track()]} | {:error, term}
  @callback saved_shows(token :: String.t(), opts :: keyword) ::
              {:ok, [Catalog.show()]} | {:error, term}
  @callback show_episodes(token :: String.t(), show_id :: String.t(), opts :: keyword) ::
              {:ok, [%{name: String.t(), release_date: String.t()}]} | {:error, term}
  @callback playlists(token :: String.t(), opts :: keyword) ::
              {:ok, [%{id: String.t(), name: String.t()}]} | {:error, term}
  @callback playlist_tracks(token :: String.t(), playlist_id :: String.t(), opts :: keyword) ::
              {:ok, [Catalog.track()]} | {:error, term}
  @callback save_tracks(token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback remove_tracks(token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback save_shows(token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback remove_shows(token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback ensure_playlist(token :: String.t(), name :: String.t(), opts :: keyword) ::
              {:ok, String.t()} | {:error, term}
  @callback add_playlist_tracks(
              token :: String.t(),
              playlist_id :: String.t(),
              ids :: [String.t()],
              opts :: keyword
            ) :: :ok | {:error, term}
  @callback remove_playlist_tracks(
              token :: String.t(),
              playlist_id :: String.t(),
              ids :: [String.t()],
              opts :: keyword
            ) :: :ok | {:error, term}
  @callback search_track(token :: String.t(), isrc :: String.t(), opts :: keyword) ::
              {:ok, Catalog.track() | nil} | {:error, term}
end
