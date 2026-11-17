defmodule Lithium.Web.AuthError do
  @behaviour Guardian.Plug.ErrorHandler

  import Phoenix.Controller
  import Plug.Conn

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, _error, _opts) do
    conn
    |> redirect(to: "/")
    |> halt()
  end
end
