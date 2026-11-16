defmodule Lithium.AppleToken do
  @moduledoc false

  @max_lifetime 15_777_000

  def developer_token(opts \\ []) do
    team_id = Keyword.get(opts, :team_id, Application.get_env(:lithium, :apple_team_id))
    key_id = Keyword.get(opts, :key_id, Application.get_env(:lithium, :apple_key_id))
    pem = Keyword.get(opts, :pem, load_pem())

    with :ok <- present(team_id, 10),
         :ok <- present(key_id, 10),
         :ok <- present_pem(pem) do
      now = System.system_time(:second)
      lifetime = min(Keyword.get(opts, :lifetime, 86_400), @max_lifetime)
      claims = %{"iss" => team_id, "iat" => now, "exp" => now + lifetime}
      signer = JOSE.JWS.from_map(%{"alg" => "ES256", "kid" => key_id})
      jwk = JOSE.JWK.from_pem(pem)
      signed = JOSE.JWT.sign(jwk, signer, JOSE.JWT.from_map(claims))
      {_meta, token} = JOSE.JWS.compact(signed)
      {:ok, token}
    end
  end

  defp load_pem do
    path = Application.get_env(:lithium, :apple_private_key_path)

    cond do
      is_binary(path) and path != "" and File.regular?(path) -> File.read!(path)
      true -> nil
    end
  end

  defp present(value, length) when is_binary(value) and byte_size(value) == length, do: :ok
  defp present(_, _), do: {:error, :missing_apple_key}

  defp present_pem(pem) when is_binary(pem) and pem != "", do: :ok
  defp present_pem(_), do: {:error, :missing_apple_key}
end
