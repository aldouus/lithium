defmodule Lithium.SyncTest do
  use ExUnit.Case, async: false

  alias Lithium.SyncTest.Bank

  setup do
    Lithium.TestData.isolate!()
    {:ok, agent} = start_supervised({Agent, fn -> Bank.initial() end})
    Process.put(:lithium_sync_agent, agent)
    :ok
  end

  test "missing credentials does not open a snapshot" do
    assert Lithium.sync("ada") == {:error, :missing_credentials}

    {:ok, dir} = Lithium.Tenant.directory("ada")
    refute File.dir?(dir)
  end

  test "first apple run adds and removes spotify favorites" do
    write_credentials()

    Bank.seed(%{
      apple_favorites: [
        track("a1", "USAAA1"),
        track("a2", "USAAA2"),
        track("amiss", "USMISS"),
        track("ax", nil)
      ],
      spotify_liked: [
        track("s2", "USAAA2"),
        track("s3", "USAAA3"),
        track("sx", nil)
      ],
      search: %{
        "USAAA1" => track("s1", "USAAA1"),
        "USMISS" => nil
      }
    })

    assert Lithium.sync("ada", test_opts()) ==
             {:ok, %{favorites: :ok, shows: :ok, playlists: :ok}}

    assert {:diff, apple, spotify, nil, :apple} =
             Enum.find(calls(), fn
               {:diff, apple, _spotify, nil, :apple} -> MapSet.member?(apple, "USAAA1")
               _ -> false
             end)

    assert apple == MapSet.new(["USAAA1", "USAAA2", "USMISS"])
    assert spotify == MapSet.new(["USAAA2", "USAAA3"])
    assert {:remove_tracks, ["s3"]} in calls()
    assert {:save_tracks, ["s1"]} in calls()
    assert {:search_track, "USAAA1"} in calls()
    assert {:search_track, "USMISS"} in calls()
    refute Enum.any?(calls(), &match?({:remove_favorites, _}, &1))
    refute Enum.any?(calls(), &match?({:ensure_playlist, _, _}, &1))

    assert snapshot("favorites") == %{
             apple: MapSet.new(["USAAA1", "USAAA2", "USMISS"]),
             spotify: MapSet.new(["USAAA1", "USAAA2"])
           }

    assert Enum.any?(Bank.get(:apple_favorites), &(&1.id == "ax"))
    assert Enum.any?(Bank.get(:spotify_liked), &(&1.id == "sx"))
    refute Enum.any?(Bank.get(:spotify_liked), &(&1.id == "s3"))
    assert_scheduled(3600)
  end

  test "a removal wins when apple dropped a song spotify added" do
    write_credentials()
    assert {:ok, :ok} = Lithium.put_interval("ada", 120)

    put_snapshot(
      "favorites",
      ["USCLASH", "USKEEP"],
      ["USKEEP"]
    )

    Bank.seed(%{
      apple_favorites: [track("a-keep", "USKEEP"), track("ax", nil)],
      spotify_liked: [track("s-keep", "USKEEP"), track("s-clash", "USCLASH"), track("sx", nil)]
    })

    assert Lithium.sync("ada", test_opts()) ==
             {:ok, %{favorites: :ok, shows: :ok, playlists: :ok}}

    assert {:remove_tracks, ["s-clash"]} in calls()
    refute Enum.any?(calls(), &match?({:save_tracks, _}, &1))
    refute Enum.any?(calls(), &match?({:add_favorites, _}, &1))
    refute Enum.any?(calls(), &match?({:search_track, _}, &1))

    assert snapshot("favorites") == %{
             apple: MapSet.new(["USKEEP"]),
             spotify: MapSet.new(["USKEEP"])
           }

    assert Enum.any?(Bank.get(:apple_favorites), &(&1.id == "ax"))
    assert Enum.any?(Bank.get(:spotify_liked), &(&1.id == "sx"))
    refute Enum.any?(Bank.get(:spotify_liked), &(&1.id == "s-clash"))
    assert_scheduled(120)
  end

  test "a favorites probe failure still syncs shows" do
    write_credentials()
    put_snapshot("favorites", ["sentinel"], ["sentinel"])

    Bank.seed(%{
      fail_favorites: true,
      apple_favorites: [track("a-del", "USDEL")],
      spotify_shows: [%{id: "sp-show", name: "News"}],
      apple_shows: [%{id: "111", name: "News"}],
      listen_notes: [
        %{spotify_id: "sp-show", itunes_id: "111", feed_url: "https://example.test/feed"}
      ],
      feeds: %{
        "https://example.test/feed" => %{
          podcast_guid: "pod-guid",
          episode_guids: MapSet.new(["ep-1"])
        }
      },
      episode_guids: %{"111" => MapSet.new(["ep-1"])}
    })

    diff = fn apple, spotify, _snapshot, _priority ->
      keys = MapSet.union(keys_of(apple), keys_of(spotify))

      cond do
        Enum.any?(keys, &String.starts_with?(&1, "itunes:")) ->
          {:ok, empty_plan()}

        true ->
          {:ok,
           plan(
             apple_remove: MapSet.new(["USDEL"]),
             spotify_add: MapSet.new(["USADD"])
           )}
      end
    end

    assert Lithium.sync("ada", test_opts(diff: diff)) ==
             {:ok,
              %{
                favorites: {:skipped, :favorites_probe_failed},
                shows: :ok,
                playlists: :ok
              }}

    assert {:remove_favorites, ["a-del"]} in calls()
    refute Enum.any?(calls(), &match?({:search_track, _}, &1))
    refute Enum.any?(calls(), &match?({:save_tracks, _}, &1))
    refute Enum.any?(calls(), &match?({:add_favorites, _}, &1))
    refute Enum.any?(calls(), &match?({:follow, _}, &1))

    assert snapshot("favorites") == %{
             apple: MapSet.new(["sentinel"]),
             spotify: MapSet.new(["sentinel"])
           }

    assert snapshot("shows") == %{
             apple: MapSet.new(["itunes:111"]),
             spotify: MapSet.new(["itunes:111"])
           }

    refute probed?("favorites")
    assert_scheduled(3600)
  end

  test "a podcasts probe failure still syncs favorites" do
    write_credentials()
    put_snapshot("shows", ["sentinel"], ["sentinel"])

    Bank.seed(%{
      fail_podcasts: true,
      apple_favorites: [track("a-both", "USBOTH")],
      spotify_liked: [track("s-both", "USBOTH")],
      spotify_shows: [%{id: "sp-show", name: "News"}],
      apple_shows: [%{id: "111", name: "News"}],
      listen_notes: [
        %{spotify_id: "sp-show", itunes_id: "111", feed_url: "https://example.test/feed"}
      ],
      feeds: %{
        "https://example.test/feed" => %{
          podcast_guid: "pod-guid",
          episode_guids: MapSet.new(["ep-1"])
        }
      },
      episode_guids: %{"111" => MapSet.new(["ep-1"])}
    })

    diff = fn apple, spotify, _snapshot, _priority ->
      keys = MapSet.union(keys_of(apple), keys_of(spotify))

      if Enum.any?(keys, &String.starts_with?(&1, "itunes:")) do
        {:ok,
         plan(
           apple_remove: MapSet.new(["itunes:111"]),
           apple_add: MapSet.new(["itunes:222"])
         )}
      else
        {:ok, empty_plan()}
      end
    end

    assert Lithium.sync("ada", test_opts(diff: diff)) ==
             {:ok,
              %{
                favorites: :ok,
                shows: {:skipped, :podcasts_probe_failed},
                playlists: :ok
              }}

    assert {:unfollow, "111"} in calls()
    refute Enum.any?(calls(), &match?({:follow, _}, &1))
    refute Enum.any?(calls(), &match?({:save_shows, _}, &1))
    refute Enum.any?(calls(), &match?({:remove_shows, _}, &1))

    assert snapshot("favorites") == %{
             apple: MapSet.new(["USBOTH"]),
             spotify: MapSet.new(["USBOTH"])
           }

    assert snapshot("shows") == %{
             apple: MapSet.new(["sentinel"]),
             spotify: MapSet.new(["sentinel"])
           }

    refute probed?("shows")
    assert_scheduled(3600)
  end

  test "a playlist probe failure skips the remaining playlist writes" do
    write_credentials()
    assert {:ok, :ok} = Lithium.put_playlist_names("ada", ["Night"])

    Bank.seed(%{
      fail_playlist: true,
      apple_playlists: %{
        "Night" => %{id: "apple-pl-Night", tracks: [track("ap1", "USPL1")]}
      },
      spotify_playlists: %{
        "Night" => %{id: "sp-pl-Night", tracks: [track("sp1", "USPL1")]}
      },
      search: %{"USOTHER" => track("sp-other", "USOTHER")}
    })

    diff = fn apple, spotify, _snapshot, _priority ->
      keys = MapSet.union(keys_of(apple), keys_of(spotify))

      if MapSet.member?(keys, "USPL1") do
        {:ok,
         plan(
           apple_remove: MapSet.new(["USPL1"]),
           spotify_add: MapSet.new(["USOTHER"])
         )}
      else
        {:ok, empty_plan()}
      end
    end

    assert Lithium.sync("ada", test_opts(diff: diff)) ==
             {:ok,
              %{
                favorites: :ok,
                shows: :ok,
                playlists: {:skipped, :playlist_probe_failed}
              }}

    assert {:ensure_playlist, :apple, "Night"} in calls()
    assert {:ensure_playlist, :spotify, "Night"} in calls()
    assert {:remove_playlist_tracks, :apple, "apple-pl-Night", [track("ap1", "USPL1")]} in calls()
    refute Enum.any?(calls(), &match?({:add_playlist_tracks, _, _, _}, &1))
    refute Enum.any?(calls(), &match?({:remove_playlist_tracks, :spotify, _, _}, &1))
    refute Enum.any?(calls(), &match?({:search_track, _}, &1))
    assert snapshot("playlist:Night") == nil
    refute probed?("playlists")
  end

  test "a skipped diff does not replace the snapshot" do
    write_credentials()
    put_snapshot("favorites", ["USKEEP"], ["USKEEP"])

    Bank.seed(%{
      apple_favorites: [track("a-keep", "USKEEP")],
      spotify_liked: [track("s-keep", "USKEEP")]
    })

    diff = fn _apple, _spotify, _snapshot, _priority ->
      {:skip, :priority_unreadable}
    end

    assert Lithium.sync("ada", test_opts(diff: diff)) ==
             {:ok,
              %{
                favorites: {:skipped, :priority_unreadable},
                shows: {:skipped, :priority_unreadable},
                playlists: :ok
              }}

    assert snapshot("favorites") == %{
             apple: MapSet.new(["USKEEP"]),
             spotify: MapSet.new(["USKEEP"])
           }

    refute Enum.any?(calls(), &match?({:remove_tracks, _}, &1))
    refute Enum.any?(calls(), &match?({:save_tracks, _}, &1))
    refute Enum.any?(calls(), &match?({:remove_favorites, _}, &1))
    assert_scheduled(3600)
  end

  test "writes a refreshed spotify token back to the tenant file" do
    path = write_credentials()

    refreshed = %{
      "spotify" => %{"access_token" => "refreshed-token", "refresh_token" => "refresh"},
      "apple_music" => %{"user_token" => "music-user", "storefront" => "us"},
      "apple_podcasts" => %{"user_token" => "podcast-user", "storefront" => "us"}
    }

    Bank.seed(%{refresh: refreshed})

    assert {:ok, %{favorites: :ok, shows: :ok, playlists: :ok}} =
             Lithium.sync("ada", test_opts())

    assert Jason.decode!(File.read!(path)) == refreshed
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert {:liked_songs, "refreshed-token"} in calls()
  end

  test "continues the rest of the favorite plan after the apple probe succeeds" do
    write_credentials()

    Bank.seed(%{
      apple_favorites: [track("a-old", "USOLD")],
      search: %{"USNEW" => track("s-found", "USNEW")}
    })

    diff = fn apple, spotify, _snapshot, _priority ->
      keys = MapSet.union(keys_of(apple), keys_of(spotify))

      if MapSet.member?(keys, "USOLD") do
        {:ok, plan(apple_remove: MapSet.new(["USOLD"]), spotify_add: MapSet.new(["USNEW"]))}
      else
        {:ok, empty_plan()}
      end
    end

    assert {:ok, %{favorites: :ok}} = Lithium.sync("ada", test_opts(diff: diff))
    assert {:remove_favorites, ["a-old"]} in calls()
    assert {:save_tracks, ["s-found"]} in calls()
    assert probed?("favorites")

    assert snapshot("favorites") == %{
             apple: MapSet.new(),
             spotify: MapSet.new(["USNEW"])
           }
  end

  def song_key(%{isrc: isrc}) when is_binary(isrc) and isrc != "", do: {:ok, String.upcase(isrc)}
  def song_key(_track), do: :unmatched

  def choose_song(isrc, candidates, _reference) do
    case Enum.filter(candidates, &isrc_match?(&1, isrc)) do
      [track] -> {:ok, track}
      _ -> :unmatched
    end
  end

  def confirm_show(left, right) do
    assert left.podcast_guid == nil
    assert right.podcast_guid == nil

    if match?(%MapSet{}, left.episode_guids) and left.episode_guids == right.episode_guids and
         MapSet.size(left.episode_guids) > 0 do
      {:ok, :episodes}
    else
      :unmatched
    end
  end

  def library_diff(apple, spotify, snapshot, priority) do
    Bank.record({:diff, apple, spotify, snapshot, priority})
    compute_diff(apple, spotify, snapshot, priority)
  end

  defp compute_diff(:unreadable, _spotify, _snapshot, :apple), do: {:skip, :priority_unreadable}
  defp compute_diff(_apple, :unreadable, _snapshot, :spotify), do: {:skip, :priority_unreadable}

  defp compute_diff(%MapSet{} = apple, :unreadable, _snapshot, :apple) do
    {:ok, plan(spotify_add: apple)}
  end

  defp compute_diff(:unreadable, %MapSet{} = spotify, _snapshot, :spotify) do
    {:ok, plan(apple_add: spotify)}
  end

  defp compute_diff(%MapSet{} = apple, %MapSet{} = spotify, nil, :apple) do
    {:ok,
     plan(
       spotify_add: MapSet.difference(apple, spotify),
       spotify_remove: MapSet.difference(spotify, apple)
     )}
  end

  defp compute_diff(%MapSet{} = apple, %MapSet{} = spotify, nil, :spotify) do
    {:ok,
     plan(
       apple_add: MapSet.difference(spotify, apple),
       apple_remove: MapSet.difference(apple, spotify)
     )}
  end

  defp compute_diff(
         %MapSet{} = apple,
         %MapSet{} = spotify,
         %{apple: %MapSet{} = snap_apple, spotify: %MapSet{} = snap_spotify},
         priority
       )
       when priority in [:apple, :spotify] do
    removed =
      snap_apple
      |> MapSet.difference(apple)
      |> MapSet.union(MapSet.difference(snap_spotify, spotify))

    apple_added = MapSet.difference(apple, snap_apple)
    spotify_added = MapSet.difference(spotify, snap_spotify)

    {:ok,
     plan(
       apple_add: spotify_added |> MapSet.difference(removed) |> MapSet.difference(apple),
       apple_remove: MapSet.intersection(apple, removed),
       spotify_add: apple_added |> MapSet.difference(removed) |> MapSet.difference(spotify),
       spotify_remove: MapSet.intersection(spotify, removed)
     )}
  end

  defp isrc_match?(%{isrc: candidate}, isrc) when is_binary(candidate) do
    String.upcase(candidate) == String.upcase(isrc)
  end

  defp isrc_match?(_candidate, _isrc), do: false

  defp keys_of(%MapSet{} = keys), do: keys
  defp keys_of(_keys), do: MapSet.new()

  defp test_opts(overrides \\ []) do
    Keyword.merge(
      [
        spotify: Lithium.SyncTest.Spotify,
        apple_music: Lithium.SyncTest.AppleMusic,
        apple_podcasts: Lithium.SyncTest.ApplePodcasts,
        listen_notes: Lithium.SyncTest.ListenNotes,
        feeds: Lithium.SyncTest.Feeds,
        diff: &library_diff/4,
        song_key: &song_key/1,
        choose_song: &choose_song/3,
        confirm_show: &confirm_show/2
      ],
      overrides
    )
  end

  defp credentials do
    %{
      "spotify" => %{"access_token" => "spotify-token", "refresh_token" => "refresh"},
      "apple_music" => %{"user_token" => "music-user", "storefront" => "us"},
      "apple_podcasts" => %{"user_token" => "podcast-user", "storefront" => "us"}
    }
  end

  defp write_credentials(tenant \\ "ada") do
    {:ok, dir} = Lithium.Tenant.ensure(tenant)
    path = Path.join(dir, "credentials.json")
    File.write!(path, Jason.encode!(credentials()))
    File.chmod!(path, 0o600)
    path
  end

  defp track(id, isrc, album \\ "Album", duration \\ 180_000) do
    %{id: id, isrc: isrc, album: album, duration_ms: duration}
  end

  defp calls, do: Bank.get(:calls)

  defp snapshot(collection) do
    {:ok, snap} = Lithium.Store.with_conn("ada", &Lithium.Store.snapshot(&1, collection))
    snap
  end

  defp put_snapshot(collection, apple, spotify) do
    {:ok, :ok} =
      Lithium.Store.with_conn("ada", fn conn ->
        Lithium.Store.put_snapshot(conn, collection, MapSet.new(apple), MapSet.new(spotify))
      end)
  end

  defp probed?(name) do
    {:ok, probed?} = Lithium.Store.with_conn("ada", &Lithium.Store.probed?(&1, name))
    probed?
  end

  defp assert_scheduled(interval) do
    {:ok, next} = Lithium.Store.with_conn("ada", &Lithium.Store.next_run/1)
    assert_in_delta next, System.system_time(:second) + interval, 5
  end

  defp empty_plan, do: plan()

  defp plan(fields \\ []) do
    Map.merge(
      %{
        apple_add: MapSet.new(),
        apple_remove: MapSet.new(),
        spotify_add: MapSet.new(),
        spotify_remove: MapSet.new()
      },
      Map.new(fields)
    )
  end
