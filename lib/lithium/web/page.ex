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
    #{apple_music_status(assigns)}
    #{apple_podcasts_status(assigns)}
    <form action="/logout" method="post">
      #{csrf()}
      <button type="submit">Log out</button>
    </form>
    """
  end

  def apple_music(%{ready: false}) do
    document("Connect Apple Music", "<p>Apple Music is not configured yet.</p>")
  end

  def apple_music(_assigns) do
    document("Connect Apple Music", """
    <h1>Connect Apple Music</h1>
    <p id="status">Preparing Apple Music.</p>
    <form id="apple-music" action="/apple/music" method="post">
      #{csrf()}
      <input type="hidden" name="music_user_token">
      <input type="hidden" name="storefront" value="us">
      <button id="connect" type="button" disabled>Connect Apple Music</button>
    </form>
    <script>
      document.addEventListener("musickitloaded", async function () {
        var status = document.getElementById("status");
        var button = document.getElementById("connect");
        var form = document.getElementById("apple-music");
        try {
          var response = await fetch("/apple/music/token");
          var developerToken = (await response.text()).trim();
          if (!response.ok) {
            status.textContent = developerToken;
            return;
          }
          var music = await MusicKit.configure({
            developerToken: developerToken,
            app: { name: "Lithium", build: "0.1.0" }
          });
          button.disabled = false;
          status.textContent = "Apple Music is ready.";
          button.addEventListener("click", async function () {
            button.disabled = true;
            try {
              var userToken = await music.authorize();
              if (!userToken) userToken = music.musicUserToken;
              form.elements.music_user_token.value = userToken || "";
              form.elements.storefront.value = music.storefrontId || "us";
              form.submit();
            } catch (_error) {
              button.disabled = false;
              status.textContent = "Apple Music could not be connected.";
            }
          });
        } catch (_error) {
          status.textContent = "Apple Music could not be prepared.";
        }
      });
    </script>
    <script src="https://js-cdn.music.apple.com/musickit/v3/musickit.js"></script>
    """)
  end

  def apple_podcasts(assigns) do
    document("Connect Apple Podcasts", """
    <h1>Connect Apple Podcasts</h1>
    #{error(assigns[:error])}
    <p>Sign in at <a href="https://podcasts.apple.com">Apple Podcasts</a>.</p>
    <p>Drag <a href="#{escape(assigns.bookmarklet)}">Connect Lithium</a> to the bookmarks bar. On the Apple Podcasts page, click that bookmark. It sends the follow token back here.</p>
    <p>If the bookmark cannot see the token, paste it below.</p>
    <form id="apple-podcasts" action="/apple/podcasts" method="post">
      #{csrf()}
      <label for="media_user_token">Token</label>
      <input id="media_user_token" name="media_user_token" autocomplete="off">
      <button type="submit">Save token</button>
    </form>
    <script>
      var token = location.hash.slice(1);
      if (token) {
        var form = document.getElementById("apple-podcasts");
        form.elements.media_user_token.value = decodeURIComponent(token);
        history.replaceState(null, "", location.pathname);
        form.submit();
      }
    </script>
    """)
  end

  defp notice("sent"), do: "<p>Check your email for a sign-in link.</p>"
  defp notice("invalid"), do: "<p>That sign-in link is no longer valid.</p>"
  defp notice("spotify"), do: "<p>Spotify is connected.</p>"
  defp notice("spotify_failed"), do: "<p>Spotify could not be connected.</p>"
  defp notice("apple_music"), do: "<p>Apple Music is connected.</p>"
  defp notice("apple_music_failed"), do: "<p>Apple Music could not be connected.</p>"
  defp notice("apple_podcasts"), do: "<p>Apple Podcasts is connected.</p>"
  defp notice("apple_podcasts_failed"), do: "<p>Apple Podcasts could not be connected.</p>"
  defp notice(_), do: ""

  defp apple_music_status(assigns) do
    cond do
      assigns.apple_music_connected ->
        "<p>Apple Music is connected.</p>"

      assigns.apple_music_configured ->
        ~s(<p><a href="/apple/music">Connect Apple Music</a></p>)

      true ->
        "<p>Apple Music is not configured yet.</p>"
    end
  end

  defp apple_podcasts_status(assigns) do
    if assigns.apple_podcasts_connected do
      "<p>Apple Podcasts is connected.</p>"
    else
      ~s(<p><a href="/apple/podcasts">Connect Apple Podcasts</a></p>)
    end
  end

  defp error(nil), do: ""
  defp error(message), do: "<p>#{escape(message)}</p>"

  defp csrf do
    token = Plug.CSRFProtection.get_csrf_token()
    ~s(<input type="hidden" name="_csrf_token" value="#{escape(token)}">)
  end

  defp document(_title, body) when body in [nil, ""], do: ""

  defp document(title, body) do
    if markup?(body) do
      """
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>#{escape(title)}</title>
        </head>
        <body>
          #{body}
        </body>
      </html>
      """
    else
      body
    end
  end

  defp markup?(body) when is_binary(body), do: String.contains?(body, "<")
  defp markup?(_body), do: false

  defp escape(value) do
    value |> to_string() |> Plug.HTML.html_escape()
  end
end
