defmodule MakeupHTML.Mixfile do
  use Mix.Project

  def project do
    [
      app: :makeup_html,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Package
      package: package(),
      description: description(),
      docs: [
        main: "readme",
        extras: [
          "README.md"
        ]
      ]
    ]
  end

  defp description do
    """
    HTML lexer for the Makeup syntax highlighter.
    """
  end

  defp package do
    [
      name: :makeup_html,
      licenses: ["BSD"],
      maintainers: ["Javier Garea <javigarea@gmail.com>"],
      links: %{"GitHub" => "https://github.com/javiergarea/makeup_html"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:makeup, "~> 0.5.0"},
      {:ex_doc, "~> 0.18.3", only: [:dev]},
      {:stream_data, "~> 0.5.0", only: :test}
    ]
  end
end
