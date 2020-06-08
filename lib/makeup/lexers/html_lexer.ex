defmodule Makeup.Lexers.HTMLLexer do
  @moduledoc """
  Lexer for the HTML language to be used
  with the Makeup package.
  """
  @behaviour Makeup.Lexer

  import NimbleParsec
  import Makeup.Lexer.Combinators
  import Makeup.Lexer.Groups

  ###################################################################
  # Step #1: tokenize the input (into a list of tokens)
  ###################################################################

  whitespace = ascii_string([?\s, ?\n], min: 1) |> token(:whitespace)

  # This is the combinator that ensures that the lexer will never reject a file
  # because of invalid input syntax
  any_char = utf8_char([]) |> token(:error)

  # Numbers
  digits = ascii_string([?0..?9], min: 1)
  number_integer = token(digits, :number_integer)

  # Floating point numbers
  float_scientific_notation_part =
    ascii_string([?e, ?E], 1)
    |> optional(string("-"))
    |> concat(digits)

  number_float =
    number_integer
    |> string(".")
    |> concat(digits)
    |> optional(float_scientific_notation_part)
    |> token(:number_float)

  # Yes, Elixir supports much more than this.
  # TODO: adapt the code from the official tokenizer, which parses the unicode database
  variable_name =
    ascii_string([?a..?z, ?_], 1)
    |> optional(ascii_string([?a..?z, ?_, ?0..?9, ?A..?Z], min: 1))

  # Can also be a function name
  variable =
    variable_name
    # Check if you need to use the lexeme parser
    # (i.e. if you need the token value to be a string)
    # If not, just delete the lexeme parser
    |> lexeme
    |> token(:name)

  # Combinators that highlight expressions surrounded by a pair of delimiters.
  parentheses = many_surrounded_by(parsec(:root_element), "(", ")")
  straight_brackets = many_surrounded_by(parsec(:root_element), "[", "]")
  curly_braces = many_surrounded_by(parsec(:root_element), "{", "}")

  # Tag the tokens with the language name.
  # This makes it easier to postprocess files with multiple languages.
  @doc false
  def __as_html_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :html), value}
  end

  root_element_combinator =
    choice([
      whitespace,
      # Parenthesis, etc. (these might be unnecessary)
      parentheses,
      straight_brackets,
      curly_braces,
      # Numbers
      number_float,
      number_integer,
      # Variables
      variable,
      # If we can't parse any of the above, we highlight the next character as an error
      # and proceed from there.
      # A lexer should always consume any string given as input.
      any_char
    ])

  ##############################################################################
  # Semi-public API: these two functions can be used by someone who wants to
  # embed this lexer into another lexer, but other than that, they are not
  # meant to be used by end-users
  ##############################################################################

  @inline Application.get_env(:makeup_html, :inline, false)

  @impl Makeup.Lexer
  defparsec(
    :root_element,
    root_element_combinator |> map({__MODULE__, :__as_html_language__, []}),
    inline: @inline
  )

  @impl Makeup.Lexer
  defparsec(
    :root,
    repeat(parsec(:root_element)),
    inline: @inline
  )

  ###################################################################
  # Step #2: postprocess the list of tokens
  ###################################################################

  # By default, return the list of tokens unchanged
  @impl Makeup.Lexer
  def postprocess(tokens, _opts \\ []), do: tokens

  #######################################################################
  # Step #3: highlight matching delimiters
  # By default, this includes delimiters that are used in many languages,
  # but feel free to delete these or add more.
  #######################################################################

  @impl Makeup.Lexer
  defgroupmatcher(:match_groups,
    parentheses: [
      open: [[{:punctuation, _, "("}]],
      close: [[{:punctuation, _, ")"}]]
    ],
    straight_brackets: [
      open: [
        [{:punctuation, _, "["}]
      ],
      close: [
        [{:punctuation, _, "]"}]
      ]
    ],
    curly_braces: [
      open: [
        [{:punctuation, _, "{"}]
      ],
      close: [
        [{:punctuation, _, "}"}]
      ]
    ]
  )

  # Finally, the public API for the lexer
  @impl Makeup.Lexer
  def lex(text, opts \\ []) do
    group_prefix = Keyword.get(opts, :group_prefix, random_prefix(10))
    {:ok, tokens, "", _, _, _} = root(text)

    tokens
    |> postprocess()
    |> match_groups(group_prefix)
  end
end
