defmodule Lithium.Secret do
  @moduledoc false

  def get_or_create! do
    root = Application.get_env(:lithium, :data_root) || Path.expand("~/.lithium")
    File.mkdir_p!(root)
    path = Path.join(root, "secret_key")

    case File.read(path) do
      {:ok, key} when byte_size(key) >= 64 ->
        String.trim(key)

      _ ->
        key = Base.url_encode64(:crypto.strong_rand_bytes(48), padding: false)
        File.write!(path, key)
        File.chmod!(path, 0o600)
        key
    end
  end
end
