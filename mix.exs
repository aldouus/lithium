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
      extra_applications: [:logger, :crypto, :public_key, :inets, :ssl, :xmerl],
      mod: {Lithium.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:ecto, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.26"},
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.5"},
      {:guardian, "~> 2.5"},
      {:resend, "~> 0.4.5"},
      {:oauth2, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"}
    ]
  end
end
