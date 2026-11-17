defmodule Lithium.Mailer.Capture do
  def deliver_magic_link(email, url) do
    send(self(), {:magic_link, email, url})
    :ok
  end
end

defmodule Lithium.Web.SessionTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint Lithium.Web.Endpoint

  setup do
    Lithium.TestData.isolate!()
    previous_mailer = Application.get_env(:lithium, :mailer)
    Application.put_env(:lithium, :mailer, Lithium.Mailer.Capture)

    on_exit(fn ->
      restore(:mailer, previous_mailer)
      Application.delete_env(:lithium, :spotify_exchange)
    end)

    {:ok, conn: build_conn()}
  end

  test "asks for an email address", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Email me a sign-in link"
  end

  test "rejects an email address that is not usable", %{conn: conn} do
    conn = post_login(conn, "not-an-email")
    assert html_response(conn, 200) =~ "Enter a valid email address."
  end

  test "sends a magic link and signs in once", %{conn: conn} do
    conn = post_login(conn, "Ada@Example.com")
    assert redirected_to(conn) == "/?notice=sent"
    assert_received {:magic_link, "ada@example.com", url}

    conn = get(build_conn(), path_and_query(url))
    assert redirected_to(conn) == "/"
    conn = conn |> recycle() |> get("/")
    assert html_response(conn, 200) =~ "Signed in as ada@example.com."

    conn = get(build_conn(), path_and_query(url))
    assert redirected_to(conn) == "/?notice=invalid"
  end

  test "reports that email is not configured" do
    Application.delete_env(:lithium, :mailer)
    Application.delete_env(:lithium, :resend_api_key)

    conn = post_login(build_conn(), "ada@example.com")
    assert html_response(conn, 200) =~ "Set RESEND_API_KEY"
  end

  test "connects Spotify and stores the refresh token", %{conn: conn} do
    previous_id = Application.get_env(:lithium, :spotify_client_id)
    previous_secret = Application.get_env(:lithium, :spotify_client_secret)
    Application.put_env(:lithium, :spotify_client_id, "spotify-client")
    Application.put_env(:lithium, :spotify_client_secret, "spotify-secret")

    on_exit(fn ->
      restore(:spotify_client_id, previous_id)
      restore(:spotify_client_secret, previous_secret)
    end)

    conn = sign_in(conn, "ada@example.com")
    conn = recycle(conn) |> get("/spotify")
    location = redirected_to(conn)
    assert location =~ "https://accounts.spotify.com/authorize"
    assert location =~ "client_id=spotify-client"
    state = URI.decode_query(URI.parse(location).query)["state"]

    Application.put_env(:lithium, :spotify_exchange, fn code, redirect_uri ->
      assert code == "auth-code"
      assert String.ends_with?(redirect_uri, "/spotify/callback")

      {:ok,
       %OAuth2.AccessToken{
         access_token: "access",
         refresh_token: "refresh",
         expires_at: 1_800_000_000
       }}
    end)

    conn =
      conn
      |> recycle()
      |> get("/spotify/callback?code=auth-code&state=#{state}")

    assert redirected_to(conn) == "/?notice=spotify"
    conn = conn |> recycle() |> get("/")
    assert html_response(conn, 200) =~ "Spotify is connected."

    user = Guardian.Plug.current_resource(conn)
    assert {:ok, credentials} = Lithium.Credentials.read(user.tenant_id)
    assert credentials["spotify"]["refresh_token"] == "refresh"
    assert credentials["spotify"]["access_token"] == "access"
    assert credentials["spotify"]["expires_at"] == 1_800_000_000
  end

  defp sign_in(conn, email) do
    post_login(conn, email)
    assert_received {:magic_link, ^email, url}
    conn = get(build_conn(), path_and_query(url))
    assert redirected_to(conn) == "/"
    conn
  end

  defp post_login(conn, email) do
    conn = get(conn, "/")
    token = Plug.CSRFProtection.get_csrf_token()
    post(conn, "/login", %{"email" => email, "_csrf_token" => token})
  end

  defp path_and_query(url) do
    uri = URI.parse(url)
    uri.path <> "?" <> uri.query
  end

  defp restore(key, nil), do: Application.delete_env(:lithium, key)
  defp restore(key, value), do: Application.put_env(:lithium, key, value)
end
