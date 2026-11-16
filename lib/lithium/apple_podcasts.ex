defmodule Lithium.ApplePodcasts do
  @moduledoc """
  Apple Podcasts library calls used by the sync.

  `Lithium.ApplePodcasts.Client` implements this against
  `https://amp-api.podcasts.apple.com`. Send `Authorization: Bearer` with the
  podcasts developer token, `media-user-token` with the tenant token, and
  `Origin: https://podcasts.apple.com`.

  Followed shows are `GET /v1/me/library/podcasts` with `limit=25` and the
  returned `next` path. `POST /v1/me/library/podcasts/{id}` follows.
  `DELETE /v1/me/library/podcasts/{id}` unfollows. A non-2xx unfollow is
  `{:error, :podcasts_probe_failed}`.

  Episode guids for a show come from
  `GET /v1/catalog/{storefront}/podcasts/{id}/episodes`. Each episode's `guid`
  attribute is the RSS guid. Pass `plug:` through every request.
  """

  @callback followed_shows(user_token :: String.t(), opts :: keyword) ::
              {:ok, [%{id: String.t(), name: String.t()}]} | {:error, term}
  @callback follow(user_token :: String.t(), show_id :: String.t(), opts :: keyword) ::
              :ok | {:error, term}
  @callback unfollow(user_token :: String.t(), show_id :: String.t(), opts :: keyword) ::
              :ok | {:error, term}
  @callback episode_guids(
              user_token :: String.t(),
              storefront :: String.t(),
              show_id :: String.t(),
              opts :: keyword
            ) :: {:ok, MapSet.t(String.t())} | {:error, term}
end
