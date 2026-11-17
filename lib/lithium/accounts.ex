defmodule Lithium.Accounts do
  @moduledoc false

  alias Lithium.Accounts.LoginToken
  alias Lithium.Accounts.Repo
  alias Lithium.Accounts.User

  def with_repo(fun) when is_function(fun, 0) do
    root = Lithium.Tenant.root()
    File.mkdir_p!(root)
    path = Path.join(root, "accounts.db")

    {:ok, pid} =
      Repo.start_link(name: nil, database: path, pool_size: 1, journal_mode: :wal)

    try do
      previous = Repo.put_dynamic_repo(pid)

      try do
        Ecto.Migrator.run(
          Repo,
          [{20_261_117_120_000, Lithium.Accounts.Migration}],
          :up,
          all: true,
          log: false
        )

        fun.()
      after
        Repo.put_dynamic_repo(previous)
      end
    after
      Supervisor.stop(pid)
    end
  end

  def ensure_user(email) when is_binary(email) do
    with_repo(fn ->
      case Repo.get_by(User, email: email) do
        %User{} = user ->
          {:ok, _} = Lithium.Tenant.ensure(user.tenant_id)
          user

        nil ->
          tenant_id = tenant_id_for(email)
          {:ok, _} = Lithium.Tenant.ensure(tenant_id)
          Repo.insert!(%User{email: email, tenant_id: tenant_id})
      end
    end)
  end

  def get_user(id) when is_integer(id) do
    with_repo(fn -> Repo.get(User, id) end)
  end

  def consume_jti(jti) when is_binary(jti) do
    with_repo(fn ->
      now = DateTime.utc_now()

      case Repo.insert_all(LoginToken, [%{jti: jti, inserted_at: now}],
             on_conflict: :nothing,
             conflict_target: [:jti]
           ) do
        {1, _} -> :ok
        {0, _} -> {:error, :used}
      end
    end)
  end

  def tenant_id_for(email) when is_binary(email) do
    hash = :crypto.hash(:sha256, email)
    "u" <> Base.encode16(binary_part(hash, 0, 8), case: :lower)
  end
end
