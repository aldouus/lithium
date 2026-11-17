defmodule Lithium.Web.Pipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :lithium,
    module: Lithium.Web.Auth,
    error_handler: Lithium.Web.AuthError

  plug(Guardian.Plug.VerifySession, claims: %{"typ" => "access"})
  plug(Guardian.Plug.LoadResource, allow_blank: true)
end
