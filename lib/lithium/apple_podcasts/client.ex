defmodule Lithium.ApplePodcasts.Client do
  @moduledoc false

  @behaviour Lithium.ApplePodcasts

  @host "https://amp-api.podcasts.apple.com"
  @origin "https://podcasts.apple.com"

  @impl true
  def followed_shows(user_token, opts) when is_binary(user_token) and is_list(opts) do
    with {:ok, token} <- developer_token() do
      collect(user_token, token, "/v1/me/library/podcasts?limit=25", opts, &map_show/1)
    end
  end

  @impl true
  def follow(user_token, show_id, opts)
      when is_binary(user_token) and is_binary(show_id) and is_list(opts) do
    with {:ok, token} <- developer_token() do
      case request(:post, library_path(show_id), user_token, token, opts) do
        {:ok, %Req.Response{status: status}} when status in [200, 202, 204] ->
          :ok

        {:ok, %Req.Response{status: status}} ->
          {:error, {:unexpected_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def unfollow(user_token, show_id, opts)
      when is_binary(user_token) and is_binary(show_id) and is_list(opts) do
    with {:ok, token} <- developer_token() do
      case request(:delete, library_path(show_id), user_token, token, opts) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          :ok

        {:ok, %Req.Response{}} ->
          {:error, :podcasts_probe_failed}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def episode_guids(user_token, storefront, show_id, opts)
      when is_binary(user_token) and is_binary(storefront) and is_binary(show_id) and
             is_list(opts) do
    path =
      "/v1/catalog/#{URI.encode(storefront)}/podcasts/#{URI.encode(show_id)}/episodes?limit=100"

    with {:ok, token} <- developer_token(),
         {:ok, guids} <- collect(user_token, token, path, opts, &map_guid/1) do
      {:ok, MapSet.new(guids)}
    end
  end

  defp collect(user_token, token, path, opts, mapper) do
    collect(user_token, token, path, opts, mapper, [], MapSet.new())
  end

  defp collect(_user_token, _token, nil, _opts, _mapper, acc, _seen), do: {:ok, acc}

  defp collect(user_token, token, path, opts, mapper, acc, seen) do
    if MapSet.member?(seen, path) do
      {:ok, acc}
    else
      case request(:get, path, user_token, token, opts) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          with {:ok, body} <- decode_json(response) do
            page = map_page(body, mapper)

            case next_path(body) do
              nil ->
                {:ok, acc ++ page}

              next ->
                collect(
                  user_token,
                  token,
                  next,
                  opts,
                  mapper,
                  acc ++ page,
                  MapSet.put(seen, path)
                )
            end
          end

        {:ok, %Req.Response{status: status}} ->
          {:error, {:unexpected_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp request(method, path, user_token, token, opts) do
    Req.request(
      method: method,
      url: absolute_url(path),
      headers: [
        {"authorization", "Bearer " <> token},
        {"media-user-token", user_token},
        {"origin", @origin}
      ],
      retry: false,
      plug: opts[:plug]
    )
  end

  defp developer_token do
    case Application.get_env(:lithium, :apple_podcasts_developer_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> Lithium.AppleToken.developer_token()
    end
  end

  defp absolute_url("http://" <> _ = url), do: url
  defp absolute_url("https://" <> _ = url), do: url
  defp absolute_url("/" <> _ = path), do: @host <> path
  defp absolute_url(path), do: @host <> "/" <> path

  defp library_path(show_id), do: "/v1/me/library/podcasts/" <> URI.encode(show_id)

  defp next_path(%{"next" => next}) when is_binary(next) and next != "", do: next
  defp next_path(_), do: nil

  defp map_page(body, mapper) do
    body
    |> data()
    |> Enum.flat_map(fn item ->
      case mapper.(item) do
        nil -> []
        value -> [value]
      end
    end)
  end

  defp data(%{"data" => items}) when is_list(items), do: items
  defp data(_), do: []

  defp map_show(%{"id" => id, "attributes" => %{"name" => name}})
       when is_binary(id) and is_binary(name) do
    %{id: id, name: name}
  end

  defp map_show(_), do: nil

  defp map_guid(%{"attributes" => %{"guid" => guid}}) when is_binary(guid), do: guid
  defp map_guid(_), do: nil

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
