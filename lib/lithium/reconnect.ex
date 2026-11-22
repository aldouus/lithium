defmodule Lithium.Reconnect do
  @moduledoc false

  @services [:spotify, :apple_music, :apple_podcasts]

  def note(tenant_id, service, result)
      when is_binary(tenant_id) and service in @services and
             is_tuple(result) and elem(result, 0) == :ok do
    clear(tenant_id, service)
    result
  end

  def note(tenant_id, service, {:error, _} = result)
      when is_binary(tenant_id) and service in @services do
    if disconnected?(service, result), do: notify(tenant_id, service)
    result
  end

  def note(_tenant_id, _service, result), do: result

  def notify(tenant_id, service) when is_binary(tenant_id) and service in @services do
    key = Atom.to_string(service)

    with {:ok, credentials} <- Lithium.Credentials.read(tenant_id),
         %{} = section <- Map.get(credentials, key),
         false <- section["reconnect_sent"] == true,
         %Lithium.Accounts.User{email: email} <- Lithium.Accounts.get_by_tenant_id(tenant_id),
         :ok <- Lithium.Mailer.deliver_reconnect(email, service, url(service)) do
      Lithium.Credentials.put_service(tenant_id, key, Map.put(section, "reconnect_sent", true))
    else
      _ -> :ok
    end
  end

  defp clear(tenant_id, service) do
    key = Atom.to_string(service)

    with {:ok, credentials} <- Lithium.Credentials.read(tenant_id),
         %{} = section <- Map.get(credentials, key),
         true <- section["reconnect_sent"] == true do
      Lithium.Credentials.put_service(tenant_id, key, Map.delete(section, "reconnect_sent"))
    else
      _ -> :ok
    end
  end

  defp disconnected?(:spotify, {:error, :spotify_auth}), do: true
  defp disconnected?(:apple_music, {:error, {:http, 401}}), do: true

  defp disconnected?(:apple_podcasts, {:error, {:unexpected_status, status}})
       when status in [401, 403],
       do: true

  defp disconnected?(_service, _result), do: false

  defp url(:spotify), do: join("/spotify")
  defp url(:apple_music), do: join("/apple/music")
  defp url(:apple_podcasts), do: join("/apple/podcasts")

  defp join(path) do
    case Application.get_env(:lithium, :base_url) do
      base when is_binary(base) and base != "" -> String.trim_trailing(base, "/") <> path
      _ -> path
    end
  end
end
