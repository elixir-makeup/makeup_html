defmodule MakeupHTML.Mixfile do
  use Mix.Project

  def project do
    [
      app: :makeup_html,
      version: "0.2.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Package
      package: package(),
      description: description(),
      docs: [
        main: "readme",
        extras: ["README.md"]
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
      licenses: ["MIT"],
      maintainers: ["Javier Garea <javigarea@gmail.com>"],
      links: %{"GitHub" => "https://github.com/elixir-makeup/makeup_html"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [],
      mod: {Makeup.Lexers.HTMLLexer.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Pinned for the formatter fix in elixir-makeup/makeup#77.
      # Back to `{:makeup, "~> 1.2"}` once it is released, hex rejects git deps.
      {:makeup,
       github: "elixir-makeup/makeup",
       ref: "6773349d54f55fd8a408c53a50108c0f41bff271",
       override: true},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end
end
