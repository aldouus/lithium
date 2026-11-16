defmodule Lithium.ListenNotes do
  @moduledoc """
  Directory lookup from a Spotify show id to an Apple show id and a feed URL.

  `Lithium.ListenNotes.Client` implements this.

  `POST https://listen-api.listennotes.com/api/v2/podcasts` with header
  `X-ListenAPI-Key` and form field `spotify_ids` (comma-separated, at most 10).
  Read `itunes_id` and `rss` from each returned podcast. A missing row is an
  unmatched show, not an error. Pass `plug:` through the request.
  """

  @callback lookup(spotify_ids :: [String.t()], opts :: keyword) ::
              {:ok,
               [
                 %{
                   spotify_id: String.t(),
                   itunes_id: String.t() | nil,
                   feed_url: String.t() | nil
                 }
               ]}
              | {:error, term}
end
