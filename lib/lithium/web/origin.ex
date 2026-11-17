defmodule Lithium.Web.Origin do
  @moduledoc false

  def join(conn, path) do
    origin(conn) <> path
  end

  def origin(conn) do
    case Application.get_env(:lithium, :base_url) do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/")

      _ ->
        URI.to_string(%URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port})
    end
  end
end
