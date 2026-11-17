defmodule Lithium.Mailer do
  @moduledoc false

  def deliver_magic_link(email, url) when is_binary(email) and is_binary(url) do
    case Application.get_env(:lithium, :mailer) do
      module when is_atom(module) and not is_nil(module) ->
        module.deliver_magic_link(email, url)

      _ ->
        send_with_resend(email, url)
    end
  end

  defp send_with_resend(email, url) do
    case Application.get_env(:lithium, :resend_api_key) do
      key when is_binary(key) and key != "" ->
        client = Resend.client(api_key: key)

        client
        |> Resend.Emails.send(%{
          from: Application.get_env(:lithium, :resend_from),
          to: [email],
          subject: "Sign in to Lithium",
          text: "Sign in to Lithium:\n\n#{url}\n",
          html: ~s(<p><a href="#{escape(url)}">Sign in to Lithium</a></p>)
        })
        |> case do
          {:ok, _email} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :missing_resend_key}
    end
  end

  defp escape(value) do
    Plug.HTML.html_escape(value)
  end
end
