defmodule Lithium.Catalog do
  @moduledoc false

  @type track :: %{
          required(:id) => String.t(),
          required(:isrc) => String.t() | nil,
          required(:album) => String.t() | nil,
          required(:duration_ms) => non_neg_integer() | nil
        }

  @type show :: %{
          required(:id) => String.t(),
          required(:name) => String.t()
        }

  @type side :: :apple | :spotify
  @type priority :: side

  @type plan :: %{
          apple_add: MapSet.t(String.t()),
          apple_remove: MapSet.t(String.t()),
          spotify_add: MapSet.t(String.t()),
          spotify_remove: MapSet.t(String.t())
        }
end
