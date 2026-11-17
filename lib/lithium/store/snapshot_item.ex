defmodule Lithium.Store.SnapshotItem do
  use Ecto.Schema

  @primary_key false
  schema "snapshot_items" do
    field(:collection, :string, primary_key: true)
    field(:side, :string, primary_key: true)
    field(:item_key, :string, primary_key: true)
  end
end
