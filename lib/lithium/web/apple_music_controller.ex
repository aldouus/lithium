defmodule Lithium.Web.AppleMusicController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  def show(conn, _params) do
    body =
      if Lithium.AppleToken.configured?() do
        Lithium.Web.Page.apple_music(%{ready: true})
      else
        Lithium.Web.Page.apple_music(%{ready: false})
      end

    html(conn, body)
  end

  def token(conn, _params) do
    case Lithium.AppleToken.developer_token(origin: Lithium.Web.Origin.origin(conn)) do
      {:ok, token} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, token)

      {:error, :missing_apple_key} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "Apple Music is not configured yet.")
    end
  end

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, token} <- user_token(params["music_user_token"]),
         :ok <-
           Lithium.Credentials.put_service(user.tenant_id, "apple_music", %{
             "music_user_token" => token,
             "storefront" => storefront(params["storefront"])
           }) do
      redirect(conn, to: "/?notice=apple_music")
    else
      _ -> redirect(conn, to: "/?notice=apple_music_failed")
    end
  end

  defp user_token(token) when is_binary(token) do
    token = String.trim(token)
    if byte_size(token) >= 20, do: {:ok, token}, else: :error
  end

  defp user_token(_token), do: :error

  defp storefront(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()
    if Regex.match?(~r/\A[a-z]{2}\z/, value), do: value, else: "us"
  end

  defp storefront(_value), do: "us"
end
