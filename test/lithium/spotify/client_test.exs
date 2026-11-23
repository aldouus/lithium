defmodule Lithium.Spotify.ClientTest do
  use ExUnit.Case, async: false

  alias Lithium.Spotify.Client

  setup do
    previous_id = Application.get_env(:lithium, :spotify_client_id)
    previous_secret = Application.get_env(:lithium, :spotify_client_secret)
    Application.put_env(:lithium, :spotify_client_id, "client-id")
    Application.put_env(:lithium, :spotify_client_secret, "client-secret")

    on_exit(fn ->
      restore_env(:spotify_client_id, previous_id)
      restore_env(:spotify_client_secret, previous_secret)
    end)

    :ok
  end

  test "pages liked songs until next is exhausted" do
    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/me/tracks"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret"]

      calls = Process.get(:liked_pages, 0) + 1
      Process.put(:liked_pages, calls)
      assert calls <= 2

      case conn.query_params["offset"] do
        nil ->
          assert conn.query_params["limit"] == "50"

          respond(conn, %{
            "items" => [%{"track" => track("a", "USAAA1", "Album A", 1000)}],
            "next" => "https://api.spotify.com/v1/me/tracks?offset=50&limit=50"
          })

        "50" ->
          respond(conn, %{
            "items" => [%{"track" => track("b", "USBBB2", "Album B", 2000)}],
            "next" => nil
          })
      end
    end

    assert {:ok,
            [
              %{id: "a", isrc: "USAAA1", album: "Album A", duration_ms: 1000},
              %{id: "b", isrc: "USBBB2", album: "Album B", duration_ms: 2000}
            ]} = Client.liked_songs("secret", plug: plug)
  end

  test "maps a 401 from a library read to spotify_auth" do
    plug = fn conn ->
      respond(conn, 401, %{"error" => %{"status" => 401, "message" => "expired"}})
    end

    assert {:error, :spotify_auth} = Client.liked_songs("secret", plug: plug)
  end

  test "maps saved shows and show episodes" do
    plug = fn conn ->
      case conn.request_path do
        "/v1/me/shows" ->
          assert conn.method == "GET"
          assert conn.query_params["limit"] == "50"

          respond(conn, %{
            "items" => [
              %{"show" => %{"id" => "show-1", "name" => "Night"}},
              %{"show" => nil}
            ],
            "next" => nil
          })

        "/v1/shows/show-1/episodes" ->
          respond(conn, %{
            "items" => [%{"name" => "Pilot", "release_date" => "2024-05-01"}],
            "next" => nil
          })
      end
    end

    assert {:ok, [%{id: "show-1", name: "Night"}]} = Client.saved_shows("secret", plug: plug)

    assert {:ok, [%{name: "Pilot", release_date: "2024-05-01"}]} =
             Client.show_episodes("secret", "show-1", plug: plug)
  end

  test "lists playlists" do
    plug = fn conn ->
      assert conn.request_path == "/v1/me/playlists"

      respond(conn, %{
        "items" => [%{"id" => "pl-1", "name" => "Night"}],
        "next" => nil
      })
    end

    assert {:ok, [%{id: "pl-1", name: "Night"}]} = Client.playlists("secret", plug: plug)
  end

  test "keeps playlist tracks that have an ISRC and accepts item or track" do
    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/playlists/pl-1/items"

      respond(conn, %{
        "items" => [
          %{"item" => nil},
          %{
            "is_local" => true,
            "item" => track("local", "LOCAL1", "Local", 1)
          },
          %{"item" => track("missing", nil, "No Code", 2)},
          %{"track" => track("legacy", "LEGACY1", "Old", 3)},
          %{"item" => track("current", "NEWISRC", "New", 4)}
        ],
        "next" => nil
      })
    end

    assert {:ok,
            [
              %{id: "legacy", isrc: "LEGACY1", album: "Old", duration_ms: 3},
              %{id: "current", isrc: "NEWISRC", album: "New", duration_ms: 4}
            ]} = Client.playlist_tracks("secret", "pl-1", plug: plug)
  end

  test "saves tracks as spotify track URIs and skips an empty list" do
    parent = self()

    plug = fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/v1/me/library"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret"]
      assert {_adapter, %{raw_body: ""}} = conn.adapter
      send(parent, {:uris, conn.query_params["uris"]})
      respond(conn, %{})
    end

    assert :ok = Client.save_tracks("secret", [], plug: plug)
    refute_received {:uris, _}

    assert :ok = Client.save_tracks("secret", ["abc", "def"], plug: plug)
    assert_received {:uris, "spotify:track:abc,spotify:track:def"}
  end

  test "chunks library saves by 40" do
    parent = self()

    plug = fn conn ->
      send(parent, {:uris, conn.query_params["uris"]})
      respond(conn, %{})
    end

    ids = Enum.map(1..41, &"t#{&1}")
    assert :ok = Client.save_tracks("secret", ids, plug: plug)

    assert_received {:uris, first}
    assert_received {:uris, second}
    refute_received {:uris, _}
    assert length(String.split(first, ",")) == 40
    assert second == "spotify:track:t41"
  end

  test "removes tracks and shows with the same library query" do
    parent = self()

    plug = fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v1/me/library"
      assert {_adapter, %{raw_body: ""}} = conn.adapter
      send(parent, {:uris, conn.query_params["uris"]})
      respond(conn, %{})
    end

    assert :ok = Client.remove_tracks("secret", ["abc"], plug: plug)
    assert_received {:uris, "spotify:track:abc"}

    assert :ok = Client.remove_shows("secret", ["show-1"], plug: plug)
    assert_received {:uris, "spotify:show:show-1"}

    assert :ok = Client.save_shows("secret", [], plug: fn _conn -> flunk("requested") end)
  end

  test "saves shows as spotify show URIs" do
    plug = fn conn ->
      assert conn.method == "PUT"
      assert conn.query_params["uris"] == "spotify:show:show-1,spotify:show:show-2"
      respond(conn, %{})
    end

    assert :ok = Client.save_shows("secret", ["show-1", "show-2"], plug: plug)
  end

  test "returns the track whose ISRC matches and ignores a different hit" do
    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/search"
      assert conn.query_params["q"] == "isrc:USRC17607839"
      assert conn.query_params["type"] == "track"
      assert conn.query_params["limit"] == "5"

      calls = Process.get(:search_calls, 0)
      Process.put(:search_calls, calls + 1)
      assert calls == 0

      respond(conn, %{
        "tracks" => %{
          "items" => [
            track("other", "USOTHER00001", "Wrong", 10),
            track("match", "usrc17607839", "Right", 20)
          ]
        }
      })
    end

    assert {:ok, %{id: "match", isrc: "usrc17607839", album: "Right", duration_ms: 20}} =
             Client.search_track("secret", "USRC17607839", plug: plug)
  end

  test "returns a long rate limit without sleeping through it" do
    plug = fn conn ->
      calls = Process.get(:long_rate_calls, 0)
      Process.put(:long_rate_calls, calls + 1)
      assert calls == 0

      conn
      |> Plug.Conn.put_resp_header("retry-after", "84320")
      |> respond(429, %{"error" => %{"status" => 429, "message" => "API rate limit exceeded"}})
    end

    assert {:error, {:spotify_rate_limit, 84_320}} =
             Client.search_track("secret", "USRC17607839", plug: plug)
  end

  test "retries a rate limited search and keeps the matching track" do
    plug = fn conn ->
      calls = Process.get(:rate_calls, 0)
      Process.put(:rate_calls, calls + 1)

      if calls == 0 do
        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> respond(429, %{"error" => %{"status" => 429, "message" => "API rate limit exceeded"}})
      else
        respond(conn, %{
          "tracks" => %{"items" => [track("match", "USRC17607839", "Right", 20)]}
        })
      end
    end

    assert {:ok, %{id: "match", isrc: "USRC17607839", album: "Right", duration_ms: 20}} =
             Client.search_track("secret", "USRC17607839", plug: plug)
  end

  test "returns nil when every search hit has a different ISRC" do
    plug = fn conn ->
      assert conn.query_params["q"] == "isrc:USRC17607839"

      respond(conn, %{
        "tracks" => %{
          "items" => [track("other", "USOTHER00001", "USRC17607839", 10)]
        }
      })
    end

    assert {:ok, nil} = Client.search_track("secret", "USRC17607839", plug: plug)
  end

  test "returns the id of a playlist with the exact name" do
    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/me/playlists"

      respond(conn, %{
        "items" => [
          %{"id" => "partial", "name" => "Night Drive"},
          %{"id" => "exact", "name" => "Night"}
        ],
        "next" => nil
      })
    end

    assert {:ok, "exact"} = Client.ensure_playlist("secret", "Night", plug: plug)
  end

  test "creates a private playlist when the name is missing" do
    plug = fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/me/playlists"} ->
          respond(conn, %{"items" => [%{"id" => "other", "name" => "Other"}], "next" => nil})

        {"POST", "/v1/me/playlists"} ->
          assert conn.body_params == %{"name" => "Night", "public" => false}
          respond(conn, %{"id" => "created"})
      end
    end

    assert {:ok, "created"} = Client.ensure_playlist("secret", "Night", plug: plug)
  end

  test "adds playlist tracks as uris in chunks of 100" do
    parent = self()

    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/playlists/pl-1/items"
      send(parent, conn.body_params["uris"])
      respond(conn, %{"snapshot_id" => "snap"})
    end

    ids = Enum.map(1..101, &"id#{&1}")
    assert :ok = Client.add_playlist_tracks("secret", "pl-1", ids, plug: plug)

    assert_received first when length(first) == 100
    assert_received ["spotify:track:id101"]
    assert hd(first) == "spotify:track:id1"
  end

  test "removes playlist tracks with the items body" do
    plug = fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v1/playlists/pl-1/items"

      assert conn.body_params == %{
               "items" => [
                 %{"uri" => "spotify:track:abc"},
                 %{"uri" => "spotify:track:def"}
               ]
             }

      respond(conn, %{"snapshot_id" => "snap"})
    end

    assert :ok = Client.remove_playlist_tracks("secret", "pl-1", ["abc", "def"], plug: plug)

    assert :ok =
             Client.remove_playlist_tracks("secret", "pl-1", [],
               plug: fn _ -> flunk("requested") end
             )
  end

  test "returns the status and body when playlist removal fails" do
    plug = fn conn ->
      respond(conn, 403, %{"error" => %{"status" => 403, "message" => "forbidden"}})
    end

    assert {:error, {:spotify, 403, %{"error" => %{"status" => 403, "message" => "forbidden"}}}} =
             Client.remove_playlist_tracks("secret", "pl-1", ["abc"], plug: plug)
  end

  test "returns a stored access token that has not expired" do
    later = System.os_time(:second) + 3600

    credentials = %{
      "spotify" => %{
        "access_token" => "live",
        "refresh_token" => "refresh-me",
        "expires_at" => later
      }
    }

    plug = fn _conn -> flunk("refreshed a live token") end
    assert {:ok, "live"} = Client.access_token(credentials, plug: plug)
  end

  test "refreshes an expired access token with the stored refresh token" do
    before = System.os_time(:second)

    credentials = %{
      "apple" => %{"user_token" => "apple"},
      "spotify" => %{
        "access_token" => "stale",
        "refresh_token" => "refresh-me",
        "expires_at" => before,
        "scope" => "user-library-read"
      }
    }

    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/token"
      assert conn.body_params["grant_type"] == "refresh_token"
      assert conn.body_params["refresh_token"] == "refresh-me"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("client-id:client-secret")
             ]

      respond(conn, %{
        "access_token" => "fresh",
        "expires_in" => 3600,
        "refresh_token" => "refresh-next"
      })
    end

    assert {:ok, "fresh", updated} = Client.access_token(credentials, plug: plug)
    after_call = System.os_time(:second)

    assert updated["apple"] == %{"user_token" => "apple"}
    assert updated["spotify"]["access_token"] == "fresh"
    assert updated["spotify"]["refresh_token"] == "refresh-next"
    assert updated["spotify"]["scope"] == "user-library-read"
    assert updated["spotify"]["expires_at"] in (before + 3600)..(after_call + 3600)
  end

  test "refreshes when the access token is missing and keeps the old refresh token" do
    credentials = %{
      "spotify" => %{
        "refresh_token" => "refresh-me",
        "expires_at" => System.os_time(:second) + 3600
      }
    }

    plug = fn conn ->
      assert conn.body_params["refresh_token"] == "refresh-me"
      respond(conn, %{"access_token" => "fresh", "expires_in" => 1200})
    end

    assert {:ok, "fresh", updated} = Client.access_token(credentials, plug: plug)
    assert updated["spotify"]["refresh_token"] == "refresh-me"
    assert is_integer(updated["spotify"]["expires_at"])
  end

  test "maps invalid_grant from the token endpoint to spotify_auth" do
    credentials = %{
      "spotify" => %{
        "access_token" => "stale",
        "refresh_token" => "refresh-me",
        "expires_at" => 0
      }
    }

    plug = fn conn ->
      respond(conn, 400, %{"error" => "invalid_grant", "error_description" => "revoked"})
    end

    assert {:error, :spotify_auth} = Client.access_token(credentials, plug: plug)
  end

  defp track(id, nil, album, duration) do
    %{
      "id" => id,
      "external_ids" => %{},
      "album" => %{"name" => album},
      "duration_ms" => duration
    }
  end

  defp track(id, isrc, album, duration) do
    %{
      "id" => id,
      "external_ids" => %{"isrc" => isrc},
      "album" => %{"name" => album},
      "duration_ms" => duration,
      "is_local" => false
    }
  end

  defp respond(conn, body) when is_map(body), do: respond(conn, 200, body)

  defp respond(conn, status, body) when is_integer(status) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(body)
  end

  defp restore_env(key, nil), do: Application.delete_env(:lithium, key)
  defp restore_env(key, value), do: Application.put_env(:lithium, key, value)
end
