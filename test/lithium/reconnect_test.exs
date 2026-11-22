defmodule Lithium.ReconnectTest.Mailer do
  def deliver_reconnect(email, service, url) do
    send(self(), {:reconnect, email, service, url})
    :ok
  end
end

defmodule Lithium.ReconnectTest.Spotify do
  def access_token(_credentials, _http), do: {:error, :spotify_auth}
end

defmodule Lithium.ReconnectTest do
  use ExUnit.Case, async: false

  setup do
    Lithium.TestData.isolate!()
    previous_mailer = Application.get_env(:lithium, :mailer)
    previous_base = Application.get_env(:lithium, :base_url)
    Application.put_env(:lithium, :mailer, Lithium.ReconnectTest.Mailer)
    Application.put_env(:lithium, :base_url, "https://lithium.aldous.cc")

    on_exit(fn ->
      restore(:mailer, previous_mailer)
      restore(:base_url, previous_base)
    end)

    user = Lithium.Accounts.ensure_user("ada@example.com")
    %{user: user}
  end

  test "emails once when Spotify rejects the saved token", %{user: user} do
    :ok =
      Lithium.Credentials.put_service(user.tenant_id, "spotify", %{
        "access_token" => "old",
        "refresh_token" => "old"
      })

    assert {:error, :spotify_auth} =
             Lithium.Sync.run(user.tenant_id, spotify: Lithium.ReconnectTest.Spotify)

    assert_received {:reconnect, "ada@example.com", :spotify, "https://lithium.aldous.cc/spotify"}

    assert {:error, :spotify_auth} =
             Lithium.Sync.run(user.tenant_id, spotify: Lithium.ReconnectTest.Spotify)

    refute_received {:reconnect, _, _, _}

    :ok =
      Lithium.Credentials.put_service(user.tenant_id, "spotify", %{
        "access_token" => "new",
        "refresh_token" => "new"
      })

    assert {:error, :spotify_auth} =
             Lithium.Sync.run(user.tenant_id, spotify: Lithium.ReconnectTest.Spotify)

    assert_received {:reconnect, "ada@example.com", :spotify, "https://lithium.aldous.cc/spotify"}
  end

  test "emails for a rejected Apple token and stays quiet after a successful read", %{user: user} do
    :ok =
      Lithium.Credentials.put_service(user.tenant_id, "apple_music", %{
        "music_user_token" => "music",
        "storefront" => "us"
      })

    :ok =
      Lithium.Credentials.put_service(user.tenant_id, "apple_podcasts", %{
        "media_user_token" => "podcasts",
        "storefront" => "us"
      })

    assert {:error, :favorites_probe_failed} =
             Lithium.Reconnect.note(
               user.tenant_id,
               :apple_music,
               {:error, :favorites_probe_failed}
             )

    refute_received {:reconnect, _, _, _}

    assert {:error, {:http, 401}} =
             Lithium.Reconnect.note(user.tenant_id, :apple_music, {:error, {:http, 401}})

    assert_received {:reconnect, "ada@example.com", :apple_music,
                     "https://lithium.aldous.cc/apple/music"}

    assert {:error, {:http, 401}} =
             Lithium.Reconnect.note(user.tenant_id, :apple_music, {:error, {:http, 401}})

    refute_received {:reconnect, _, _, _}

    assert {:ok, []} = Lithium.Reconnect.note(user.tenant_id, :apple_music, {:ok, []})

    assert {:error, {:http, 401}} =
             Lithium.Reconnect.note(user.tenant_id, :apple_music, {:error, {:http, 401}})

    assert_received {:reconnect, "ada@example.com", :apple_music,
                     "https://lithium.aldous.cc/apple/music"}

    assert {:error, {:unexpected_status, 403}} =
             Lithium.Reconnect.note(
               user.tenant_id,
               :apple_podcasts,
               {:error, {:unexpected_status, 403}}
             )

    assert_received {:reconnect, "ada@example.com", :apple_podcasts,
                     "https://lithium.aldous.cc/apple/podcasts"}
  end

  defp restore(key, nil), do: Application.delete_env(:lithium, key)
  defp restore(key, value), do: Application.put_env(:lithium, key, value)
end
