defmodule Lithium.Store.SpotifyIdMigration do
  use Ecto.Migration

  def change do
    create table(:spotify_ids, primary_key: false) do
      add(:isrc, :text, primary_key: true, null: false)
      add(:spotify_id, :text, null: false)
    end
  end
end
