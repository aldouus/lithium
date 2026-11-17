defmodule Lithium.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field(:email, :string)
    field(:tenant_id, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
