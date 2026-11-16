defmodule Lithium.EngineTest do
  use ExUnit.Case, async: true

  alias Lithium.Engine

  test "apple priority replaces spotify on the first run" do
    assert Engine.diff(set(["a", "b"]), set(["b", "c"]), nil, :apple) ==
             {:ok, plan(%{spotify_add: set(["a"]), spotify_remove: set(["c"])})}
  end

  test "spotify priority replaces apple on the first run" do
    assert Engine.diff(set(["a", "b"]), set(["b", "c"]), nil, :spotify) ==
             {:ok, plan(%{apple_add: set(["c"]), apple_remove: set(["a"])})}
  end

  test "copies an apple removal onto spotify" do
    snapshot = %{apple: set(["gone", "keep"]), spotify: set(["gone", "keep"])}

    assert Engine.diff(set(["keep"]), set(["gone", "keep"]), snapshot, :spotify) ==
             {:ok, plan(%{spotify_remove: set(["gone"])})}
  end

  test "copies a spotify add onto apple" do
    snapshot = %{apple: set(["keep"]), spotify: set(["keep"])}

    assert Engine.diff(set(["keep"]), set(["keep", "new"]), snapshot, :apple) ==
             {:ok, plan(%{apple_add: set(["new"])})}
  end

  test "drops a spotify add when apple removed the same key" do
    snapshot = %{apple: set(["clash"]), spotify: set([])}

    assert Engine.diff(set([]), set(["clash"]), snapshot, :spotify) ==
             {:ok, plan(%{spotify_remove: set(["clash"])})}
  end

  test "leaves a key that was already only on one side" do
    snapshot = %{apple: set(["only-apple", "both"]), spotify: set(["both"])}
    apple = set(["only-apple", "both"])
    spotify = set(["both"])

    assert Engine.diff(apple, spotify, snapshot, :apple) == {:ok, plan()}
  end

  test "plans nothing when both sides added the same key" do
    snapshot = %{apple: set(["old"]), spotify: set(["old"])}
    current = set(["old", "shared"])

    assert Engine.diff(current, current, snapshot, :apple) == {:ok, plan()}
  end

  test "skips when the priority side is unreadable" do
    assert Engine.diff(:unreadable, set(["a"]), nil, :apple) == {:skip, :priority_unreadable}

    assert Engine.diff(set(["a"]), :unreadable, nil, :spotify) ==
             {:skip, :priority_unreadable}
  end

  test "adds priority keys when the lower side is unreadable" do
    apple = set(["a", "b"])
    spotify = set(["c"])

    snapshot = %{apple: set(["a"]), spotify: set(["a", "stale"])}

    assert Engine.diff(apple, :unreadable, snapshot, :apple) ==
             {:ok, plan(%{spotify_add: apple})}

    assert Engine.diff(:unreadable, spotify, nil, :spotify) ==
             {:ok, plan(%{apple_add: spotify})}
  end

  defp plan(fields \\ []) do
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

  defp set(keys), do: MapSet.new(keys)
end
