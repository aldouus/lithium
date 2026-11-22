defmodule Lithium.Web.AppleConnectTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint Lithium.Web.Endpoint

  setup do
    Lithium.TestData.isolate!()
    previous_mailer = Application.get_env(:lithium, :mailer)
    previous_team = Application.get_env(:lithium, :apple_team_id)
    previous_key = Application.get_env(:lithium, :apple_key_id)
    previous_pem = Application.get_env(:lithium, :apple_private_key)
    Application.put_env(:lithium, :mailer, Lithium.Web.AppleConnectTest.Mailer)

    on_exit(fn ->
      restore(:mailer, previous_mailer)
      restore(:apple_team_id, previous_team)
      restore(:apple_key_id, previous_key)
      restore(:apple_private_key, previous_pem)
    end)

    {:ok, conn: build_conn()}
  end

  test "asks a signed-out visitor to sign in", %{conn: conn} do
    conn = get(conn, "/apple/music")
    assert redirected_to(conn) == "/"
  end

  test "connects Apple Music from the MusicKit button", %{conn: conn} do
    jwk = install_key!()
    conn = sign_in(conn, "ada@example.com")

    conn = recycle(conn) |> get("/apple/music")
    assert html_response(conn, 200) =~ "Connect Apple Music"
    assert html_response(conn, 200) =~ "musickit.js"
    refute html_response(conn, 200) =~ "<style"

    conn = recycle(conn) |> get("/apple/music/token")
    assert response(conn, 200) =~ "."
    token = response(conn, 200)
    {true, jwt, _jws} = JOSE.JWT.verify_strict(jwk, ["ES256"], token)
    assert jwt.fields["origin"] == ["http://www.example.com"]

    conn =
      recycle(conn)
      |> post("/apple/music", %{
        "_csrf_token" => Plug.CSRFProtection.get_csrf_token(),
        "music_user_token" => String.duplicate("m", 24),
        "storefront" => "GB"
      })

    assert redirected_to(conn) == "/?notice=apple_music"
    conn = recycle(conn) |> get("/")
    assert html_response(conn, 200) =~ "Apple Music is connected."

    user = Guardian.Plug.current_resource(conn)
    assert {:ok, credentials} = Lithium.Credentials.read(user.tenant_id)
    assert credentials["apple_music"]["music_user_token"] == String.duplicate("m", 24)
    assert credentials["apple_music"]["storefront"] == "gb"
  end

  test "connects Apple Podcasts from the bookmark token", %{conn: conn} do
    conn = sign_in(conn, "ada@example.com")
    conn = recycle(conn) |> get("/apple/podcasts")
    html = html_response(conn, 200)
    assert html =~ "https://podcasts.apple.com"
    assert html =~ "media-user-token"
    assert html =~ "Connect Lithium"
    refute html =~ "<style"

    conn =
      recycle(conn)
      |> post("/apple/podcasts", %{
        "_csrf_token" => Plug.CSRFProtection.get_csrf_token(),
        "media_user_token" => String.duplicate("p", 24)
      })

    assert redirected_to(conn) == "/?notice=apple_podcasts"
    conn = recycle(conn) |> get("/")
    assert html_response(conn, 200) =~ "Apple Podcasts is connected."

    user = Guardian.Plug.current_resource(conn)
    assert {:ok, credentials} = Lithium.Credentials.read(user.tenant_id)
    assert credentials["apple_podcasts"]["media_user_token"] == String.duplicate("p", 24)
    assert credentials["apple_podcasts"]["storefront"] == "us"
  end

  defp install_key! do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_kind, pem} = JOSE.JWK.to_pem(jwk)
    Application.put_env(:lithium, :apple_team_id, "TEAMID1234")
    Application.put_env(:lithium, :apple_key_id, "KEYID12345")
    Application.put_env(:lithium, :apple_private_key, pem)
    jwk
  end

  defp sign_in(conn, email) do
    conn = get(conn, "/")
    token = Plug.CSRFProtection.get_csrf_token()
    post(conn, "/login", %{"email" => email, "_csrf_token" => token})
    assert_received {:magic_link, ^email, url}
    uri = URI.parse(url)
    conn = get(build_conn(), uri.path <> "?" <> uri.query)
    assert redirected_to(conn) == "/"
    conn
  end

  defp restore(key, nil), do: Application.delete_env(:lithium, key)
  defp restore(key, value), do: Application.put_env(:lithium, key, value)
end

defmodule Lithium.Web.AppleConnectTest.Mailer do
  def deliver_magic_link(email, url) do
    send(self(), {:magic_link, email, url})
    :ok
  end
end
