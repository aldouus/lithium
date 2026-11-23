defmodule Lithium.Spotify.Client do
  @moduledoc false

  @behaviour Lithium.Spotify

  @api_base "https://api.spotify.com"
  @accounts_base "https://accounts.spotify.com"
  @page_size 50
  # PUT and DELETE /v1/me/library accept at most 40 URIs.
  @library_chunk 40
  @playlist_chunk 100
  # A short Retry-After is a burst limit. A long one is the quota window, and
  # the sync resumes later instead of sleeping inside this request.
  @retry_in_process_ms 5_000

  @doc """
  Returns a Spotify access token from `credentials["spotify"]`.

  A stored token whose `expires_at` unix second is still in the future comes
  back as `{:ok, token}`. A missing or expired token is refreshed with
  `refresh_token` and returned as `{:ok, token, credentials}` so the caller
  can persist the new `access_token` and `expires_at`.
  """
  def access_token(credentials, opts) when is_map(credentials) and is_list(opts) do
    spotify = spotify_section(credentials)

    case usable_token(spotify) do
      {:ok, token} -> {:ok, token}
      :refresh -> refresh_access_token(credentials, spotify, opts)
    end
  end

  @impl true
  def liked_songs(token, opts) when is_binary(token) and is_list(opts) do
    with {:ok, items} <- paginate(token, "/v1/me/tracks", opts) do
      {:ok, Enum.flat_map(items, &map_saved_track/1)}
    end
  end

  @impl true
  def saved_shows(token, opts) when is_binary(token) and is_list(opts) do
    with {:ok, items} <- paginate(token, "/v1/me/shows", opts) do
      {:ok, Enum.flat_map(items, &map_show/1)}
    end
  end

  @impl true
  def show_episodes(token, show_id, opts)
      when is_binary(token) and is_binary(show_id) and is_list(opts) do
    with {:ok, items} <- paginate(token, "/v1/shows/#{show_id}/episodes", opts) do
      {:ok, Enum.flat_map(items, &map_episode/1)}
    end
  end

  @impl true
  def playlists(token, opts) when is_binary(token) and is_list(opts) do
    with {:ok, items} <- paginate(token, "/v1/me/playlists", opts) do
      {:ok, Enum.flat_map(items, &map_playlist/1)}
    end
  end

  @impl true
  def playlist_tracks(token, playlist_id, opts)
      when is_binary(token) and is_binary(playlist_id) and is_list(opts) do
    with {:ok, items} <- paginate(token, "/v1/playlists/#{playlist_id}/items", opts) do
      {:ok, Enum.flat_map(items, &map_playlist_item/1)}
    end
  end

  @impl true
  def save_tracks(token, ids, opts), do: write_library(token, :put, "track", ids, opts)

  @impl true
  def remove_tracks(token, ids, opts), do: write_library(token, :delete, "track", ids, opts)

  @impl true
  def save_shows(token, ids, opts), do: write_library(token, :put, "show", ids, opts)

  @impl true
  def remove_shows(token, ids, opts), do: write_library(token, :delete, "show", ids, opts)

  @impl true
  def ensure_playlist(token, name, opts)
      when is_binary(token) and is_binary(name) and is_list(opts) do
    with {:ok, playlists} <- playlists(token, opts) do
      case Enum.find(playlists, &(&1.name == name)) do
        %{id: id} -> {:ok, id}
        nil -> create_playlist(token, name, opts)
      end
    end
  end

  @impl true
  def add_playlist_tracks(token, playlist_id, ids, opts) do
    write_playlist(token, :post, playlist_id, ids, opts, fn chunk ->
      %{"uris" => Enum.map(chunk, &track_uri/1)}
    end)
  end

  @impl true
  def remove_playlist_tracks(token, playlist_id, ids, opts) do
    write_playlist(token, :delete, playlist_id, ids, opts, fn chunk ->
      %{"items" => Enum.map(chunk, &%{"uri" => track_uri(&1)})}
    end)
  end

  @impl true
  def search_track(token, isrc, opts)
      when is_binary(token) and is_binary(isrc) and is_list(opts) do
    params = [q: "isrc:#{isrc}", type: "track", limit: 5]

    with {:ok, %{body: body}} <- request(token, :get, "/v1/search", [params: params], opts) do
      track =
        body
        |> search_items()
        |> Enum.find_value(fn item ->
          if isrc_match?(get_in(item, ["external_ids", "isrc"]), isrc), do: map_track(item)
        end)

      {:ok, track}
    end
  end

  defp write_library(_token, _method, _type, [], _opts), do: :ok

  defp write_library(token, method, type, ids, opts)
       when is_binary(token) and is_list(ids) and is_list(opts) do
    ids
    |> Enum.chunk_every(@library_chunk)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      uris = Enum.map_join(chunk, ",", &"spotify:#{type}:#{&1}")

      # Spotify's load balancer rejects a PUT or DELETE that has no body and
      # no Content-Length, with an HTML 411 that says the request was a POST.
      case request(token, method, "/v1/me/library", [params: [uris: uris], body: ""], opts) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp write_playlist(_token, _method, _playlist_id, [], _opts, _body_fun), do: :ok

  defp write_playlist(token, method, playlist_id, ids, opts, body_fun)
       when is_binary(token) and is_binary(playlist_id) and is_list(ids) and is_list(opts) do
    path = "/v1/playlists/#{playlist_id}/items"

    ids
    |> Enum.chunk_every(@playlist_chunk)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case request(token, method, path, [json: body_fun.(chunk)], opts) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp create_playlist(token, name, opts) do
    json = %{"name" => name, "public" => false}

    case request(token, :post, "/v1/me/playlists", [json: json], opts) do
      {:ok, %{body: %{"id" => id}}} when is_binary(id) and id != "" ->
        {:ok, id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:spotify, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp paginate(token, path, opts) do
    fetch_page(token, path, [limit: @page_size], opts, [])
  end

  defp fetch_page(token, url, params, opts, acc) do
    case request(token, :get, url, [params: params], opts) do
      {:ok, %{status: status, body: body}} when is_map(body) ->
        case body["items"] || [] do
          items when is_list(items) ->
            acc = acc ++ items

            case body["next"] do
              next when is_binary(next) and next != "" ->
                fetch_page(token, next, [], opts, acc)

              _ ->
                {:ok, acc}
            end

          _ ->
            {:error, {:spotify, status, body}}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:spotify, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp request(token, method, url, extra, opts) do
    Lithium.Spotify.Pace.wait()
    options = Keyword.merge(extra, method: method, url: url)

    token
    |> api_request(opts)
    |> Req.request(options)
    |> normalize()
  end

  defp api_request(token, opts) do
    Req.new(
      base_url: @api_base,
      auth: {:bearer, token},
      plug: opts[:plug],
      retry: &rate_limit_retry/2,
      max_retries: 5
    )
  end

  defp rate_limit_retry(_request, %{status: status} = response)
       when status in [408, 429, 500, 502, 503, 504] do
    delay = retry_delay_ms(response)

    if status == 429 and delay > @retry_in_process_ms do
      false
    else
      {:delay, min(delay, @retry_in_process_ms)}
    end
  end

  defp rate_limit_retry(_request, _response), do: false

  defp retry_delay_ms(response) do
    case Req.Response.get_retry_after(response) do
      milliseconds when is_integer(milliseconds) and milliseconds >= 0 -> milliseconds
      _ -> 1_000
    end
  end

  defp refresh_access_token(credentials, spotify, opts) do
    case spotify["refresh_token"] do
      refresh when is_binary(refresh) and refresh != "" ->
        post_refresh(credentials, spotify, refresh, opts)

      _ ->
        {:error, :missing_credentials}
    end
  end

  defp post_refresh(credentials, spotify, refresh, opts) do
    result =
      Req.new(
        base_url: @accounts_base,
        auth: {:basic, client_userinfo()},
        plug: opts[:plug],
        retry: false
      )
      |> Req.post(url: "/api/token", form: [grant_type: "refresh_token", refresh_token: refresh])
      |> normalize()

    case result do
      {:ok, %{body: %{"access_token" => token} = body}} when is_binary(token) and token != "" ->
        updated = Map.put(credentials, "spotify", store_token(spotify, body, token))
        {:ok, token, updated}

      {:ok, %{status: status, body: body}} ->
        {:error, {:spotify, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp store_token(spotify, body, token) do
    expires_in =
      case body["expires_in"] do
        seconds when is_integer(seconds) and seconds > 0 -> seconds
        _ -> 3600
      end

    spotify
    |> Map.put("access_token", token)
    |> Map.put("expires_at", System.os_time(:second) + expires_in)
    |> put_refresh_token(body["refresh_token"])
  end

  defp put_refresh_token(spotify, refresh) when is_binary(refresh) and refresh != "" do
    Map.put(spotify, "refresh_token", refresh)
  end

  defp put_refresh_token(spotify, _), do: spotify

  defp client_userinfo do
    id = Application.get_env(:lithium, :spotify_client_id)
    secret = Application.get_env(:lithium, :spotify_client_secret)
    "#{id}:#{secret}"
  end

  defp spotify_section(%{"spotify" => spotify}) when is_map(spotify), do: spotify
  defp spotify_section(_), do: %{}

  defp usable_token(%{"access_token" => token, "expires_at" => expires_at})
       when is_binary(token) and token != "" and is_integer(expires_at) do
    if expires_at > System.os_time(:second) do
      {:ok, token}
    else
      :refresh
    end
  end

  defp usable_token(_), do: :refresh

  defp normalize({:ok, %{status: status} = response}) when status in 200..299, do: {:ok, response}

  defp normalize({:ok, %{status: 400, body: %{"error" => "invalid_grant"}}}) do
    {:error, :spotify_auth}
  end

  defp normalize({:ok, %{status: 401}}), do: {:error, :spotify_auth}

  defp normalize({:ok, %{status: 429} = response}) do
    seconds = max(div(retry_delay_ms(response), 1_000), 1)
    {:error, {:spotify_rate_limit, seconds}}
  end

  defp normalize({:ok, %{status: status, body: body}}), do: {:error, {:spotify, status, body}}

  defp normalize({:error, reason}), do: {:error, reason}

  defp map_saved_track(%{"track" => track}) when is_map(track), do: [map_track(track)]
  defp map_saved_track(_), do: []

  defp map_playlist_item(item) when is_map(item) do
    media = playlist_media(item)

    cond do
      not is_map(media) -> []
      local?(item, media) -> []
      not present_isrc?(media) -> []
      true -> [map_track(media)]
    end
  end

  defp map_playlist_item(_), do: []

  defp playlist_media(%{"item" => item}) when is_map(item), do: item
  defp playlist_media(%{"track" => track}) when is_map(track), do: track
  defp playlist_media(_), do: nil

  defp local?(wrapper, media) do
    wrapper["is_local"] == true or media["is_local"] == true
  end

  defp present_isrc?(media) do
    case get_in(media, ["external_ids", "isrc"]) do
      isrc when is_binary(isrc) and isrc != "" -> true
      _ -> false
    end
  end

  defp map_track(track) when is_map(track) do
    %{
      id: track["id"],
      isrc: get_in(track, ["external_ids", "isrc"]),
      album: get_in(track, ["album", "name"]),
      duration_ms: track["duration_ms"]
    }
  end

  defp map_track(_), do: nil

  defp map_show(%{"show" => show}) when is_map(show), do: map_show(show)

  defp map_show(%{"id" => id, "name" => name}) when is_binary(id) and is_binary(name) do
    [%{id: id, name: name}]
  end

  defp map_show(_), do: []

  defp map_episode(%{"name" => name, "release_date" => release_date})
       when is_binary(name) and is_binary(release_date) do
    [%{name: name, release_date: release_date}]
  end

  defp map_episode(_), do: []

  defp map_playlist(%{"id" => id, "name" => name}) when is_binary(id) and is_binary(name) do
    [%{id: id, name: name}]
  end

  defp map_playlist(_), do: []

  defp search_items(body) when is_map(body) do
    case get_in(body, ["tracks", "items"]) do
      items when is_list(items) -> items
      _ -> []
    end
  end

  defp search_items(_), do: []

  defp isrc_match?(candidate, expected) when is_binary(candidate) and is_binary(expected) do
    String.downcase(candidate) == String.downcase(expected)
  end

  defp isrc_match?(_, _), do: false

  defp track_uri(id), do: "spotify:track:#{id}"
end
