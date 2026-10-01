# Adapted from makeup_elixir's benchmarks/main.exs.
alias Makeup.Formatters.HTML.HTMLFormatter
alias Makeup.Lexers.HTMLLexer

# HTML5 Boilerplate's index.html, with the body repeated to a size worth
# measuring. Repeating the whole file would give a document with 100 doctypes.
# See bench/data/LICENSE for its copyright notice.
source_path = Path.join(__DIR__, "data/index.html")

[doctype, body] = source_path |> File.read!() |> String.split("\n", parts: 2)
code = doctype <> "\n" <> String.duplicate(body, 100)
tokens = HTMLLexer.lex(code)

Benchee.run(
  %{
    "Lexer performance" => fn ->
      HTMLLexer.lex(code)
    end,
    "Formatter performance" => fn ->
      HTMLFormatter.format_as_binary(tokens)
    end,
    "Lexer + Formatter" => fn ->
      code
      |> HTMLLexer.lex()
      |> HTMLFormatter.format_as_binary()
    end,
    "Lexer compilation time" => fn ->
      Kernel.ParallelCompiler.compile(["lib/makeup/lexers/html_lexer.ex"])
    end
  },
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false}
  ]
)
