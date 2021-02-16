defmodule Makeup.Lexers.HTMLLexer.Combinators do
  @moduledoc false
  import NimbleParsec
  import Makeup.Lexer.Combinators

  def keyword(string), do: string |> token(:keyword)

  # Insensitive string
  # https://elixirforum.com/t/nimbleparsec-case-insensitive-matches/14339/2
  def anycase_string(string) do
    string
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.reverse()
    |> char_piper
    |> reduce({List, :to_string, []})
  end

  defp char_piper([c]) when c in ?A..?Z do
    c
    |> both_cases
    |> ascii_char
  end

  defp char_piper([c | rest]) when c in ?A..?Z do
    rest
    |> char_piper
    |> ascii_char(both_cases(c))
  end

  defp char_piper([c]) do
    ascii_char([c])
  end

  defp char_piper([c | rest]) do
    rest
    |> char_piper
    |> ascii_char([c])
  end

  defp both_cases(c) do
    [c, c + 32]
  end
end
