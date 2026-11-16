defmodule Lithium.Match.SongsTest do
  use ExUnit.Case, async: true

  alias Lithium.Match.Songs

  test "leaves a track unmatched when the ISRC is missing" do
    assert Songs.key(%{}) == :unmatched
    assert Songs.key(%{isrc: nil}) == :unmatched
    assert Songs.key(%{isrc: ""}) == :unmatched
    assert Songs.key(%{"isrc" => nil}) == :unmatched
    assert Songs.key(%{"isrc" => ""}) == :unmatched
  end

  test "keys a track by its uppercased ISRC" do
    assert Songs.key(%{isrc: "usrc17607839"}) == {:ok, "USRC17607839"}
    assert Songs.key(%{"isrc" => "gbAyc0100001"}) == {:ok, "GBAYC0100001"}
  end

  test "returns the single catalog hit for an ISRC" do
    hit = track("apple-1", "usrc17607839", "Tusk", 10_000)
    other = track("apple-2", "GBAYC0100001", "Rumours", 240_000)

    assert Songs.choose("USRC17607839", [other, hit], reference("Rumours", 240_000)) ==
             {:ok, hit}
  end

  test "leaves the song unmatched when no catalog hit has the ISRC" do
    miss = track("miss", "GBAYC0100001", "Rumours", 200_000)

    assert Songs.choose("USRC17607839", [miss], reference("Rumours", 200_000)) == :unmatched
    assert Songs.choose("USRC17607839", [], reference("Rumours", 200_000)) == :unmatched
  end

  test "chooses among several catalog hits by album and duration" do
    studio = track("studio", "USRC17607839", "Rumours & More!", 202_000)
    remaster = track("remaster", "usrc17607839", "rumours and more", 202_001)
    other_album = track("comp", "Usrc17607839", "Tusk", 200_000)

    assert Songs.choose(
             "usrc17607839",
             [other_album, remaster, studio],
             reference("Rumours and More", 200_000)
           ) == {:ok, studio}
  end

  test "keeps the only matching album when duration does not agree" do
    studio = track("studio", "USRC17607839", "Rumours", 300_000)
    near = track("near", "USRC17607839", "Tusk", 200_000)

    assert Songs.choose("USRC17607839", [near, studio], reference("Rumours", 200_000)) ==
             {:ok, studio}
  end

  test "does not count a nil album or nil duration as agreement" do
    close = track("close", "USRC17607839", nil, 200_000)
    far = track("far", "USRC17607839", nil, 300_000)

    assert Songs.choose("USRC17607839", [close, far], reference(nil, 200_000)) == :unmatched

    timed = track("timed", "USRC17607839", "Rumours", 200_000)
    untimed = track("untimed", "USRC17607839", "Rumours", nil)

    assert Songs.choose("USRC17607839", [timed, untimed], reference("Rumours", 200_000)) ==
             {:ok, timed}
  end

  test "leaves the song unmatched when several hits still tie" do
    left = track("left", "USRC17607839", "Rumours", 201_000)
    right = track("right", "USRC17607839", "Rumours!", 199_000)

    assert Songs.choose("USRC17607839", [left, right], reference("Rumours", 200_000)) ==
             :unmatched
  end

  defp track(id, isrc, album, duration_ms) do
    %{id: id, isrc: isrc, album: album, duration_ms: duration_ms}
  end

  defp reference(album, duration_ms) do
    %{album: album, duration_ms: duration_ms}
  end
end
