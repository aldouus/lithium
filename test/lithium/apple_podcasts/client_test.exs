defmodule Lithium.ApplePodcasts.ClientTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:lithium, :apple_podcasts_developer_token)
    Application.put_env(:lithium, :apple_podcasts_developer_token, "dev-token")

    on_exit(fn ->
      restore(:apple_podcasts_developer_token, previous)
    end)

    :ok
  end

  test "lists followed shows and follows next" do
    plug = fn conn ->
      assert conn.host == "amp-api.podcasts.apple.com"
      assert conn.method == "GET"
      assert conn.request_path == "/v1/me/library/podcasts"
      assert_player_headers(conn)

      body =
        if conn.query_params["offset"] do
          %{"data" => [%{"id" => "b", "attributes" => %{"name" => "Second"}}]}
        else
          assert conn.query_params["limit"] == "25"

          %{
            "data" => [%{"id" => "a", "attributes" => %{"name" => "First"}}],
            "next" => "/v1/me/library/podcasts?limit=25&offset=25"
          }
        end

      json(conn, body)
    end

    assert Lithium.ApplePodcasts.Client.followed_shows("user-1", plug: plug) ==
             {:ok, [%{id: "a", name: "First"}, %{id: "b", name: "Second"}]}
  end

  test "follow accepts 202" do
    plug = fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/me/library/podcasts/42"
      assert_player_headers(conn)
      Plug.Conn.send_resp(conn, 202, "")
    end

    assert Lithium.ApplePodcasts.Client.follow("user-1", "42", plug: plug) == :ok
  end

  test "unfollow returns podcasts_probe_failed when the response is not 2xx" do
    plug = fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v1/me/library/podcasts/42"
      assert_player_headers(conn)
      Plug.Conn.send_resp(conn, 403, "")
    end

    assert Lithium.ApplePodcasts.Client.unfollow("user-1", "42", plug: plug) ==
             {:error, :podcasts_probe_failed}
  end

  test "collects episode guids across pages and skips nil guids" do
    plug = fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/catalog/us/podcasts/42/episodes"
      assert_player_headers(conn)

      body =
        if conn.query_params["offset"] do
          %{
            "data" => [
              %{"attributes" => %{"guid" => "ep-2"}},
              %{"attributes" => %{"guid" => nil}},
              %{"attributes" => %{}}
            ]
          }
        else
          assert conn.query_params["limit"] == "100"

          %{
            "data" => [%{"attributes" => %{"guid" => "ep-1"}}],
            "next" => "/v1/catalog/us/podcasts/42/episodes?limit=100&offset=100"
          }
        end

      json(conn, body)
    end

    assert Lithium.ApplePodcasts.Client.episode_guids("user-1", "us", "42", plug: plug) ==
             {:ok, MapSet.new(["ep-1", "ep-2"])}
  end

  test "mints a developer token when the configured token is empty" do
    Application.put_env(:lithium, :apple_podcasts_developer_token, "")

    plug = fn _conn ->
      flunk("requested Apple Podcasts without a developer token")
    end

    assert Lithium.ApplePodcasts.Client.followed_shows("user-1", plug: plug) ==
             {:error, :missing_apple_key}
  end

  defp assert_player_headers(conn) do
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer dev-token"]
    assert Plug.Conn.get_req_header(conn, "media-user-token") == ["user-1"]
    assert Plug.Conn.get_req_header(conn, "origin") == ["https://podcasts.apple.com"]
  end

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  defp restore(key, nil), do: Application.delete_env(:lithium, key)
  defp restore(key, value), do: Application.put_env(:lithium, key, value)
end
