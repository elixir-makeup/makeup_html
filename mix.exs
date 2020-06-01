defmodule MakeupHTML.Mixfile do
  use Mix.Project

  def project do
    [
      app: :makeup_html,
      version: "0.4.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:makeup, "~> 0.5.0"},
      {:ex_doc, "~> 0.18.3", only: [:dev]},
    ]
  end
end
