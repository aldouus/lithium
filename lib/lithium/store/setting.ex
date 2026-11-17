defmodule Lithium.Store.Setting do
  use Ecto.Schema

  @primary_key {:key, :string, []}
  schema "settings" do
    field(:value, :string)
  end
end
