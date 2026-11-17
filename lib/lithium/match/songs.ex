defmodule Lithium.Match.Songs do
  @moduledoc """
  Matches a song to one catalog row by ISRC.

  `key/1` is the uppercased ISRC. A track with no ISRC is `:unmatched`.
  `choose/3` keeps rows with that ISRC. One row is the match. Several rows
  are narrowed by normalized album title, then by duration within 2000 ms.
  A nil album or duration does not agree. Zero rows or a remaining tie is
  `:unmatched`.
  """

  @duration_window_ms 2_000

  @spec key(map) :: {:ok, String.t()} | :unmatched
  def key(%{isrc: isrc}) when is_binary(isrc) and isrc != "", do: {:ok, String.upcase(isrc)}
  def key(%{"isrc" => isrc}) when is_binary(isrc) and isrc != "", do: {:ok, String.upcase(isrc)}
  def key(_track), do: :unmatched

  @spec choose(String.t(), [map], map) :: {:ok, map} | :unmatched
  def choose(isrc, candidates, reference)
      when is_binary(isrc) and is_list(candidates) and is_map(reference) do
    case Enum.filter(candidates, &isrc_match?(&1, isrc)) do
      [candidate] -> {:ok, candidate}
      [] -> :unmatched
      several -> disambiguate(several, reference)
    end
  end

  defp disambiguate(candidates, reference) do
    case Enum.filter(candidates, &album_agrees?(&1, reference)) do
      [candidate] -> {:ok, candidate}
      [] -> :unmatched
      several -> several |> Enum.filter(&duration_agrees?(&1, reference)) |> one()
    end
  end

  defp one([candidate]), do: {:ok, candidate}
  defp one(_candidates), do: :unmatched

  defp isrc_match?(%{isrc: candidate}, isrc) when is_binary(candidate) and candidate != "" do
    String.upcase(candidate) == String.upcase(isrc)
  end

  defp isrc_match?(_candidate, _isrc), do: false

  defp album_agrees?(candidate, reference) when is_map(candidate) do
    case {normalize_album(Map.get(candidate, :album)),
          normalize_album(Map.get(reference, :album))} do
      {album, album} when is_binary(album) -> true
      _ -> false
    end
  end

  defp duration_agrees?(candidate, reference) when is_map(candidate) do
    case {Map.get(candidate, :duration_ms), Map.get(reference, :duration_ms)} do
      {left, right} when is_integer(left) and is_integer(right) ->
        abs(left - right) <= @duration_window_ms

      _ ->
        false
    end
  end

  defp normalize_album(album) when is_binary(album) do
    album
    |> String.downcase()
    |> String.replace("&", "and")
    |> String.replace(~r/[^\p{L}\p{N}]/u, "")
  end

  defp normalize_album(_album), do: nil
end
