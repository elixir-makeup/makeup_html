defmodule HTMLLexerTokenizer do
  use ExUnit.Case, async: false
  use ExUnitProperties
  alias Makeup.Lexers.HTMLLexer
  alias Makeup.Lexer.Postprocess

  # This function has three purposes:
  # 1. Ensure deterministic lexer output (no random prefix)
  # 2. Convert the token values into binaries so that the output
  #    is more obvious on visual inspection
  #    (iolists are hard to parse by a human)
  # 3. remove language metadata
  def lex(text) do
    text
    |> HTMLLexer.lex(group_prefix: "group")
    |> Postprocess.token_values_to_binaries()
    |> Enum.map(fn {ttype, meta, value} -> {ttype, Map.delete(meta, :language), value} end)
  end

  test "empty string" do
    assert lex("") == []
  end

  property "HTML document does not produce errors" do
    check all(document <- HTMLGenerators.document()) do
      assert !Enum.any?(lex(document), &match?({:error, _, _}, &1))
    end
  end
end
