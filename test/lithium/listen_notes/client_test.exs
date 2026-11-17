defmodule Lithium.ListenNotes.ClientTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:lithium, :listen_notes_api_key)
    Application.delete_env(:lithium, :listen_notes_api_key)

    on_exit(fn ->
      if previous do
        Application.put_env(:lithium, :listen_notes_api_key, previous)
      else
        Application.delete_env(:lithium, :listen_notes_api_key)
      end
    end)

    :ok
  end

  test "maps rss and itunes id for each matched spotify show" do
    Application.put_env(:lithium, :listen_notes_api_key, "ln-key")

    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.host == "listen-api.listennotes.com"
      assert conn.request_path == "/api/v2/podcasts"
      assert Plug.Conn.get_req_header(conn, "x-listenapi-key") == ["ln-key"]
      assert conn.body_params["spotify_ids"] == "show1,show2,missing"

      json(conn, %{
        "podcasts" => [
          %{
            "itunes_id" => 12_345,
            "rss" => "https://example.com/feed.xml",
            "extra" => %{"spotify_url" => "https://open.spotify.com/show/show1"}
          },
          %{
            "spotify_id" => "show2",
            "itunes_id" => "678",
            "rss" => nil
          }
        ]
      })
    end

    assert Lithium.ListenNotes.Client.lookup(["show1", "show2", "missing"], plug: plug) ==
             {:ok,
              [
                %{
                  spotify_id: "show1",
                  itunes_id: "12345",
                  feed_url: "https://example.com/feed.xml"
                },
                %{spotify_id: "show2", itunes_id: "678", feed_url: nil}
              ]}
  end

  test "returns missing_listen_notes_key when the api key is not configured" do
    plug = fn _conn ->
      flunk("requested Listen Notes without an api key")
    end

    assert Lithium.ListenNotes.Client.lookup(["show1"], plug: plug) ==
             {:error, :missing_listen_notes_key}
  end

  test "requests spotify ids in chunks of 10" do
    Application.put_env(:lithium, :listen_notes_api_key, "ln-key")
    {:ok, agent} = Agent.start_link(fn -> [] end)
    ids = Enum.map(1..11, &"show#{&1}")

    plug = fn conn ->
      chunk = String.split(conn.body_params["spotify_ids"], ",", trim: true)
      Agent.update(agent, &[chunk | &1])

      podcasts =
        Enum.map(chunk, fn id ->
          %{
            "itunes_id" => 1,
            "rss" => "https://feeds.example/#{id}.xml",
            "extra" => %{"spotify_url" => "https://open.spotify.com/show/#{id}"}
          }
        end)

      json(conn, %{"podcasts" => podcasts})
    end

    assert {:ok, rows} = Lithium.ListenNotes.Client.lookup(ids, plug: plug)
    assert Enum.map(rows, & &1.spotify_id) == ids
    assert Agent.get(agent, &Enum.reverse/1) == [Enum.take(ids, 10), ["show11"]]
  end

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end
end