end

defmodule Lithium.SyncTest.Bank do
  def initial do
    %{
      refresh: nil,
      fail_favorites: false,
      fail_podcasts: false,
      fail_playlist: false,
      apple_favorites: [],
      spotify_liked: [],
      apple_shows: [],
      spotify_shows: [],
      listen_notes: [],
      feeds: %{},
      episode_guids: %{},
      search: %{},
      catalog: [],
      apple_playlists: %{},
      spotify_playlists: %{},
      calls: []
    }
  end

  def agent, do: Process.get(:lithium_sync_agent)

  def get(key), do: Map.fetch!(Agent.get(agent(), & &1), key)

  def seed(attrs), do: Agent.update(agent(), &Map.merge(&1, attrs))

  def update(fun), do: Agent.update(agent(), fun)

  def record(call), do: update(fn state -> %{state | calls: state.calls ++ [call]} end)
end

defmodule Lithium.SyncTest.Spotify do
  alias Lithium.SyncTest.Bank

  def access_token(_credentials, _opts) do
    case Bank.get(:refresh) do
      nil -> {:ok, "spotify-token"}
      credentials -> {:ok, "refreshed-token", credentials}
    end
  end

  def liked_songs(token, _opts) do
    Bank.record({:liked_songs, token})
    {:ok, Bank.get(:spotify_liked)}
  end

  def saved_shows(_token, _opts) do
    Bank.record(:saved_shows)
    {:ok, Bank.get(:spotify_shows)}
  end

  def playlists(_token, _opts), do: {:ok, []}

  def playlist_tracks(_token, playlist_id, _opts) do
    Bank.record({:playlist_tracks, :spotify, playlist_id})
    {:ok, playlist(Bank.get(:spotify_playlists), playlist_id).tracks}
  end

  def save_tracks(_token, ids, _opts) do
    Bank.update(fn state ->
      added =
        Enum.map(ids, fn id ->
          state.search
          |> Map.values()
          |> Enum.find(&match?(%{id: ^id}, &1)) ||
            %{id: id, isrc: nil, album: nil, duration_ms: nil}
        end)

      %{state | spotify_liked: state.spotify_liked ++ added}
    end)

    Bank.record({:save_tracks, ids})
    :ok
  end

  def remove_tracks(_token, ids, _opts) do
    Bank.update(fn state ->
      %{state | spotify_liked: Enum.reject(state.spotify_liked, &(&1.id in ids))}
    end)

    Bank.record({:remove_tracks, ids})
    :ok
  end

  def save_shows(_token, ids, _opts) do
    Bank.record({:save_shows, ids})
    :ok
  end

  def remove_shows(_token, ids, _opts) do
    Bank.record({:remove_shows, ids})
    :ok
  end

  def ensure_playlist(_token, name, _opts) do
    Bank.record({:ensure_playlist, :spotify, name})
    id = "sp-pl-" <> name

    Bank.update(fn state ->
      playlists = Map.put_new(state.spotify_playlists, name, %{id: id, tracks: []})
      %{state | spotify_playlists: playlists}
    end)

    {:ok, Bank.get(:spotify_playlists)[name].id}
  end

  def add_playlist_tracks(_token, playlist_id, ids, _opts) do
    Bank.record({:add_playlist_tracks, :spotify, playlist_id, ids})
    :ok
  end

  def remove_playlist_tracks(_token, playlist_id, ids, _opts) do
    Bank.record({:remove_playlist_tracks, :spotify, playlist_id, ids})
    :ok
  end

  def search_track(_token, isrc, _opts) do
    Bank.record({:search_track, isrc})
    {:ok, Map.get(Bank.get(:search), isrc)}
  end

  defp playlist(playlists, playlist_id) do
    Enum.find_value(playlists, fn {_name, playlist} ->
      if playlist.id == playlist_id, do: playlist
    end)
  end
