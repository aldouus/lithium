defmodule Lithium.Match.Shows do
  @moduledoc """
  Confirms two shows are the same podcast.

  A shared non-empty `podcast:guid` is enough. Two different podcast guids,
  or a guid on only one side, do not match. Episode guid sets confirm a pair
  only when both sets are non-empty and equal. A partial overlap and empty
  sets do not. Show titles are ignored.
  """

  @type show :: %{
          podcast_guid: String.t() | nil,
          episode_guids: MapSet.t(String.t())
        }

  @spec confirm(show(), show()) ::
          {:ok, {:podcast_guid, String.t()}} | {:ok, :episodes} | :unmatched
  def confirm(
        %{podcast_guid: left_guid, episode_guids: left_episodes},
        %{podcast_guid: right_guid, episode_guids: right_episodes}
      ) do
    cond do
      same_guid?(left_guid, right_guid) ->
        {:ok, {:podcast_guid, left_guid}}

      guid_present?(left_guid) or guid_present?(right_guid) ->
        :unmatched

      equal_episodes?(left_episodes, right_episodes) ->
        {:ok, :episodes}

      true ->
        :unmatched
    end
  end

  defp same_guid?(left, right) do
    guid_present?(left) and left == right
  end

  defp guid_present?(guid) when is_binary(guid) and guid != "", do: true
  defp guid_present?(_guid), do: false

  defp equal_episodes?(%MapSet{} = left, %MapSet{} = right) do
    MapSet.size(left) > 0 and left == right
  end

  defp equal_episodes?(_left, _right), do: false
end
