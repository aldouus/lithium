defmodule Lithium.AppleMusic.ClientTest do
  use ExUnit.Case, async: false

  alias Lithium.AppleMusic.Client

  setup_all do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_kind, pem} = JOSE.JWK.to_pem(jwk)
    path = Path.join(System.tmp_dir!(), "lithium-apple-#{System.unique_integer([:positive])}.pem")
    File.write!(path, pem)

    previous = %{
      team_id: Application.get_env(:lithium, :apple_team_id),
      key_id: Application.get_env(:lithium, :apple_key_id),
      key_path: Application.get_env(:lithium, :apple_private_key_path)
    }

    Application.put_env(:lithium, :apple_team_id, "TEAMID1234")
    Application.put_env(:lithium, :apple_key_id, "KEYID12345")
    Application.put_env(:lithium, :apple_private_key_path, path)

    on_exit(fn ->
      restore_env(:apple_team_id, previous.team_id)
      restore_env(:apple_key_id, previous.key_id)
      restore_env(:apple_private_key_path, previous.key_path)
      File.rm(path)
    end)

    :ok
  end

  test "maps an inFavorites song through its included catalog song" do
    plug = fn conn ->
      assert conn.host == "api.music.apple.com"
      assert conn.method == "GET"
      assert music_user_token(conn) == "user-token"
      assert bearer?(conn)

      cond do
        conn.query_params["offset"] == "100" ->
          json(conn, %{
            "data" => [
              %{
                "id" => "lib.3",
                "attributes" => %{
                  "inFavorites" => true,
                  "playParams" => %{"catalogId" => "cat.3"}
                }
              }
            ],
            "included" => [
              %{
                "id" => "cat.3",
                "type" => "songs",
                "attributes" => %{
                  "isrc" => "USRC30000003",
                  "albumName" => "Second",
                  "durationInMillis" => 180_000
                }
              }
            ]
          })

        true ->
          assert conn.request_path == "/v1/me/library/songs"
          assert conn.query_params["extend"] == "inFavorites"
          assert conn.query_params["include"] == "catalog"
          assert conn.query_params["limit"] == "100"

          json(conn, %{
            "next" => "/v1/me/library/songs?offset=100",
            "data" => [
              %{
                "id" => "lib.1",
                "type" => "library-songs",
                "attributes" => %{
                  "inFavorites" => true,
                  "playParams" => %{"catalogId" => "other"}
                },
                "relationships" => %{
                  "catalog" => %{"data" => [%{"id" => "cat.1", "type" => "songs"}]}
                }
              },
              %{
                "id" => "lib.skip",
                "attributes" => %{"inFavorites" => false}
              },
              %{
                "id" => "lib.only",
                "attributes" => %{"inFavorites" => true}
              }
            ],
            "included" => [
              %{
                "id" => "cat.1",
                "type" => "songs",
                "attributes" => %{
                  "isrc" => "USRC17607839",
                  "albumName" => "Night",
                  "durationInMillis" => 210_000
                }
              }
            ]
          })
      end
    end

    assert {:ok, tracks} = Client.favorites("user-token", "us", plug: plug)

    assert tracks == [
             %{id: "cat.1", isrc: "USRC17607839", album: "Night", duration_ms: 210_000},
             %{id: "lib.only", isrc: nil, album: nil, duration_ms: nil},
             %{id: "cat.3", isrc: "USRC30000003", album: "Second", duration_ms: 180_000}
           ]
  end

  test "adds favorites in chunks and accepts 202" do
    parent = self()

    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.host == "api.music.apple.com"
      assert conn.request_path == "/v1/me/favorites"
      send(parent, {:query, conn.query_string})
      Plug.Conn.send_resp(conn, 202, "")
    end

    ids = Enum.map(1..21, &Integer.to_string/1)
    assert :ok = Client.add_favorites("user-token", ids, plug: plug)

    assert_received {:query, first}
    assert_received {:query, second}
    refute_received {:query, _}

    assert first == "ids[songs]=" <> Enum.join(Enum.map(1..20, &Integer.to_string/1), ",")
    assert second == "ids[songs]=21"
  end

  test "rejects an add favorites response that is not 202" do
    plug = fn conn ->
      Plug.Conn.send_resp(conn, 200, "")
    end

    assert Client.add_favorites("user-token", ["1"], plug: plug) == {:error, {:http, 200}}
  end

  test "deletes favorites with the ids[songs] query" do
    for status <- [200, 202, 204] do
      plug = fn conn ->
        assert conn.method == "DELETE"
        assert conn.host == "api.music.apple.com"
        assert conn.request_path == "/v1/me/favorites"
        assert conn.query_string == "ids[songs]=111,222"
        assert music_user_token(conn) == "user-token"
        Plug.Conn.send_resp(conn, status, "")
      end

      assert :ok = Client.remove_favorites("user-token", ["111", "222"], plug: plug)
    end
  end

  test "reports a failed favorites delete" do
    plug = fn conn ->
      assert conn.request_path == "/v1/me/favorites"
      assert conn.query_string == "ids[songs]=1"
      Plug.Conn.send_resp(conn, 403, "")
    end

    assert Client.remove_favorites("user-token", ["1"], plug: plug) ==
             {:error, :favorites_probe_failed}
  end

  test "looks up catalog songs by ISRC" do
    parent = self()

    plug = fn conn ->
      assert conn.host == "api.music.apple.com"
      assert conn.request_path == "/v1/catalog/us/songs"
      send(parent, {:query, conn.query_string})

      isrcs = conn.query_string |> String.replace_prefix("filter[isrc]=", "") |> String.split(",")

      json(conn, %{
        "data" =>
          Enum.map(isrcs, fn isrc ->
            %{
              "id" => "id-" <> isrc,
              "attributes" => %{
                "isrc" => isrc,
                "albumName" => "Album " <> isrc,
                "durationInMillis" => 1000
              }
            }
          end)
      })
    end

    isrcs = Enum.map(1..26, &("ISRC" <> Integer.to_string(&1)))
    assert {:ok, tracks} = Client.songs_by_isrc("user-token", "us", isrcs, plug: plug)

    assert_received {:query, first}
    assert_received {:query, second}
    refute_received {:query, _}

    assert first == "filter[isrc]=" <> Enum.join(Enum.take(isrcs, 25), ",")
    assert second == "filter[isrc]=ISRC26"
    assert length(tracks) == 26
    assert hd(tracks) == %{id: "id-ISRC1", isrc: "ISRC1", album: "Album ISRC1", duration_ms: 1000}
  end

  test "lists library playlists across pages" do
    plug = fn conn ->
      assert conn.host == "api.music.apple.com"
      assert conn.request_path == "/v1/me/library/playlists"
      assert conn.query_params["limit"] == "100" or conn.query_params["offset"] == "100"

      if conn.query_params["offset"] == "100" do
        json(conn, %{
          "data" => [
            %{"id" => "p.2", "attributes" => %{"name" => "Day", "canEdit" => false}}
          ]
        })
      else
        assert conn.query_params["limit"] == "100"

        json(conn, %{
          "next" => "/v1/me/library/playlists?offset=100",
          "data" => [
            %{"id" => "p.1", "attributes" => %{"name" => "Night", "canEdit" => true}}
          ]
        })
      end
    end

    assert {:ok, playlists} = Client.playlists("user-token", plug: plug)

    assert playlists == [
             %{id: "p.1", name: "Night", can_edit: true},
             %{id: "p.2", name: "Day", can_edit: false}
           ]
  end

  test "maps playlist tracks through the included catalog song" do
    plug = fn conn ->
      assert conn.request_path == "/v1/me/library/playlists/pl.1/tracks"
      assert conn.query_params["include"] == "catalog"
      assert conn.query_params["limit"] == "100"

      json(conn, %{
        "data" => [
          %{
            "id" => "lib.9",
            "relationships" => %{
              "catalog" => %{"data" => [%{"id" => "cat.9", "type" => "songs"}]}
            }
          }
        ],
        "included" => [
          %{
            "id" => "cat.9",
            "type" => "songs",
            "attributes" => %{
              "isrc" => "USRC9",
              "albumName" => "Playlist Album",
              "durationInMillis" => 90_000
            }
          }
        ]
      })
    end

    assert {:ok, [track]} = Client.playlist_tracks("user-token", "pl.1", plug: plug)

    assert track == %{
             id: "cat.9",
             isrc: "USRC9",
             album: "Playlist Album",
             duration_ms: 90_000
           }
  end

  test "returns an editable playlist id" do
    plug = fn conn ->
      assert conn.method == "GET"

      json(conn, %{
        "data" => [
          %{"id" => "p.locked", "attributes" => %{"name" => "Night", "canEdit" => false}},
          %{"id" => "p.ok", "attributes" => %{"name" => "Night", "canEdit" => true}}
        ]
      })
    end

    assert {:ok, "p.ok"} = Client.ensure_playlist("user-token", "Night", plug: plug)
  end

  test "creates a library playlist when none with that name is editable" do
    plug = fn conn ->
      case conn.method do
        "GET" ->
          json(conn, %{
            "data" => [
              %{"id" => "p.other", "attributes" => %{"name" => "night", "canEdit" => true}},
              %{"id" => "p.locked", "attributes" => %{"name" => "Night", "canEdit" => false}}
            ]
          })

        "POST" ->
          assert conn.host == "api.music.apple.com"
          assert conn.request_path == "/v1/me/library/playlists"
          assert conn.body_params == %{"attributes" => %{"name" => "Night"}}
          json(conn, 201, %{"data" => [%{"id" => "p.new"}]})
      end
    end

    assert {:ok, "p.new"} = Client.ensure_playlist("user-token", "Night", plug: plug)
  end

  test "appends tracks to a library playlist" do
    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.host == "api.music.apple.com"
      assert conn.request_path == "/v1/me/library/playlists/pl.1/tracks"

      assert conn.body_params == %{
               "data" => [
                 %{"id" => "a", "type" => "songs"},
                 %{"id" => "b", "type" => "songs"}
               ]
             }

      json(conn, 201, %{})
    end

    assert :ok = Client.add_playlist_tracks("user-token", "pl.1", ["a", "b"], plug: plug)
  end

  test "deletes playlist tracks on the web player host" do
    plug = fn conn ->
      assert conn.method == "DELETE"
      assert conn.scheme == :https
      assert conn.host == "amp-api.music.apple.com"
      assert conn.request_path == "/v1/me/library/playlists/pl.1/tracks"
      assert header(conn, "media-user-token") == "user-token"
      assert header(conn, "origin") == "https://music.apple.com"
      assert bearer?(conn)

      assert conn.body_params == %{
               "data" => [
                 %{"id" => "cat.9", "type" => "songs"},
                 %{"id" => "cat.10", "type" => "songs"}
               ]
             }

      Plug.Conn.send_resp(conn, 200, "")
    end

    tracks = [
      %{id: "cat.9", isrc: "USRC9", album: "A", duration_ms: 1},
      %{id: "cat.10", isrc: nil, album: nil, duration_ms: nil}
    ]

    assert :ok = Client.remove_playlist_tracks("user-token", "pl.1", tracks, plug: plug)
  end

  test "reports a failed playlist track delete" do
    plug = fn conn ->
      assert conn.host == "amp-api.music.apple.com"
      Plug.Conn.send_resp(conn, 403, "")
    end

    tracks = [%{id: "cat.9", isrc: nil, album: nil, duration_ms: nil}]

    assert Client.remove_playlist_tracks("user-token", "pl.1", tracks, plug: plug) ==
             {:error, :playlist_probe_failed}
  end

  test "returns the developer token error without calling HTTP" do
    Application.delete_env(:lithium, :apple_team_id)

    on_exit(fn ->
      Application.put_env(:lithium, :apple_team_id, "TEAMID1234")
    end)

    plug = fn _conn ->
      flunk("HTTP was called")
    end

    assert Client.favorites("user-token", "us", plug: plug) == {:error, :missing_apple_key}

    assert Client.remove_playlist_tracks("user-token", "pl.1", [], plug: plug) ==
             {:error, :missing_apple_key}
  end

  defp json(conn, data), do: json(conn, 200, data)

  defp json(conn, status, data) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(data)
  end

  defp header(conn, name) do
    conn |> Plug.Conn.get_req_header(name) |> List.first()
  end

  defp music_user_token(conn), do: header(conn, "music-user-token")

  defp bearer?(conn) do
    case header(conn, "authorization") do
      "Bearer " <> jwt -> length(String.split(jwt, ".")) == 3
      _ -> false
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:lithium, key)
  defp restore_env(key, value), do: Application.put_env(:lithium, key, value)
end
