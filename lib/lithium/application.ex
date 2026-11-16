defmodule Lithium.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Lithium.Worker]
    Supervisor.start_link(children, strategy: :one_for_one, name: Lithium.Supervisor)
  end
end
