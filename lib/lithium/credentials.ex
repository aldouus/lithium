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

  def token(credentials, service, field) when is_map(credentials) do
    case credentials do
      %{^service => %{^field => value}} when is_binary(value) and value != "" -> {:ok, value}
      %{^service => %{^field => value}} when is_integer(value) -> {:ok, value}
      _ -> {:error, :missing_credentials}
    end
  end
end
