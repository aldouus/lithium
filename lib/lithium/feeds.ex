defmodule Lithium.Feeds do
  @moduledoc """
  RSS fields used to confirm a show match.

  `Lithium.Feeds.Client` fetches the feed URL and returns the channel
  `podcast:guid` when the tag is present, plus the set of item `<guid>` values.
  A feed that cannot be fetched is `{:error, reason}`. Pass `plug:` through.
  """

  @callback show_identity(feed_url :: String.t(), opts :: keyword) ::
              {:ok, %{podcast_guid: String.t() | nil, episode_guids: MapSet.t(String.t())}}
              | {:error, term}
end
