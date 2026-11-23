defmodule Lithium.Store.SpotifyId do
  use Ecto.Schema

  @primary_key false
  schema "spotify_ids" do
    field(:isrc, :string, primary_key: true)
    field(:spotify_id, :string)
  end
end
