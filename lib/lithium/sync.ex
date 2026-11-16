defmodule Lithium.Sync do
  @moduledoc """
  One sync pass for a tenant.

  Favorites, shows, and named playlists are diffed from the stored snapshot.
  Clients, diff, and match functions default to the production modules and can
  be replaced in tests. A key that cannot be resolved is left where it is.
  An Apple delete that fails its probe stops that collection only.
  """

  @option_keys [
    :spotify,
    :apple_music,
    :apple_podcasts,
    :listen_notes,
    :feeds,
    :diff,
    :song_key,
    :choose_song,
    :confirm_show
  ]

  def run(tenant_id, opts \\ []) when is_binary(tenant_id) and is_list(opts) do
    opts = Keyword.merge(defaults(), opts)

    with {:ok, credentials} <- Lithium.Credentials.read(tenant_id),
         {:ok, spotify_token, credentials} <-
           spotify_session(tenant_id, credentials, opts[:spotify], http_opts(opts)),
         {:ok, apple} <- apple_tokens(credentials) do
      ctx = context(tenant_id, opts, spotify_token, apple)

      report = %{
        favorites: sync_favorites(ctx),
        shows: sync_shows(ctx),
        playlists: sync_playlists(ctx)
      }

      schedule_next(tenant_id)
      {:ok, report}
    end
  end

  defp defaults do
    [
      spotify: Lithium.Spotify.Client,
      apple_music: Lithium.AppleMusic.Client,
      apple_podcasts: Lithium.ApplePodcasts.Client,
      listen_notes: Lithium.ListenNotes.Client,
      feeds: Lithium.Feeds.Client,
      diff: &engine_diff/4,
      song_key: &song_key/1,
      choose_song: &choose_song/3,
      confirm_show: &confirm_show/2
    ]
  end

  defp engine_diff(apple, spotify, snapshot, priority) do
    apply(Lithium.Engine, :diff, [apple, spotify, snapshot, priority])
  end

  defp song_key(track), do: apply(Lithium.Match.Songs, :key, [track])

  defp choose_song(isrc, candidates, reference) do
    apply(Lithium.Match.Songs, :choose, [isrc, candidates, reference])
  end

  defp confirm_show(left, right), do: apply(Lithium.Match.Shows, :confirm, [left, right])

  defp http_opts(opts), do: Keyword.drop(opts, @option_keys)

  defp spotify_session(tenant_id, credentials, spotify, http) do
    case spotify.access_token(credentials, http) do
      {:ok, token, refreshed} when is_binary(token) and is_map(refreshed) ->
        :ok = write_credentials(tenant_id, refreshed)
        {:ok, token, refreshed}

      {:ok, token} when is_binary(token) ->
        {:ok, token, credentials}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_credentials(tenant_id, credentials) do
    {:ok, path} = Lithium.Tenant.credentials_path(tenant_id)
    File.write!(path, Jason.encode!(credentials))
    File.chmod!(path, 0o600)
    :ok
  end

  defp apple_tokens(credentials) do
    with {:ok, music} <- Lithium.Credentials.token(credentials, "apple_music", "user_token"),
         {:ok, podcasts} <- Lithium.Credentials.token(credentials, "apple_podcasts", "user_token") do
      {:ok,
       %{
         music: music,
         podcasts: podcasts,
         storefront: storefront(credentials, "apple_music"),
         podcasts_storefront: storefront(credentials, "apple_podcasts")
       }}
    end
  end

  defp storefront(credentials, service) do
    case Lithium.Credentials.token(credentials, service, "storefront") do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> "us"
    end
  end

  defp context(tenant_id, opts, spotify_token, apple) do
    settings = read_settings(tenant_id)

    %{
      tenant_id: tenant_id,
      http: http_opts(opts),
      priority: settings.priority,
      playlist_names: settings.playlist_names,
      spotify_token: spotify_token,
      music_token: apple.music,
      podcasts_token: apple.podcasts,
      storefront: apple.storefront,
      podcasts_storefront: apple.podcasts_storefront,
      spotify: opts[:spotify],
      apple_music: opts[:apple_music],
      apple_podcasts: opts[:apple_podcasts],
      listen_notes: opts[:listen_notes],
      feeds: opts[:feeds],
      diff: opts[:diff],
      song_key: opts[:song_key],
      choose_song: opts[:choose_song],
      confirm_show: opts[:confirm_show]
    }
  end

  defp read_settings(tenant_id) do
    store!(tenant_id, fn conn ->
      %{
        priority: Lithium.Store.priority(conn),
        playlist_names: Lithium.Store.playlist_names(conn)
      }
    end)
  end

  defp schedule_next(tenant_id) do
    now = System.system_time(:second)

    store!(tenant_id, fn conn ->
      Lithium.Store.put_next_run(conn, now + Lithium.Store.interval(conn))
    end)
  end

  defp sync_favorites(ctx) do
    apple =
      load_songs(
        fn -> ctx.apple_music.favorites(ctx.music_token, ctx.storefront, ctx.http) end,
        ctx
      )

    spotify = load_songs(fn -> ctx.spotify.liked_songs(ctx.spotify_token, ctx.http) end, ctx)

    case diff_sets(ctx, side_keys(apple), side_keys(spotify), "favorites") do
      {:skipped, reason} ->
        {:skipped, reason}

      {:ok, plan} ->
        case apply_favorite_plan(ctx, plan, side_index(apple), side_index(spotify)) do
          :ok -> snapshot_favorites(ctx)
          other -> other
        end
    end
  end

  defp apply_favorite_plan(ctx, plan, apple_index, spotify_index) do
    with :ok <-
           delete_apple_favorites(ctx, indexed_ids(plan_field(plan, :apple_remove), apple_index)),
         :ok <-
           add_apple_favorites(ctx, plan_field(plan, :apple_add), spotify_index, apple_index),
         :ok <-
           delete_spotify_tracks(
             ctx,
             indexed_ids(plan_field(plan, :spotify_remove), spotify_index)
           ),
         :ok <- add_spotify_tracks(ctx, plan_field(plan, :spotify_add)) do
      :ok
    end
  end

  defp delete_apple_favorites(_ctx, []), do: :ok

  defp delete_apple_favorites(ctx, ids) do
    probe(ctx, "favorites", :favorites_probe_failed, fn ->
      ctx.apple_music.remove_favorites(ctx.music_token, ids, ctx.http)
    end)
  end

  defp add_apple_favorites(ctx, keys, primary, fallback) do
    case resolve_apple_ids(ctx, keys, primary, fallback) do
      [] -> :ok
      ids -> ctx.apple_music.add_favorites(ctx.music_token, ids, ctx.http)
    end
  end

  defp delete_spotify_tracks(_ctx, []), do: :ok

  defp delete_spotify_tracks(ctx, ids) do
    ctx.spotify.remove_tracks(ctx.spotify_token, ids, ctx.http)
  end

  defp add_spotify_tracks(ctx, keys) do
    case resolve_spotify_ids(ctx, keys) do
      [] -> :ok
      ids -> ctx.spotify.save_tracks(ctx.spotify_token, ids, ctx.http)
    end
  end

  defp snapshot_favorites(ctx) do
    apple =
      load_songs(
        fn -> ctx.apple_music.favorites(ctx.music_token, ctx.storefront, ctx.http) end,
        ctx
      )

    spotify = load_songs(fn -> ctx.spotify.liked_songs(ctx.spotify_token, ctx.http) end, ctx)

    case {apple, spotify} do
      {{:ok, apple_keys, _}, {:ok, spotify_keys, _}} ->
        write_snapshot(ctx.tenant_id, "favorites", apple_keys, spotify_keys)
        :ok

      _ ->
        {:error, :unreadable}
    end
  end

  defp sync_shows(ctx) do
    case current_shows(ctx) do
      {:ok, apple_keys, spotify_keys, apple_index, spotify_index} ->
        case diff_sets(ctx, apple_keys, spotify_keys, "shows") do
          {:skipped, reason} ->
            {:skipped, reason}

          {:ok, plan} ->
            case apply_show_plan(ctx, plan, apple_index, spotify_index) do
              :ok -> snapshot_shows(ctx)
              other -> other
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_shows(ctx) do
    with {:ok, spotify_shows} <- ctx.spotify.saved_shows(ctx.spotify_token, ctx.http),
         {:ok, apple_shows} <- ctx.apple_podcasts.followed_shows(ctx.podcasts_token, ctx.http),
         {:ok, apple_keys, spotify_keys, apple_index, spotify_index} <-
           match_shows(ctx, spotify_shows, apple_shows) do
      {:ok, apple_keys, spotify_keys, apple_index, spotify_index}
    end
  end

  defp match_shows(_ctx, [], _apple_shows) do
    {:ok, MapSet.new(), MapSet.new(), %{}, %{}}
  end

  defp match_shows(ctx, spotify_shows, apple_shows) do
    followed = MapSet.new(Enum.map(apple_shows, & &1.id))

    with {:ok, rows} when is_list(rows) <-
           ctx.listen_notes.lookup(Enum.map(spotify_shows, & &1.id), ctx.http) do
      rows = Map.new(rows, &{&1.spotify_id, &1})

      {apple_keys, spotify_keys, apple_index, spotify_index} =
        Enum.reduce(spotify_shows, {MapSet.new(), MapSet.new(), %{}, %{}}, fn show, acc ->
          case Map.get(rows, show.id) do
            nil -> acc
            row -> confirm_spotify_show(ctx, show, row, followed, acc)
          end
        end)

      {:ok, apple_keys, spotify_keys, apple_index, spotify_index}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp confirm_spotify_show(ctx, show, row, followed, acc) do
    itunes = itunes_text(Map.get(row, :itunes_id))
    feed_url = Map.get(row, :feed_url)

    with true <- is_binary(itunes) and itunes != "",
         true <- is_binary(feed_url) and feed_url != "",
         {:ok, feed} <- ctx.feeds.show_identity(feed_url, ctx.http),
         {:ok, guids} <-
           ctx.apple_podcasts.episode_guids(
             ctx.podcasts_token,
             ctx.podcasts_storefront,
             itunes,
             ctx.http
           ),
         {:ok, _} <-
           ctx.confirm_show.(episode_identity(feed), %{podcast_guid: nil, episode_guids: guids}) do
      remember_show(show, itunes, followed, acc)
    else
      _ -> acc
    end
  end

  defp episode_identity(%{episode_guids: %MapSet{} = guids}),
    do: %{podcast_guid: nil, episode_guids: guids}

  defp episode_identity(_feed), do: %{podcast_guid: nil, episode_guids: MapSet.new()}

  defp remember_show(
         show,
         itunes,
         followed,
         {apple_keys, spotify_keys, apple_index, spotify_index}
       ) do
    key = "itunes:" <> itunes
    spotify_index = Map.put(spotify_index, key, %{id: show.id})
    spotify_keys = MapSet.put(spotify_keys, key)

    if MapSet.member?(followed, itunes) do
      {MapSet.put(apple_keys, key), spotify_keys, Map.put(apple_index, key, %{id: itunes}),
       spotify_index}
    else
      {apple_keys, spotify_keys, apple_index, spotify_index}
    end
  end

  defp itunes_text(id) when is_binary(id), do: id
  defp itunes_text(id) when is_integer(id), do: Integer.to_string(id)
  defp itunes_text(_id), do: nil

  defp apply_show_plan(ctx, plan, apple_index, spotify_index) do
    with :ok <- unfollow_shows(ctx, show_ids(plan_field(plan, :apple_remove), apple_index)),
         :ok <- follow_shows(ctx, show_ids(plan_field(plan, :apple_add), apple_index)),
         :ok <-
           write_spotify_shows(
             ctx,
             :remove_shows,
             indexed_ids(plan_field(plan, :spotify_remove), spotify_index)
           ),
         :ok <-
           write_spotify_shows(
             ctx,
             :save_shows,
             indexed_ids(plan_field(plan, :spotify_add), spotify_index)
           ) do
      :ok
    end
  end

  defp unfollow_shows(_ctx, []), do: :ok

  defp unfollow_shows(ctx, ids) do
    probed? = probed?(ctx.tenant_id, "shows")

    ids
    |> Enum.reduce_while({:ok, probed?}, fn id, {:ok, probed?} ->
      case ctx.apple_podcasts.unfollow(ctx.podcasts_token, id, ctx.http) do
        :ok ->
          unless probed?, do: mark_probed(ctx.tenant_id, "shows")
          {:cont, {:ok, true}}

        {:error, :podcasts_probe_failed} when not probed? ->
          {:halt, {:skipped, :podcasts_probe_failed}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _probed?} -> :ok
      other -> other
    end
  end

  defp follow_shows(_ctx, []), do: :ok

  defp follow_shows(ctx, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case ctx.apple_podcasts.follow(ctx.podcasts_token, id, ctx.http) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_spotify_shows(_ctx, _fun, []), do: :ok

  defp write_spotify_shows(ctx, fun, ids) do
    apply(ctx.spotify, fun, [ctx.spotify_token, ids, ctx.http])
  end

  defp snapshot_shows(ctx) do
    case current_shows(ctx) do
      {:ok, apple_keys, spotify_keys, _apple_index, _spotify_index} ->
        write_snapshot(ctx.tenant_id, "shows", apple_keys, spotify_keys)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp show_ids(keys, index) do
    keys
    |> each_key()
    |> Enum.map(fn key ->
      case Map.get(index, key) do
        %{id: id} when is_binary(id) and id != "" -> id
        _ -> itunes_suffix(key)
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp itunes_suffix("itunes:" <> id) when id != "", do: id
  defp itunes_suffix(_key), do: nil

  defp sync_playlists(ctx) do
    case ctx.playlist_names do
      [] ->
        :ok

      names ->
        names
        |> Enum.reduce_while(:none, fn name, acc -> reduce_playlist(ctx, name, acc) end)
        |> normalize_playlist_result()
    end
  end

  defp reduce_playlist(ctx, name, acc) do
    case sync_playlist(ctx, name) do
      :ok ->
        {:cont, :ok}

      {:skipped, :playlist_probe_failed} = skipped ->
        {:halt, skipped}

      {:skipped, reason} ->
        {:cont, keep_playlist_skip(acc, reason)}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp keep_playlist_skip(:ok, _reason), do: :ok
  defp keep_playlist_skip({:skipped, reason}, _reason), do: {:skipped, reason}
  defp keep_playlist_skip(:none, reason), do: {:skipped, reason}

  defp normalize_playlist_result(:none), do: :ok
  defp normalize_playlist_result(result), do: result

  defp sync_playlist(ctx, name) do
    with {:ok, apple_id} when is_binary(apple_id) <-
           ctx.apple_music.ensure_playlist(ctx.music_token, name, ctx.http),
         {:ok, spotify_id} when is_binary(spotify_id) <-
           ctx.spotify.ensure_playlist(ctx.spotify_token, name, ctx.http) do
      apple =
        load_songs(
          fn -> ctx.apple_music.playlist_tracks(ctx.music_token, apple_id, ctx.http) end,
          ctx
        )

      spotify =
        load_songs(
          fn -> ctx.spotify.playlist_tracks(ctx.spotify_token, spotify_id, ctx.http) end,
          ctx
        )

      case diff_sets(ctx, side_keys(apple), side_keys(spotify), "playlist:" <> name) do
        {:skipped, reason} ->
          {:skipped, reason}

        {:ok, plan} ->
          case apply_playlist_plan(ctx, plan, apple, spotify, apple_id, spotify_id) do
            :ok -> snapshot_playlist(ctx, name, apple_id, spotify_id)
            other -> other
          end
      end
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp apply_playlist_plan(ctx, plan, apple, spotify, apple_id, spotify_id) do
    apple_index = side_index(apple)
    spotify_index = side_index(spotify)

    with :ok <-
           delete_apple_playlist_tracks(
             ctx,
             apple_id,
             tracks_for(plan_field(plan, :apple_remove), apple_index)
           ),
         :ok <-
           add_apple_playlist_tracks(
             ctx,
             apple_id,
             plan_field(plan, :apple_add),
             spotify_index,
             apple_index
           ),
         :ok <-
           delete_spotify_playlist_tracks(
             ctx,
             spotify_id,
             indexed_ids(plan_field(plan, :spotify_remove), spotify_index)
           ),
         :ok <-
           add_spotify_playlist_tracks(ctx, spotify_id, plan_field(plan, :spotify_add)) do
      :ok
    end
  end

  defp delete_apple_playlist_tracks(_ctx, _playlist_id, []), do: :ok

  defp delete_apple_playlist_tracks(ctx, playlist_id, tracks) do
    probe(ctx, "playlists", :playlist_probe_failed, fn ->
      ctx.apple_music.remove_playlist_tracks(ctx.music_token, playlist_id, tracks, ctx.http)
    end)
  end

  defp add_apple_playlist_tracks(ctx, playlist_id, keys, primary, fallback) do
    case resolve_apple_ids(ctx, keys, primary, fallback) do
      [] -> :ok
      ids -> ctx.apple_music.add_playlist_tracks(ctx.music_token, playlist_id, ids, ctx.http)
    end
  end

  defp delete_spotify_playlist_tracks(_ctx, _playlist_id, []), do: :ok

  defp delete_spotify_playlist_tracks(ctx, playlist_id, ids) do
    ctx.spotify.remove_playlist_tracks(ctx.spotify_token, playlist_id, ids, ctx.http)
  end

  defp add_spotify_playlist_tracks(ctx, playlist_id, keys) do
    case resolve_spotify_ids(ctx, keys) do
      [] -> :ok
      ids -> ctx.spotify.add_playlist_tracks(ctx.spotify_token, playlist_id, ids, ctx.http)
    end
  end

  defp snapshot_playlist(ctx, name, apple_id, spotify_id) do
    apple =
      load_songs(
        fn -> ctx.apple_music.playlist_tracks(ctx.music_token, apple_id, ctx.http) end,
        ctx
      )

    spotify =
      load_songs(
        fn -> ctx.spotify.playlist_tracks(ctx.spotify_token, spotify_id, ctx.http) end,
        ctx
      )

    case {apple, spotify} do
      {{:ok, apple_keys, _}, {:ok, spotify_keys, _}} ->
        write_snapshot(ctx.tenant_id, "playlist:" <> name, apple_keys, spotify_keys)
        :ok

      _ ->
        {:error, :unreadable}
    end
  end

  defp probe(ctx, flag, probe_error, fun) do
    probed? = probed?(ctx.tenant_id, flag)

    case fun.() do
      :ok ->
        unless probed?, do: mark_probed(ctx.tenant_id, flag)
        :ok

      {:error, ^probe_error} when not probed? ->
        {:skipped, probe_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp diff_sets(ctx, apple_keys, spotify_keys, collection) do
    snapshot = read_snapshot(ctx.tenant_id, collection)

    case ctx.diff.(apple_keys, spotify_keys, snapshot, ctx.priority) do
      {:skip, reason} -> {:skipped, reason}
      {:ok, plan} -> {:ok, plan}
    end
  end

  defp load_songs(loader, ctx) do
    case loader.() do
      {:ok, tracks} when is_list(tracks) ->
        {keys, index} = index_tracks(tracks, ctx.song_key)
        {:ok, keys, index}

      {:error, _reason} ->
        :unreadable
    end
  end

  defp side_keys({:ok, keys, _index}), do: keys
  defp side_keys(:unreadable), do: :unreadable

  defp side_index({:ok, _keys, index}), do: index
  defp side_index(:unreadable), do: %{}

  defp index_tracks(tracks, song_key) do
    Enum.reduce(tracks, {MapSet.new(), %{}}, fn track, {keys, index} ->
      case song_key.(track) do
        {:ok, key} when is_binary(key) and key != "" ->
          {MapSet.put(keys, key), Map.put(index, key, track)}

        _ ->
          {keys, index}
      end
    end)
  end

  defp resolve_apple_ids(ctx, keys, primary, fallback) do
    case each_key(keys) do
      [] ->
        []

      isrcs ->
        case ctx.apple_music.songs_by_isrc(ctx.music_token, ctx.storefront, isrcs, ctx.http) do
          {:ok, candidates} when is_list(candidates) ->
            Enum.map(isrcs, fn isrc ->
              reference = reference_for(isrc, primary, fallback)
              chosen_id(ctx.choose_song.(isrc, candidates, reference))
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          _ ->
            []
        end
    end
  end

  defp resolve_spotify_ids(ctx, keys) do
    keys
    |> each_key()
    |> Enum.map(fn isrc ->
      case ctx.spotify.search_track(ctx.spotify_token, isrc, ctx.http) do
        {:ok, %{id: id}} when is_binary(id) and id != "" -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp reference_for(key, primary, fallback) do
    track = Map.get(primary, key) || Map.get(fallback, key) || %{}
    %{album: Map.get(track, :album), duration_ms: Map.get(track, :duration_ms)}
  end

  defp chosen_id({:ok, %{id: id}}) when is_binary(id) and id != "", do: id
  defp chosen_id(_other), do: nil

  defp indexed_ids(keys, index) do
    keys
    |> each_key()
    |> Enum.flat_map(fn key ->
      case Map.get(index, key) do
        %{id: id} when is_binary(id) and id != "" -> [id]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp tracks_for(keys, index) do
    Enum.flat_map(each_key(keys), fn key ->
      case Map.get(index, key) do
        %{id: id} = track when is_binary(id) and id != "" -> [track]
        _ -> []
      end
    end)
  end

  defp each_key(%MapSet{} = keys), do: keys |> MapSet.to_list() |> Enum.sort()
  defp each_key(_keys), do: []

  defp plan_field(plan, field) do
    case Map.get(plan, field, MapSet.new()) do
      %MapSet{} = set -> set
      _ -> MapSet.new()
    end
  end

  defp probed?(tenant_id, name), do: store!(tenant_id, &Lithium.Store.probed?(&1, name))

  defp mark_probed(tenant_id, name) do
    store!(tenant_id, &Lithium.Store.mark_probed(&1, name))
  end

  defp read_snapshot(tenant_id, collection) do
    store!(tenant_id, &Lithium.Store.snapshot(&1, collection))
  end

  defp write_snapshot(tenant_id, collection, apple_keys, spotify_keys) do
    store!(tenant_id, fn conn ->
      Lithium.Store.put_snapshot(conn, collection, apple_keys, spotify_keys)
    end)
  end

  defp store!(tenant_id, fun) do
    {:ok, result} = Lithium.Store.with_conn(tenant_id, fun)
    result
  end
end
