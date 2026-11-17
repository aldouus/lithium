defmodule Lithium.Feeds.Client do
  @moduledoc false

  @behaviour Lithium.Feeds

  @impl true
  def show_identity(feed_url, opts) when is_binary(feed_url) and is_list(opts) do
    case Req.get(feed_url, retry: false, plug: opts[:plug]) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        parse_feed(body)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_feed(body) when is_binary(body) do
    {root, _rest} =
      body
      |> String.to_charlist()
      |> :xmerl_scan.string(quiet: true)

    {:ok, identity(root)}
  rescue
    exception -> {:error, exception}
  catch
    :exit, reason -> {:error, reason}
  end

  defp parse_feed(body) when is_list(body), do: parse_feed(IO.iodata_to_binary(body))
  defp parse_feed(_body), do: {:error, :invalid_feed}

  defp identity(root) do
    case find_channel(root) do
      nil ->
        %{podcast_guid: nil, episode_guids: MapSet.new()}

      channel ->
        %{
          podcast_guid: channel_guid(channel),
          episode_guids: episode_guids(channel)
        }
    end
  end

  defp find_channel({:xmlElement, _, _, _, _, _, _, _, _, _, _, _} = element) do
    if local_name(element) == "channel" do
      element
    else
      Enum.find_value(children(element), fn child ->
        if local_name(child) == "channel", do: child
      end)
    end
  end

  defp find_channel(_), do: nil

  defp channel_guid(channel) do
    Enum.find_value(children(channel), fn child ->
      if local_name(child) == "guid" do
        case text(child) do
          "" -> nil
          value -> value
        end
      end
    end)
  end

  defp episode_guids(channel) do
    channel
    |> children()
    |> Enum.filter(&(local_name(&1) == "item"))
    |> Enum.reduce(MapSet.new(), fn item, guids ->
      item
      |> children()
      |> Enum.reduce(guids, fn child, guids ->
        if local_name(child) == "guid" do
          case text(child) do
            "" -> guids
            value -> MapSet.put(guids, value)
          end
        else
          guids
        end
      end)
    end)
  end

  defp children({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    Enum.filter(content, &match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
  end

  defp local_name({:xmlElement, name, expanded, nsinfo, _, _, _, _, _, _, _, _}) do
    cond do
      match?({_, _}, nsinfo) ->
        nsinfo |> elem(1) |> xml_string()

      match?({_, _}, expanded) ->
        expanded |> elem(1) |> xml_string()

      true ->
        name |> xml_string() |> String.split(":") |> List.last()
    end
  end

  defp text({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.map(fn
      {:xmlText, _, _, _, value, _} -> xml_string(value)
      _ -> ""
    end)
    |> Enum.join()
    |> String.trim()
  end

  defp xml_string(value) when is_atom(value), do: Atom.to_string(value)
  defp xml_string(value) when is_binary(value), do: value
  defp xml_string(value) when is_list(value), do: List.to_string(value)
end
