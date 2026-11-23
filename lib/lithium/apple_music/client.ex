defmodule Lithium.AppleMusic.Client do
  @moduledoc false

  @behaviour Lithium.AppleMusic

  @api "https://api.music.apple.com"
  @web "https://amp-api.music.apple.com"
  @origin "https://music.apple.com"
  @page_limit 100
  @favorite_chunk 20
  @isrc_chunk 25

  @impl true
  def favorites(user_token, _storefront, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token(),
         {:ok, pages} <-
           pages(token, user_token, "/v1/me/library/songs", song_params(), opts) do
      {:ok, Enum.flat_map(pages, &favorite_tracks/1)}
    end
  end

  @impl true
  def add_favorites(user_token, ids, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token() do
      favorite_ids(token, user_token, ids, :post, opts)
    end
  end

  @impl true
  def remove_favorites(user_token, ids, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token() do
      favorite_ids(token, user_token, ids, :delete, opts)
    end
  end

  @impl true
  def songs_by_isrc(user_token, storefront, isrcs, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token() do
      isrcs
      |> Enum.chunk_every(@isrc_chunk)
      |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
        case get_body(token, user_token, isrc_url(storefront, chunk), opts) do
          {:ok, body} -> {:cont, {:ok, acc ++ catalog_tracks(body)}}
          error -> {:halt, error}
        end
      end)
    end
  end

  @impl true
  def playlists(user_token, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token(),
         {:ok, pages} <-
           pages(token, user_token, "/v1/me/library/playlists", [limit: @page_limit], opts) do
      {:ok, Enum.flat_map(pages, &map_playlists/1)}
    end
  end

  @impl true
  def playlist_tracks(user_token, playlist_id, opts) do
    path = "/v1/me/library/playlists/#{playlist_id}/tracks"

    with {:ok, token} <- Lithium.AppleToken.developer_token(),
         {:ok, pages} <-
           pages(token, user_token, path, [include: "catalog", limit: @page_limit], opts) do
      {:ok, Enum.flat_map(pages, &library_tracks/1)}
    end
  end

  @impl true
  def ensure_playlist(user_token, name, opts) do
    with {:ok, playlists} <- playlists(user_token, opts) do
      case Enum.find(playlists, &(&1.name == name and &1.can_edit)) do
        %{id: id} ->
          {:ok, id}

        nil ->
          with {:ok, token} <- Lithium.AppleToken.developer_token() do
            create_playlist(token, user_token, name, opts)
          end
      end
    end
  end

  @impl true
  def add_playlist_tracks(user_token, playlist_id, ids, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token() do
      url = api_url("/v1/me/library/playlists/#{playlist_id}/tracks")
      json = %{"data" => Enum.map(ids, &%{"id" => &1, "type" => "songs"})}

      case request(:post, url, api_headers(token, user_token), opts, json: json) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, %{status: status}} -> {:error, {:http, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def remove_playlist_tracks(user_token, playlist_id, tracks, opts) do
    with {:ok, token} <- Lithium.AppleToken.developer_token() do
      url = @web <> "/v1/me/library/playlists/#{playlist_id}/tracks"

      headers = [
        {"authorization", "Bearer " <> token},
        {"media-user-token", user_token},
        {"origin", @origin}
      ]

      json = %{"data" => Enum.map(tracks, &%{"id" => &1.id, "type" => "songs"})}

      case request(:delete, url, headers, opts, json: json) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, _response} -> {:error, :playlist_probe_failed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp song_params do
    [extend: "inFavorites", include: "catalog", limit: @page_limit]
  end

  defp pages(token, user_token, path, params, opts, acc \\ []) do
    case get_body(token, user_token, api_url(path), opts, params) do
      {:ok, body} ->
        case next_target(body) do
          nil ->
            {:ok, Enum.reverse([body | acc])}

          {next_path, next_params} ->
            pages(token, user_token, next_path, next_params, opts, [body | acc])
        end

      error ->
        error
    end
  end

  defp next_target(%{"next" => next}) when is_binary(next) and next != "" do
    uri = URI.parse(next)
    path = uri.path || next

    params =
      if is_binary(uri.query) and uri.query != "", do: URI.decode_query(uri.query), else: []

    {path, params}
  end

  defp next_target(_), do: nil

  defp favorite_ids(token, user_token, ids, method, opts) do
    ids
    |> Enum.chunk_every(@favorite_chunk)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case favorite_request(token, user_token, chunk, method, opts) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp favorite_request(token, user_token, ids, method, opts) do
    case request(method, favorites_url(ids), api_headers(token, user_token), opts, []) do
      {:ok, %{status: 202}} when method == :post ->
        :ok

      {:ok, %{status: status}} when method == :delete and status in [200, 202, 204] ->
        :ok

      {:ok, _response} when method == :delete ->
        {:error, :favorites_probe_failed}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp favorites_url(ids) do
    @api <> "/v1/me/favorites?ids[songs]=" <> Enum.join(ids, ",")
  end

  defp isrc_url(storefront, isrcs) do
    @api <> "/v1/catalog/#{storefront}/songs?filter[isrc]=" <> Enum.join(isrcs, ",")
  end

  defp create_playlist(token, user_token, name, opts) do
    json = %{"attributes" => %{"name" => name}}

    case request(:post, api_url("/v1/me/library/playlists"), api_headers(token, user_token), opts,
           json: json
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case decode(body) do
          %{"data" => [%{"id" => id} | _]} when is_binary(id) -> {:ok, id}
          _ -> {:error, :missing_playlist}
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_body(token, user_token, url, opts, params \\ []) do
    extra = if params in [[], %{}], do: [], else: [params: params]

    case request(:get, url, api_headers(token, user_token), opts, extra) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, decode(body)}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(method, url, headers, opts, extra) do
    Req.request(
      [method: method, url: url, headers: headers, retry: false, plug: opts[:plug]] ++ extra
    )
  end

  defp api_url("https://" <> _ = url), do: url
  defp api_url(path), do: @api <> path

  defp api_headers(token, user_token) do
    [
      {"authorization", "Bearer " <> token},
      {"music-user-token", user_token}
    ]
  end

  defp decode(%{} = body), do: body

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> decoded
      _ -> %{}
    end
  end

  defp decode(_), do: %{}

  defp favorite_tracks(body) do
    included = included_by_id(body)

    body
    |> data()
    |> Enum.filter(&in_favorites?/1)
    |> Enum.map(&library_track(&1, included))
  end

  defp library_tracks(body) do
    included = included_by_id(body)
    Enum.map(data(body), &library_track(&1, included))
  end

  defp catalog_tracks(body) do
    Enum.map(data(body), fn song ->
      attributes = song["attributes"] || %{}

      %{
        id: song["id"],
        isrc: attributes["isrc"],
        album: attributes["albumName"],
        duration_ms: attributes["durationInMillis"]
      }
    end)
  end

  defp map_playlists(body) do
    Enum.map(data(body), fn playlist ->
      attributes = playlist["attributes"] || %{}

      %{
        id: playlist["id"],
        name: attributes["name"],
        can_edit: attributes["canEdit"] == true
      }
    end)
  end

  defp library_track(song, included) do
    catalog_id = catalog_id(song)
    attributes = catalog_attributes(song, included, catalog_id)

    %{
      id: catalog_id || song["id"],
      isrc: attributes["isrc"],
      album: attributes["albumName"],
      duration_ms: attributes["durationInMillis"]
    }
  end

  defp catalog_id(song) do
    relationship_id(song) || play_params_catalog_id(song)
  end

  defp relationship_id(song) do
    case get_in(song, ["relationships", "catalog", "data"]) do
      [%{"id" => id} | _] -> present_id(id)
      _ -> nil
    end
  end

  defp play_params_catalog_id(song) do
    present_id(get_in(song, ["attributes", "playParams", "catalogId"]))
  end

  defp present_id(id) when is_binary(id) and id != "", do: id
  defp present_id(_), do: nil

  defp catalog_attributes(song, included, id) do
    Map.merge(inline_catalog_attributes(song), included_attributes(included, id))
  end

  defp inline_catalog_attributes(song) do
    case get_in(song, ["relationships", "catalog", "data"]) do
      [%{"attributes" => attributes} | _] when is_map(attributes) -> attributes
      _ -> %{}
    end
  end

  defp included_attributes(_included, nil), do: %{}

  defp included_attributes(included, id) do
    case included do
      %{^id => %{"attributes" => attributes}} when is_map(attributes) -> attributes
      _ -> %{}
    end
  end

  defp included_by_id(body) do
    for %{"id" => id} = item <- body["included"] || [], into: %{}, do: {id, item}
  end

  defp data(body), do: body["data"] || []

  defp in_favorites?(song) do
    get_in(song, ["attributes", "inFavorites"]) == true
  end
end
