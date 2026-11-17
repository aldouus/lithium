defmodule Lithium.Feeds.ClientTest do
  use ExUnit.Case, async: true

  test "reads the channel podcast guid and item guids" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
      <channel>
        <title>Example</title>
        <podcast:guid>917393e3-1b1e-5cef-ace4-edaa54e1f810</podcast:guid>
        <item>
          <title>One</title>
          <guid isPermaLink="false">episode-1</guid>
        </item>
        <item>
          <guid>episode-2</guid>
        </item>
      </channel>
    </rss>
    """

    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.host == "feeds.example"
      assert conn.request_path == "/feed.xml"

      conn
      |> Plug.Conn.put_resp_content_type("application/rss+xml")
      |> Plug.Conn.send_resp(200, xml)
    end

    assert Lithium.Feeds.Client.show_identity("https://feeds.example/feed.xml", plug: plug) ==
             {:ok,
              %{
                podcast_guid: "917393e3-1b1e-5cef-ace4-edaa54e1f810",
                episode_guids: MapSet.new(["episode-1", "episode-2"])
              }}
  end

  test "does not treat an item guid as the channel podcast guid" do
    xml = """
    <rss>
      <channel>
        <item><guid>only-episode</guid></item>
      </channel>
    </rss>
    """

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/rss+xml")
      |> Plug.Conn.send_resp(200, xml)
    end

    assert Lithium.Feeds.Client.show_identity("https://feeds.example/feed.xml", plug: plug) ==
             {:ok, %{podcast_guid: nil, episode_guids: MapSet.new(["only-episode"])}}
  end

  test "returns the fetch error when the feed cannot be loaded" do
    plug = fn conn ->
      Plug.Conn.send_resp(conn, 500, "nope")
    end

    assert Lithium.Feeds.Client.show_identity("https://feeds.example/feed.xml", plug: plug) ==
             {:error, {:unexpected_status, 500}}
  end
end
