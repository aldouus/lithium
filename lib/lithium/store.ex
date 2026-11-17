defmodule Lithium.Store do
  @moduledoc false

  import Ecto.Query

  alias Lithium.Repo
  alias Lithium.Store.PlaylistName
  alias Lithium.Store.Setting
  alias Lithium.Store.SnapshotItem
  alias Lithium.Store.SnapshotMeta

  def with_conn(tenant_id, fun) when is_function(fun, 1) do
    with {:ok, _} <- Lithium.Tenant.ensure(tenant_id),
         {:ok, path} <- Lithium.Tenant.database_path(tenant_id) do
      {:ok, pid} =
        Repo.start_link(
          name: nil,
          database: path,
          pool_size: 1,
          journal_mode: :wal
        )

      try do
        previous = Repo.put_dynamic_repo(pid)

        try do
          Ecto.Migrator.run(
            Repo,
            [{20_261_116_000_000, Lithium.Store.Migration}],
            :up,
            all: true,
            log: false
          )

          {:ok, fun.(pid)}
        after
          Repo.put_dynamic_repo(previous)
        end
      after
        Supervisor.stop(pid)
      end
    end
  end

  def journal_mode(conn) do
    with_repo(conn, fn ->
      {:ok, %{rows: [[mode]]}} = Repo.query("PRAGMA journal_mode")
      mode
    end)
  end

  def put_priority(conn, side) when side in [:apple, :spotify] do
    put_setting(conn, "priority", Atom.to_string(side))
  end

  def priority(conn) do
    case get_setting(conn, "priority") do
      "spotify" -> :spotify
      _ -> :apple
    end
  end

  def put_interval(conn, seconds) when is_integer(seconds) and seconds > 0 do
    put_setting(conn, "interval_seconds", Integer.to_string(seconds))
  end

  def interval(conn) do
    case get_setting(conn, "interval_seconds") do
      nil -> 3600
      text -> String.to_integer(text)
    end
  end

  def put_next_run(conn, unix) when is_integer(unix) do
    put_setting(conn, "next_run_at", Integer.to_string(unix))
  end

  def next_run(conn) do
    case get_setting(conn, "next_run_at") do
      nil -> nil
      text -> String.to_integer(text)
    end
  end

  def mark_probed(conn, name) when is_binary(name) do
    put_setting(conn, "probed:" <> name, "true")
  end

  def probed?(conn, name) when is_binary(name) do
    get_setting(conn, "probed:" <> name) == "true"
  end

  def put_playlist_names(conn, names) when is_list(names) do
    with_repo(conn, fn ->
      {:ok, :ok} =
        Repo.transaction(
          fn ->
            Repo.delete_all(PlaylistName)

            rows =
              names
              |> Enum.uniq()
              |> Enum.map(fn name when is_binary(name) -> %{name: name} end)

            insert_all(PlaylistName, rows)
            :ok
          end,
          mode: :immediate
        )

      :ok
    end)
  end

  def playlist_names(conn) do
    with_repo(conn, fn ->
      Repo.all(from(name in PlaylistName, order_by: [asc: name.name], select: name.name))
    end)
  end

  def snapshot(conn, collection) when is_binary(collection) do
    with_repo(conn, fn ->
      case Repo.get(SnapshotMeta, collection) do
        nil ->
          nil

        _meta ->
          %{
            apple: snapshot_side(collection, "apple"),
            spotify: snapshot_side(collection, "spotify")
          }
      end
    end)
  end

  def put_snapshot(conn, collection, apple, spotify) when is_binary(collection) do
    taken_at = DateTime.utc_now()

    with_repo(conn, fn ->
      {:ok, :ok} =
        Repo.transaction(
          fn ->
            Repo.delete_all(from(item in SnapshotItem, where: item.collection == ^collection))
            insert_side(collection, "apple", apple)
            insert_side(collection, "spotify", spotify)

            Repo.insert!(
              %SnapshotMeta{collection: collection, taken_at: taken_at},
              on_conflict: [set: [taken_at: taken_at]],
              conflict_target: [:collection]
            )

            :ok
          end,
          mode: :immediate
        )

      :ok
    end)
  end

  defp snapshot_side(collection, side) do
    Repo.all(
      from(item in SnapshotItem,
        where: item.collection == ^collection and item.side == ^side,
        select: item.item_key
      )
    )
    |> MapSet.new()
  end

  defp insert_side(collection, side, keys) do
    rows =
      Enum.map(keys, fn key when is_binary(key) ->
        %{collection: collection, side: side, item_key: key}
      end)

    insert_all(SnapshotItem, rows)
  end

  defp insert_all(_schema, []), do: {0, nil}

  defp insert_all(schema, rows) do
    Repo.insert_all(schema, rows)
  end

  defp put_setting(conn, key, value) do
    with_repo(conn, fn ->
      Repo.insert!(
        %Setting{key: key, value: value},
        on_conflict: [set: [value: value]],
        conflict_target: [:key]
      )

      :ok
    end)
  end

  defp get_setting(conn, key) do
    with_repo(conn, fn ->
      case Repo.get(Setting, key) do
        nil -> nil
        setting -> setting.value
      end
    end)
  end

  defp with_repo(conn, fun) do
    previous = Repo.put_dynamic_repo(conn)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end
end
