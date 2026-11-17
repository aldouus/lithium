defmodule Lithium.Credentials do
  @moduledoc false

  def read(tenant_id) do
    with {:ok, path} <- Lithium.Tenant.credentials_path(tenant_id),
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      {:error, :enoent} -> {:error, :missing_credentials}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  def put_service(tenant_id, service, fields) when is_binary(service) and is_map(fields) do
    with {:ok, _} <- Lithium.Tenant.ensure(tenant_id),
         {:ok, path} <- Lithium.Tenant.credentials_path(tenant_id),
         {:ok, current} <- read_or_empty(tenant_id) do
      File.write!(path, Jason.encode!(Map.put(current, service, fields)))
      File.chmod!(path, 0o600)
      :ok
    end
  end

  def token(credentials, service, field) when is_map(credentials) do
    case credentials do
      %{^service => %{^field => value}} when is_binary(value) and value != "" -> {:ok, value}
      %{^service => %{^field => value}} when is_integer(value) -> {:ok, value}
      _ -> {:error, :missing_credentials}
    end
  end

  defp read_or_empty(tenant_id) do
    case read(tenant_id) do
      {:ok, map} -> {:ok, map}
      {:error, :missing_credentials} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end
end
