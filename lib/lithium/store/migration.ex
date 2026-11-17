defmodule Lithium.Store.Migration do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add(:key, :text, primary_key: true, null: false)
      add(:value, :text, null: false)
    end

    create table(:playlist_names, primary_key: false) do
      add(:name, :text, primary_key: true, null: false)
    end

    create table(:snapshot_meta, primary_key: false) do
      add(:collection, :text, primary_key: true, null: false)
      add(:taken_at, :utc_datetime_usec, null: false)
    end

    create table(:snapshot_items, primary_key: false) do
      add(:collection, :text, primary_key: true, null: false)
      add(:side, :text, primary_key: true, null: false)
      add(:item_key, :text, primary_key: true, null: false)
    end
  end
end