end

defmodule Lithium.SyncTest.AppleMusic do
  alias Lithium.SyncTest.Bank

  def favorites(_token, _storefront, _opts) do
    Bank.record(:apple_favorites)
    {:ok, Bank.get(:apple_favorites)}
  end

  def add_favorites(_token, ids, _opts) do
    Bank.record({:add_favorites, ids})
    :ok
  end

  def remove_favorites(_token, ids, _opts) do
    Bank.record({:remove_favorites, ids})

    if Bank.get(:fail_favorites) do
      {:error, :favorites_probe_failed}
    else
      Bank.update(fn state ->
        %{state | apple_favorites: Enum.reject(state.apple_favorites, &(&1.id in ids))}
      end)

      :ok
    end
  end

  def songs_by_isrc(_token, _storefront, isrcs, _opts) do
    Bank.record({:songs_by_isrc, isrcs})
    {:ok, Bank.get(:catalog)}
  end

  def playlists(_token, _opts), do: {:ok, []}

  def playlist_tracks(_token, playlist_id, _opts) do
    Bank.record({:playlist_tracks, :apple, playlist_id})
    {:ok, playlist(Bank.get(:apple_playlists), playlist_id).tracks}
  end

  def ensure_playlist(_token, name, _opts) do
    Bank.record({:ensure_playlist, :apple, name})
    id = "apple-pl-" <> name

    Bank.update(fn state ->
      playlists = Map.put_new(state.apple_playlists, name, %{id: id, tracks: []})
      %{state | apple_playlists: playlists}
    end)

    {:ok, Bank.get(:apple_playlists)[name].id}
  end

  def add_playlist_tracks(_token, playlist_id, ids, _opts) do
    Bank.record({:add_playlist_tracks, :apple, playlist_id, ids})
    :ok
  end

  def remove_playlist_tracks(_token, playlist_id, tracks, _opts) do
    Bank.record({:remove_playlist_tracks, :apple, playlist_id, tracks})

    if Bank.get(:fail_playlist) do
      {:error, :playlist_probe_failed}
    else
      :ok
    end
  end

  defp playlist(playlists, playlist_id) do
    Enum.find_value(playlists, fn {_name, playlist} ->
      if playlist.id == playlist_id, do: playlist
    end)
  end
