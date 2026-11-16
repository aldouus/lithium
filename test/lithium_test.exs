defmodule LithiumTest do
  use ExUnit.Case, async: false

  setup do
    Lithium.TestData.isolate!()
    :ok
  end

  test "rejects a tenant id that leaves the tenants directory" do
    assert Lithium.Tenant.directory("../etc") == {:error, :invalid_tenant}
    assert Lithium.Tenant.directory("a/b") == {:error, :invalid_tenant}
  end

  test "opens the tenant database in WAL mode" do
    assert {:ok, "wal"} =
             Lithium.Store.with_conn("ada", fn conn ->
               Lithium.Store.journal_mode(conn)
             end)
  end

  test "stores priority, playlists, and snapshots per tenant" do
    assert {:ok, :ok} = Lithium.put_priority("ada", :spotify)
    assert {:ok, :ok} = Lithium.put_playlist_names("ada", ["Night", "Night"])
    assert {:ok, :ok} = Lithium.put_interval("ada", 120)

    assert {:ok, snapshot} =
             Lithium.Store.with_conn("ada", fn conn ->
               assert Lithium.Store.priority(conn) == :spotify
               assert Lithium.Store.interval(conn) == 120
               assert Lithium.Store.playlist_names(conn) == ["Night"]
               assert Lithium.Store.snapshot(conn, "favorites") == nil

               :ok =
                 Lithium.Store.put_snapshot(
                   conn,
                   "favorites",
                   MapSet.new(["USRC1"]),
                   MapSet.new()
                 )

               Lithium.Store.snapshot(conn, "favorites")
             end)

    assert snapshot.apple == MapSet.new(["USRC1"])
    assert snapshot.spotify == MapSet.new()
  end

  test "reads a credential file and reports when it is missing" do
    assert Lithium.Credentials.read("ada") == {:error, :missing_credentials}

    {:ok, dir} = Lithium.Tenant.ensure("ada")
    path = Path.join(dir, "credentials.json")

    File.write!(path, Jason.encode!(%{"spotify" => %{"access_token" => "token"}}))
    File.chmod!(path, 0o600)

    assert {:ok, %{"spotify" => %{"access_token" => "token"}}} =
             Lithium.Credentials.read("ada")

    assert {:ok, "token"} =
             Lithium.Credentials.token(
               %{"spotify" => %{"access_token" => "token"}},
               "spotify",
               "access_token"
             )
  end

  test "mints an Apple developer token from a P-256 key" do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_kind, pem} = JOSE.JWK.to_pem(jwk)

    assert {:ok, token} =
             Lithium.AppleToken.developer_token(
               team_id: "TEAMID1234",
               key_id: "KEYID12345",
               pem: pem
             )

    {true, jwt, _jws} = JOSE.JWT.verify_strict(jwk, ["ES256"], token)
    assert jwt.fields["iss"] == "TEAMID1234"
    assert jwt.fields["exp"] - jwt.fields["iat"] <= 15_777_000
  end

  test "refuses an Apple token without a key" do
    assert Lithium.AppleToken.developer_token(team_id: nil, key_id: nil, pem: nil) ==
             {:error, :missing_apple_key}
  end
end
