defmodule Lithium.Engine do
  @moduledoc """
  Plans adds and removals that bring one Apple library and one Spotify library
  back together.
  """

  @type library :: MapSet.t(String.t()) | :unreadable

  @type snapshot ::
          nil
          | %{
              required(:apple) => MapSet.t(String.t()),
              required(:spotify) => MapSet.t(String.t())
            }

  @doc """
  Diffs the current `apple` and `spotify` key sets against `snapshot`.

  Either library may be `:unreadable`. `priority` is `:apple` or `:spotify`.
  """
  @spec diff(library(), library(), snapshot(), Lithium.Catalog.priority()) ::
          {:ok, Lithium.Catalog.plan()} | {:skip, :priority_unreadable}
  def diff(:unreadable, _spotify, _snapshot, :apple), do: {:skip, :priority_unreadable}
  def diff(_apple, :unreadable, _snapshot, :spotify), do: {:skip, :priority_unreadable}

  def diff(%MapSet{} = apple, :unreadable, _snapshot, :apple) do
    {:ok, plan(spotify_add: apple)}
  end

  def diff(:unreadable, %MapSet{} = spotify, _snapshot, :spotify) do
    {:ok, plan(apple_add: spotify)}
  end

  def diff(%MapSet{} = apple, %MapSet{} = spotify, nil, :apple) do
    {:ok,
     plan(
       spotify_add: MapSet.difference(apple, spotify),
       spotify_remove: MapSet.difference(spotify, apple)
     )}
  end

  def diff(%MapSet{} = apple, %MapSet{} = spotify, nil, :spotify) do
    {:ok,
     plan(
       apple_add: MapSet.difference(spotify, apple),
       apple_remove: MapSet.difference(apple, spotify)
     )}
  end

  def diff(
        %MapSet{} = apple,
        %MapSet{} = spotify,
        %{apple: %MapSet{} = snap_apple, spotify: %MapSet{} = snap_spotify},
        priority
      )
      when priority in [:apple, :spotify] do
    {:ok, reconcile(apple, spotify, snap_apple, snap_spotify)}
  end

  defp reconcile(apple, spotify, snap_apple, snap_spotify) do
    removed =
      MapSet.union(
        MapSet.difference(snap_apple, apple),
        MapSet.difference(snap_spotify, spotify)
      )

    apple_kept = MapSet.difference(apple, removed)
    spotify_kept = MapSet.difference(spotify, removed)

    plan(
      apple_add: MapSet.difference(spotify_kept, apple_kept),
      apple_remove: MapSet.intersection(apple, removed),
      spotify_add: MapSet.difference(apple_kept, spotify_kept),
      spotify_remove: MapSet.intersection(spotify, removed)
    )
  end

  defp plan(fields) do
    Map.merge(
      %{
        apple_add: MapSet.new(),
        apple_remove: MapSet.new(),
        spotify_add: MapSet.new(),
        spotify_remove: MapSet.new()
      },
      Map.new(fields)
    )
  end
end
