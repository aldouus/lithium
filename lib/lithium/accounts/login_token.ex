defmodule Lithium.Accounts.LoginToken do
  use Ecto.Schema

  @primary_key {:jti, :string, []}
  schema "login_tokens" do
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
