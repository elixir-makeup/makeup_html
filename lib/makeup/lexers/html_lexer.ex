defmodule Makeup.Lexers.HTMLLexer do
  @moduledoc """
  Lexer for the HTML language to be used
  with the Makeup package.
  """
  @behaviour Makeup.Lexer

  import NimbleParsec
  import Makeup.Lexer.Combinators
  import Makeup.Lexer.Groups
  import Makeup.Lexers.HTMLLexer.Combinators
  alias Makeup.Lexers.HTMLLexer.HTMLElements
  alias Makeup.Lexers.HTMLLexer.HTMLAttributes

  @keywords HTMLElements.get_elements() ++
              HTMLAttributes.get_attributes() ++ HTMLAttributes.get_event_handler_attributes()

  ###################################################################
  # Step #1: tokenize the input (into a list of tokens)
  ###################################################################

  wspace = ascii_string([?\r, ?\s, ?\n, ?\f], min: 1)

  whitespace = wspace |> token(:whitespace)

  # This is the combinator that ensures that the lexer will never reject a file
  # because of invalid input syntax
  any_char = utf8_char([]) |> token(:error)

  keywords = Enum.map(@keywords, &keyword/1)

  operators =
    ascii_string([?=], 1)
    |> token(:operator)

  doctype =
    "<!"
    |> string()
    |> concat(anycase_string("DOCTYPE"))
    |> optional(wspace)
    |> concat(anycase_string("html"))
    # optional doctype legacy string
    |> optional(wspace)
    |> concat(string(">"))
    |> token(:keyword)

  insensitive_string =
    ascii_string([?a..?z, ?A..?Z, ?0..?9], 1)
    |> optional(
      ascii_string([?a..?z, ?_, ?0..?9, ?A..?Z, ?\r, ?\s, ?\n, ?\f, ?>, ?<, ?!], min: 1)
    )
    |> lexeme
    |> token(:string)

  # Combinators that highlight expressions surrounded by a pair of delimiters.
  start_tag = many_surrounded_by(parsec(:root_element), "<", ">")
  end_tag = many_surrounded_by(parsec(:root_element), "</", ">")
  single_tag = many_surrounded_by(parsec(:root_element), "<", "/>")
  comment_tag = many_surrounded_by(parsec(:root_element), "<!--", "-->")
  doctype_tag = many_surrounded_by(parsec(:root_element), "<!", ">")
  attribute_delimiters = many_surrounded_by(parsec(:root_element), "\"", "\"")

  # Tag the tokens with the language name.
  # This makes it easier to postprocess files with multiple languages.
  @doc false
  def __as_html_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :html), value}
  end

  root_element_combinator =
    choice(
      [
        doctype,
        operators,
        # Delimiters
        comment_tag,
        doctype_tag,
        single_tag,
        end_tag,
        start_tag,
        attribute_delimiters
      ] ++
        keywords ++
        [
          insensitive_string,
          whitespace,
          # Error
          any_char
        ]
    )

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
    start_tag: [
      open: [[{:punctuation, _, "<"}]],
      close: [[{:punctuation, _, ">"}]]
    ],
    end_tag: [
      open: [[{:punctuation, _, "</"}]],
      close: [[{:punctuation, _, ">"}]]
    ],
    single_tag: [
      open: [[{:punctuation, _, "<"}]],
      close: [[{:punctuation, _, "/>"}]]
    ],
    comment_tag: [
      open: [[{:punctuation, _, "<!--"}]],
      close: [[{:punctuation, _, "-->"}]]
    ],
    doctype_tag: [
      open: [[{:punctuation, _, "<!"}]],
      close: [[{:punctuation, _, ">"}]]
    ],
    attribute_delimiters: [
      open: [[{:punctuation, _, "\""}]],
      close: [[{:punctuation, _, "\""}]]
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
