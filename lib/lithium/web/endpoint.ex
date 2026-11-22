defmodule Lithium.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :lithium

  @session_options [
    store: :cookie,
    key: "_lithium_session",
    signing_salt: "lithium-session",
    same_site: "Lax",
    max_age: 30 * 24 * 60 * 60
  ]

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(Lithium.Web.Router)
end
