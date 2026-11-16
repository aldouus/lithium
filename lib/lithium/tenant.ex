defmodule Lithium.Tenant do
  @moduledoc false

  @id_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/

  def root do
    Application.fetch_env!(:lithium, :data_root)
  end

  def valid_id?(tenant_id) when is_binary(tenant_id), do: Regex.match?(@id_pattern, tenant_id)
  def valid_id?(_), do: false

  def directory(tenant_id) do
    with :ok <- check_id(tenant_id) do
      {:ok, Path.join([root(), "tenants", tenant_id])}
    end
  end

  def database_path(tenant_id) do
    with {:ok, dir} <- directory(tenant_id), do: {:ok, Path.join(dir, "library.db")}
  end

  def credentials_path(tenant_id) do
    with {:ok, dir} <- directory(tenant_id), do: {:ok, Path.join(dir, "credentials.json")}
  end

  def ensure(tenant_id) do
    with {:ok, dir} <- directory(tenant_id) do
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o700)
      {:ok, dir}
    end
  end

  def list do
    tenants = Path.join(root(), "tenants")

    case File.ls(tenants) do
      {:ok, names} ->
        names
        |> Enum.filter(&valid_id?/1)
        |> Enum.filter(&File.dir?(Path.join(tenants, &1)))
        |> Enum.sort()

      {:error, :enoent} ->
        []
    end
  end

  defp check_id(tenant_id) do
    if valid_id?(tenant_id), do: :ok, else: {:error, :invalid_tenant}
  end
end
