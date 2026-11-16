defmodule Lithium do
  @moduledoc """
  Per-tenant library sync between Apple Music, Apple Podcasts, and Spotify.
  """

  @doc """
  Runs one sync for `tenant_id`.

  The same function handles a first run and every later run. The tenant's
  priority order is the fallback when no snapshot exists or one side cannot
  be read.
  """
  def sync(tenant_id, opts \\ []) when is_binary(tenant_id) and is_list(opts) do
    Lithium.Sync.run(tenant_id, opts)
  end

  def put_priority(tenant_id, side) when side in [:apple, :spotify] do
    Lithium.Store.with_conn(tenant_id, fn conn ->
      Lithium.Store.put_priority(conn, side)
    end)
  end

  def put_playlist_names(tenant_id, names) when is_list(names) do
    Lithium.Store.with_conn(tenant_id, fn conn ->
      Lithium.Store.put_playlist_names(conn, names)
    end)
  end

  def put_interval(tenant_id, seconds) when is_integer(seconds) and seconds > 0 do
    Lithium.Store.with_conn(tenant_id, fn conn ->
      Lithium.Store.put_interval(conn, seconds)
    end)
  end
end
