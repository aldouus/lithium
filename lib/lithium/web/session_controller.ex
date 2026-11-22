defmodule Lithium.Web.SessionController do
  use Phoenix.Controller, formats: [:html]

  require Logger

  import Plug.Conn

  @email ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  def home(conn, params) do
    render_home(conn, notice: params["notice"], error: nil)
  end

  def create(conn, %{"email" => email}) do
    with {:ok, email} <- normalize_email(email),
         {:ok, token, _claims} <- magic_token(email),
         :ok <- Lithium.Mailer.deliver_magic_link(email, verify_url(conn, token)) do
      redirect(conn, to: "/?notice=sent")
    else
      {:error, :invalid_email} ->
        render_home(conn, notice: nil, error: "Enter a valid email address.")

      {:error, :missing_resend_key} ->
        render_home(conn, notice: nil, error: "Email is not configured yet. Set RESEND_API_KEY.")

      {:error, reason} ->
        Logger.error("magic link email failed: #{inspect(reason)}")
        render_home(conn, notice: nil, error: "The sign-in email could not be sent.")
    end
  end

  def create(conn, _params) do
    render_home(conn, notice: nil, error: "Enter a valid email address.")
  end

  def verify(conn, %{"token" => token}) do
    with {:ok, claims} <- Lithium.Web.Auth.decode_and_verify(token, %{"typ" => "magic"}),
         :ok <- Lithium.Accounts.consume_jti(claims["jti"]),
         email when is_binary(email) <- claims["sub"],
         {:ok, email} <- normalize_email(email) do
      user = Lithium.Accounts.ensure_user(email)

      conn
      |> Lithium.Web.Auth.Plug.sign_in(user)
      |> redirect(to: "/")
    else
      _ -> redirect(conn, to: "/?notice=invalid")
    end
  end

  def verify(conn, _params), do: redirect(conn, to: "/?notice=invalid")

  def delete(conn, _params) do
    conn
    |> Lithium.Web.Auth.Plug.sign_out()
    |> redirect(to: "/")
  end

  defp render_home(conn, assigns) do
    user = Guardian.Plug.current_resource(conn)
    credentials = credentials(user)

    body =
      Lithium.Web.Page.home(%{
        user: user,
        notice: assigns[:notice],
        error: assigns[:error],
        spotify_configured: Lithium.Spotify.OAuth.configured?(),
        spotify_connected: connected?(credentials, "spotify", "refresh_token"),
        apple_music_configured: Lithium.AppleToken.configured?(),
        apple_music_connected: connected?(credentials, "apple_music", "music_user_token"),
        apple_podcasts_connected: connected?(credentials, "apple_podcasts", "media_user_token")
      })

    content_type = if String.contains?(body, "<"), do: "text/html", else: "text/plain"

    conn
    |> put_resp_content_type(content_type)
    |> send_resp(200, body)
  end

  defp magic_token(email) do
    Lithium.Web.Auth.encode_and_sign(%{email: email}, %{},
      token_type: "magic",
      ttl: {2, :hours}
    )
  end

  defp verify_url(conn, token) do
    Lithium.Web.Origin.join(conn, "/login/verify?token=#{URI.encode_www_form(token)}")
  end

  defp normalize_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if Regex.match?(@email, email) do
      {:ok, email}
    else
      {:error, :invalid_email}
    end
  end

  defp normalize_email(_email), do: {:error, :invalid_email}

  defp credentials(nil), do: %{}

  defp credentials(user) do
    case Lithium.Credentials.read(user.tenant_id) do
      {:ok, credentials} -> credentials
      _ -> %{}
    end
  end

  defp connected?(credentials, service, field) do
    match?({:ok, _token}, Lithium.Credentials.token(credentials, service, field))
  end
end
