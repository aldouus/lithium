defmodule Lithium.ListenNotes.Client do
  @moduledoc false

  @behaviour Lithium.ListenNotes

  @endpoint "https://listen-api.listennotes.com/api/v2/podcasts"
  @chunk_size 10

  @impl true
  def lookup(spotify_ids, opts) when is_list(spotify_ids) and is_list(opts) do
    with {:ok, key} <- api_key() do
      fetch_chunks(spotify_ids, key, opts)
    end
  end

  defp fetch_chunks(ids, key, opts) do
    ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case fetch_chunk(chunk, key, opts) do
        {:ok, rows} -> {:cont, {:ok, acc ++ rows}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_chunk(ids, key, opts) do
    result =
      Req.post(@endpoint,
        form: [spotify_ids: Enum.join(ids, ",")],
        headers: [{"X-ListenAPI-Key", key}],
        retry: false,
        plug: opts[:plug]
      )

    case result do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        with {:ok, body} <- decode_json(response) do
          {:ok, rows(body, ids)}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key do
    case Application.get_env(:lithium, :listen_notes_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_listen_notes_key}
    end
  end

  defp rows(body, ids) do
    podcasts =
      case body do
        %{"podcasts" => podcasts} when is_list(podcasts) -> podcasts
        _ -> []
      end

    Enum.flat_map(ids, fn id ->
      case Enum.find(podcasts, &match_podcast?(&1, id)) do
        nil -> []
        podcast -> [to_row(id, podcast)]
      end
    end)
  end

  defp to_row(spotify_id, podcast) do
    %{
      spotify_id: spotify_id,
      itunes_id: string_or_nil(podcast["itunes_id"]),
      feed_url: feed_url(podcast["rss"])
    }
  end

  defp match_podcast?(podcast, id) when is_map(podcast) and is_binary(id) do
    spotify_id_field(podcast) == id or spotify_url_contains?(podcast, id)
  end

  defp match_podcast?(_, _), do: false

  defp spotify_id_field(podcast) do
    [
      fetch_string(podcast, "spotify_id"),
      fetch_string(podcast, "spotifyId"),
      fetch_string(podcast["extra"], "spotify_id"),
      fetch_string(podcast["extra"], "spotifyId")
    ]
    |> Enum.find(&is_binary/1)
  end

  defp spotify_url_contains?(podcast, id) do
    case fetch_string(podcast["extra"], "spotify_url") do
      nil -> false
      url -> String.contains?(url, id)
    end
  end

  defp fetch_string(%{} = map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch_string(_, _), do: nil

  defp string_or_nil(value) when is_integer(value), do: Integer.to_string(value)
  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_), do: nil

  defp feed_url(value) when is_binary(value) and value != "", do: value
  defp feed_url(_), do: nil

  defp decode_json(%Req.Response{body: body}) when is_map(body), do: {:ok, body}

  defp decode_json(%Req.Response{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json(%Req.Response{}), do: {:error, :invalid_response}
end
