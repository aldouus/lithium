defmodule Lithium.Web.Page do
  @moduledoc false

  def home(assigns) do
    document("Lithium", if(assigns.user, do: account(assigns), else: login(assigns)))
  end

  defp login(assigns) do
    """
    <h1>Sign in</h1>
    #{notice(assigns.notice)}
    #{error(assigns.error)}
    <form action="/login" method="post">
      #{csrf()}
      <label for="email">Email</label>
      <input id="email" name="email" type="email" autocomplete="email" required>
      <button type="submit">Email me a sign-in link</button>
    </form>
    """
  end

  defp account(assigns) do
    spotify =
      if assigns.spotify_configured do
        if assigns.spotify_connected do
          "<p>Spotify is connected.</p>"
        else
          ~s(<p><a href="/spotify">Connect Spotify</a></p>)
        end
      else
        "<p>Spotify client credentials are not set yet.</p>"
      end

    """
    <h1>Account</h1>
    #{notice(assigns.notice)}
    <p>Signed in as #{escape(assigns.user.email)}.</p>
    #{spotify}
    <form action="/logout" method="post">
      #{csrf()}
      <button type="submit">Log out</button>
    </form>
    """
  end

  defp notice("sent"), do: "<p>Check your email for a sign-in link.</p>"
  defp notice("invalid"), do: "<p>That sign-in link is no longer valid.</p>"
  defp notice("spotify"), do: "<p>Spotify is connected.</p>"
  defp notice("spotify_failed"), do: "<p>Spotify could not be connected.</p>"
  defp notice(_), do: ""

  defp error(nil), do: ""
  defp error(message), do: "<p>#{escape(message)}</p>"

  defp csrf do
    token = Plug.CSRFProtection.get_csrf_token()
    ~s(<input type="hidden" name="_csrf_token" value="#{escape(token)}">)
  end

  defp document(title, body) do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(title)}</title>
        <style>
          body { font: 16px/1.5 ui-sans-serif, system-ui, sans-serif; margin: 3rem auto; max-width: 32rem; padding: 0 1rem; }
          label, input, button { display: block; }
          input { margin: 0.25rem 0 1rem; padding: 0.4rem 0.5rem; width: 100%; }
          button { padding: 0.4rem 0.8rem; }
        </style>
      </head>
      <body>
        #{body}
      </body>
    </html>
    """
  end

  defp escape(value) do
    value |> to_string() |> Plug.HTML.html_escape()
  end
end
