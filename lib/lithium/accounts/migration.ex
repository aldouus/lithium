defmodule Lithium.Accounts.Migration do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:email, :text, null: false)
      add(:tenant_id, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:users, [:email]))
    create(unique_index(:users, [:tenant_id]))

    create table(:login_tokens, primary_key: false) do
      add(:jti, :text, primary_key: true, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