end

defmodule Lithium.SyncTest.ApplePodcasts do
  alias Lithium.SyncTest.Bank

  def followed_shows(_token, _opts) do
    Bank.record(:followed_shows)
    {:ok, Bank.get(:apple_shows)}
  end

  def follow(_token, show_id, _opts) do
    Bank.record({:follow, show_id})
    :ok
  end

  def unfollow(_token, show_id, _opts) do
    Bank.record({:unfollow, show_id})

    if Bank.get(:fail_podcasts) do
      {:error, :podcasts_probe_failed}
    else
      :ok
    end
  end

  def episode_guids(_token, _storefront, show_id, _opts) do
    Bank.record({:episode_guids, show_id})
    {:ok, Map.get(Bank.get(:episode_guids), show_id, MapSet.new())}
  end
end

defmodule Lithium.SyncTest.ListenNotes do
  alias Lithium.SyncTest.Bank

  def lookup(ids, _opts) do
    Bank.record({:lookup, ids})
    {:ok, Enum.filter(Bank.get(:listen_notes), &(&1.spotify_id in ids))}
  end
end

defmodule Lithium.SyncTest.Feeds do
  alias Lithium.SyncTest.Bank

  def show_identity(url, _opts) do
    Bank.record({:show_identity, url})

    case Map.get(Bank.get(:feeds), url) do
      nil -> {:error, :not_found}
      identity -> {:ok, identity}
    end
  end
end
