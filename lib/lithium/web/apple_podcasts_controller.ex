defmodule Lithium.Web.ApplePodcastsController do
  use Phoenix.Controller, formats: [:html]

  def show(conn, params) do
    html(conn, page(conn, params["error"]))
  end

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, token} <- user_token(params["media_user_token"]),
         :ok <-
           Lithium.Credentials.put_service(user.tenant_id, "apple_podcasts", %{
             "media_user_token" => token,
             "storefront" => storefront(user.tenant_id)
           }) do
      redirect(conn, to: "/?notice=apple_podcasts")
    else
      _ -> html(conn, page(conn, "That token could not be saved."))
    end
  end

  defp page(conn, error) do
    Lithium.Web.Page.apple_podcasts(%{
      bookmarklet: bookmarklet(Lithium.Web.Origin.join(conn, "/apple/podcasts")),
      error: error
    })
  end

  defp bookmarklet(return_url) do
    "javascript:" <>
      "(function(){var m=document.cookie.match(/(?:^|; )media-user-token=([^;]+)/);" <>
      "if(!m){alert(\"Sign in to Apple Podcasts on this page, then click this bookmark again.\");return;}" <>
      "location.href=#{Jason.encode!(return_url)}+\"#\"+encodeURIComponent(m[1]);})();"
  end

  defp user_token(token) when is_binary(token) do
    token = String.trim(token)
    if byte_size(token) >= 20, do: {:ok, token}, else: :error
  end

  defp user_token(_token), do: :error

  defp storefront(tenant_id) do
    case Lithium.Credentials.read(tenant_id) do
      {:ok, credentials} ->
        case Lithium.Credentials.token(credentials, "apple_music", "storefront") do
          {:ok, storefront} -> storefront
          _ -> "us"
        end

      _ ->
        "us"
    end
  end
end
