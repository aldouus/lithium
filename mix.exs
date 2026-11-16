defmodule Lithium.MixProject do
  use Mix.Project

  def project do
    [
      app: :lithium,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :inets, :ssl],
      mod: {Lithium.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:exqlite, "~> 0.27"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:plug, "~> 1.16"}
    ]
  end
end
