defmodule Lithium.AppleMusic do
  @moduledoc """
  Apple Music library calls used by the sync.

  `Lithium.AppleMusic.Client` implements this.

  Reads use `https://api.music.apple.com` with `Authorization: Bearer` set to
  `Lithium.AppleToken.developer_token/0` and `Music-User-Token` set to the
  tenant token. Favorites are the tracks in the system Favorite Songs
  playlist, which is where Apple Music sends starred songs. That playlist is
  the library playlist named Favorite Songs with `canEdit` false. Resolve each
  track through its catalog relationship, using the attributes embedded on
  that relationship or the matching `included` song, so the song carries
  `isrc`, album name, and `durationInMillis`.

  `POST /v1/me/favorites?ids[songs]=` adds a favorite. `DELETE` on that same
  path with the same query removes one. The delete is not in Apple's published
  reference. A non-2xx delete is `{:error, :favorites_probe_failed}`.

  Library playlists are `/v1/me/library/playlists` and their tracks. Creating
  and appending stay on `api.music.apple.com`. Removing one track goes to
  `https://amp-api.music.apple.com/v1/me/library/playlists/{id}/tracks` with
  `Origin: https://music.apple.com` and header `media-user-token`. A non-2xx
  response is `{:error, :playlist_probe_failed}`.

  Catalog lookup by ISRC is `GET /v1/catalog/{storefront}/songs?filter[isrc]=`.
  Pass `plug:` through every request.
  """

  alias Lithium.Catalog

  @callback favorites(user_token :: String.t(), storefront :: String.t(), opts :: keyword) ::
              {:ok, [Catalog.track()]} | {:error, term}
  @callback add_favorites(user_token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback remove_favorites(user_token :: String.t(), ids :: [String.t()], opts :: keyword) ::
              :ok | {:error, term}
  @callback songs_by_isrc(
              user_token :: String.t(),
              storefront :: String.t(),
              isrcs :: [String.t()],
              opts :: keyword
            ) :: {:ok, [Catalog.track()]} | {:error, term}
  @callback playlists(user_token :: String.t(), opts :: keyword) ::
              {:ok, [%{id: String.t(), name: String.t(), can_edit: boolean}]} | {:error, term}
  @callback playlist_tracks(user_token :: String.t(), playlist_id :: String.t(), opts :: keyword) ::
              {:ok, [Catalog.track()]} | {:error, term}
  @callback ensure_playlist(user_token :: String.t(), name :: String.t(), opts :: keyword) ::
              {:ok, String.t()} | {:error, term}
  @callback add_playlist_tracks(
              user_token :: String.t(),
              playlist_id :: String.t(),
              ids :: [String.t()],
              opts :: keyword
            ) :: :ok | {:error, term}
  @callback remove_playlist_tracks(
              user_token :: String.t(),
              playlist_id :: String.t(),
              tracks :: [Catalog.track()],
              opts :: keyword
            ) :: :ok | {:error, term}
end
