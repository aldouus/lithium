defmodule Lithium.Match.ShowsTest do
  use ExUnit.Case, async: true

  alias Lithium.Match.Shows

  test "accepts two shows that share a podcast guid" do
    guid = "ead4c236-bf58-58c6-a7d6-0a32d63e4367"

    left = show(guid, ["ep-1"], "Night Vale")
    right = show(guid, ["ep-9"], "Welcome to Night Vale")

    assert Shows.confirm(left, right) == {:ok, {:podcast_guid, guid}}
  end

  test "rejects a pair whose podcast guids differ" do
    episodes = ["ep-1", "ep-2"]

    left = show("guid-a", episodes)
    right = show("guid-b", episodes)

    assert Shows.confirm(left, right) == :unmatched
  end

  test "accepts two shows whose episode guid sets are equal" do
    episodes = ["ep-1", "ep-2"]

    left = show(nil, episodes)
    right = show(nil, episodes)

    assert Shows.confirm(left, right) == {:ok, :episodes}
  end

  test "rejects a partial episode overlap" do
    left = show(nil, ["ep-1", "ep-2"])
    right = show(nil, ["ep-2", "ep-3"])

    assert Shows.confirm(left, right) == :unmatched
  end

  test "rejects empty episode guid sets" do
    left = show(nil, [])
    right = show(nil, [])

    assert Shows.confirm(left, right) == :unmatched
  end

  test "rejects a podcast guid on only one side" do
    episodes = ["ep-1", "ep-2"]

    left = show("guid-a", episodes)
    right = show(nil, episodes)

    assert Shows.confirm(left, right) == :unmatched
  end

  defp show(guid, episodes, name \\ nil) do
    %{
      podcast_guid: guid,
      episode_guids: MapSet.new(episodes),
      name: name
    }
  end
end
