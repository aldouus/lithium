defmodule Lithium.Store.SnapshotMeta do
  use Ecto.Schema

  @primary_key {:collection, :string, []}
  schema "snapshot_meta" do
    field(:taken_at, :utc_datetime_usec)
  end
end
