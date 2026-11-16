defmodule Lithium.Store do
  @moduledoc false

  alias Exqlite.Sqlite3

  def with_conn(tenant_id, fun) when is_function(fun, 1) do
    with {:ok, _} <- Lithium.Tenant.ensure(tenant_id),
         {:ok, path} <- Lithium.Tenant.database_path(tenant_id),
         {:ok, conn} <- Sqlite3.open(path) do
      try do
        :ok = Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")
        :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")
        :ok = migrate(conn)
        {:ok, fun.(conn)}
      after
        Sqlite3.close(conn)
      end
    end
  end

  def journal_mode(conn) do
    [[mode]] = all(conn, "PRAGMA journal_mode", [])
    mode
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
    :ok = Sqlite3.execute(conn, "BEGIN IMMEDIATE")

    try do
      :ok = Sqlite3.execute(conn, "DELETE FROM playlist_names")

      names
      |> Enum.uniq()
      |> Enum.each(fn name when is_binary(name) ->
        run(conn, "INSERT INTO playlist_names (name) VALUES (?1)", [name])
      end)

      :ok = Sqlite3.execute(conn, "COMMIT")
      :ok
    rescue
      exception ->
        Sqlite3.execute(conn, "ROLLBACK")
        reraise exception, __STACKTRACE__
    end
  end

  def playlist_names(conn) do
    conn
    |> all("SELECT name FROM playlist_names ORDER BY name", [])
    |> Enum.map(fn [name] -> name end)
  end

  def snapshot(conn, collection) when is_binary(collection) do
    case all(conn, "SELECT taken_at FROM snapshot_meta WHERE collection = ?1", [collection]) do
      [] ->
        nil

      [[_taken_at]] ->
        %{
          apple: snapshot_side(conn, collection, "apple"),
          spotify: snapshot_side(conn, collection, "spotify")
        }
    end
  end

  def put_snapshot(conn, collection, apple, spotify) when is_binary(collection) do
    :ok = Sqlite3.execute(conn, "BEGIN IMMEDIATE")

    try do
      run(conn, "DELETE FROM snapshot_items WHERE collection = ?1", [collection])
      insert_side(conn, collection, "apple", apple)
      insert_side(conn, collection, "spotify", spotify)

      run(
        conn,
        "INSERT INTO snapshot_meta (collection, taken_at) VALUES (?1, ?2)
         ON CONFLICT(collection) DO UPDATE SET taken_at = excluded.taken_at",
        [collection, DateTime.utc_now() |> DateTime.to_iso8601()]
      )

      :ok = Sqlite3.execute(conn, "COMMIT")
      :ok
    rescue
      exception ->
        Sqlite3.execute(conn, "ROLLBACK")
        reraise exception, __STACKTRACE__
    end
  end

  defp snapshot_side(conn, collection, side) do
    conn
    |> all(
      "SELECT item_key FROM snapshot_items WHERE collection = ?1 AND side = ?2",
      [collection, side]
    )
    |> Enum.map(fn [key] -> key end)
    |> MapSet.new()
  end

  defp insert_side(conn, collection, side, keys) do
    Enum.each(keys, fn key when is_binary(key) ->
      run(
        conn,
        "INSERT INTO snapshot_items (collection, side, item_key) VALUES (?1, ?2, ?3)",
        [collection, side, key]
      )
    end)
  end

  defp put_setting(conn, key, value) do
    run(
      conn,
      "INSERT INTO settings (key, value) VALUES (?1, ?2)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      [key, value]
    )

    :ok
  end

  defp get_setting(conn, key) do
    case all(conn, "SELECT value FROM settings WHERE key = ?1", [key]) do
      [[value]] -> value
      [] -> nil
    end
  end

  defp migrate(conn) do
    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      """)

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS playlist_names (
        name TEXT PRIMARY KEY
      )
      """)

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS snapshot_meta (
        collection TEXT PRIMARY KEY,
        taken_at TEXT NOT NULL
      )
      """)

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS snapshot_items (
        collection TEXT NOT NULL,
        side TEXT NOT NULL,
        item_key TEXT NOT NULL,
        PRIMARY KEY (collection, side, item_key)
      )
      """)

    :ok
  end

  defp run(conn, sql, args) do
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(statement, args)

      case Sqlite3.step(conn, statement) do
        :done -> :ok
        {:row, _row} -> :ok
      end
    after
      Sqlite3.release(conn, statement)
    end
  end

  defp all(conn, sql, args) do
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(statement, args)
      collect(conn, statement, [])
    after
      Sqlite3.release(conn, statement)
    end
  end

  defp collect(conn, statement, acc) do
    case Sqlite3.step(conn, statement) do
      {:row, row} -> collect(conn, statement, [row | acc])
      :done -> Enum.reverse(acc)
    end
  end
end
