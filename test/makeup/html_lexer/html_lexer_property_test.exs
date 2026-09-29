defmodule HTMLLexerProperty do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Makeup.Formatters.HTML.HTMLFormatter
  alias Makeup.Lexer
  alias Makeup.Lexers.HTMLLexer

  property "lexing is lossless" do
    check all(source <- HTMLGenerators.document(), max_runs: 2_000) do
      assert source |> HTMLLexer.lex() |> Lexer.unlex() == source
    end
  end

  property "every token value is iodata" do
    check all(source <- HTMLGenerators.document(), max_runs: 2_000) do
      for {_ttype, _meta, value} <- HTMLLexer.lex(source) do
        assert is_binary(value) or is_list(value)
      end
    end
  end

  property "the formatter renders every token stream" do
    check all(source <- HTMLGenerators.document(), max_runs: 2_000) do
      assert is_binary(HTMLFormatter.format_as_binary(HTMLLexer.lex(source)))
    end
  end
end
