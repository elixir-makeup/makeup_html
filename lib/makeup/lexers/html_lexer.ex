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

  ###################################################################
  # Step #1: tokenize the input (into a list of tokens)
  ###################################################################

  # Whitespaces
  wspace = ascii_string([?\r, ?\s, ?\n, ?\t, ?\f], min: 1)
  whitespace = token(wspace, :whitespace)

  # Comment
  comment =
    string("<!--")
    |> repeat(lookahead_not(string("-->")) |> utf8_string([], 1))
    |> optional(string("-->"))
    |> token(:comment_multiline)

  # CDATA section
  cdata =
    string("<![CDATA[")
    |> repeat(lookahead_not(string("]]>")) |> utf8_string([], 1))
    |> optional(string("]]>"))
    |> token(:comment_preproc)

  # Processing instruction
  processing_instruction =
    string("<?")
    |> repeat(utf8_string([not: ?>], 1))
    |> optional(string(">"))
    |> token(:comment_preproc)

  # Character reference
  entity =
    string("&")
    |> concat(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?#], min: 1))
    |> concat(string(";"))
    |> token(:name_entity)

  # Doctype
  doctype =
    string("<!")
    |> concat(anycase_string("DOCTYPE"))
    |> repeat(utf8_string([not: ?>], 1))
    |> optional(string(">"))
    |> token(:comment_preproc)

  tag_name_chars = [?a..?z, ?A..?Z, ?0..?9, ?_, ?-, ?:, ?.]
  # A tag name cannot start with a digit. `.` and `:` are for HEEx function
  # components (`<.input>`) and slots (`<:inner_block>`).
  tag_name =
    lookahead(ascii_char([?a..?z, ?A..?Z, ?., ?:]))
    |> concat(ascii_string(tag_name_chars, min: 1))

  attribute_name =
    utf8_string([not: ?\s, not: ?\n, not: ?\r, not: ?\t, not: ?\f, not: ?/, not: ?>, not: ?=],
      min: 1
    )

  quoted_attribute_value =
    choice([
      string("\"") |> repeat(utf8_string([not: ?"], 1)) |> optional(string("\"")),
      string("'") |> repeat(utf8_string([not: ?'], 1)) |> optional(string("'"))
    ])
    |> token(:string)

  unquoted_attribute_value =
    utf8_string([not: ?\s, not: ?\n, not: ?\r, not: ?\t, not: ?\f, not: ?>], min: 1)
    |> token(:string)

  # A space may precede a quoted value, not an unquoted one: `field= name="x"`
  attribute =
    token(attribute_name, :name_attribute)
    |> optional(
      optional(whitespace)
      |> concat(token(string("="), :operator))
      |> optional(
        choice([
          optional(whitespace) |> concat(quoted_attribute_value),
          unquoted_attribute_value
        ])
      )
    )

  # A solidus that does not close the tag, as in `<h/a='b'>`
  stray_solidus = lookahead_not(string("/>")) |> concat(token(string("/"), :punctuation))

  tag_attributes = repeat(choice([whitespace, attribute, stray_solidus]))

  # End tag
  close_tag =
    token(string("</"), :punctuation)
    |> concat(token(tag_name, :name_tag))
    |> optional(whitespace)
    |> concat(token(string(">"), :punctuation))

  # Start tag
  open_tag =
    token(string("<"), :punctuation)
    |> concat(token(tag_name, :name_tag))
    |> concat(tag_attributes)
    |> concat(token(choice([string("/>"), string(">")]), :punctuation))

  # `<` and `>` are ordinary operators in JavaScript and CSS, so a script or
  # style body is one opaque token that ends only at its own close tag
  raw_element = fn name ->
    open =
      token(string("<"), :punctuation)
      |> concat(token(anycase_string(name), :name_tag))
      |> lookahead_not(ascii_char(tag_name_chars))
      |> concat(tag_attributes)
      |> concat(token(string(">"), :punctuation))

    close =
      token(string("</"), :punctuation)
      |> concat(token(anycase_string(name), :name_tag))
      |> optional(whitespace)
      |> concat(token(string(">"), :punctuation))

    body =
      times(lookahead_not(close) |> utf8_string([], 1), min: 1)
      |> reduce({Enum, :join, [""]})
      |> token(:text)

    open |> optional(body) |> optional(close)
  end

  # Text
  text = utf8_string([not: ?<, not: ?&], min: 1) |> token(:text)

  # Unmatched
  any_char = utf8_string([], 1) |> token(:text)

  # Tag the tokens with the language name.
  # This makes it easier to postprocess files with multiple languages.
  @doc false
  def __as_html_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :html), value}
  end

  # First match wins, not longest, so: longest prefix first
  root_element_combinator =
    choice([
      # Markup declarations
      comment,
      cdata,
      doctype,
      processing_instruction,
      # Tags
      raw_element.("script"),
      raw_element.("style"),
      close_tag,
      open_tag,
      # Text
      entity,
      text,
      any_char
    ])

  ##############################################################################
  # Semi-public API: these two functions can be used by someone who wants to
  # embed this lexer into another lexer, but other than that, they are not
  # meant to be used by end-users
  ##############################################################################
  @inline Application.compile_env(:makeup_html, :inline, false)

  # @impl Makeup.Lexer
  defparsec(
    :root_element,
    root_element_combinator |> map({__MODULE__, :__as_html_language__, []}),
    inline: @inline,
    export_combinator: true
  )

  # @impl Makeup.Lexer
  defparsec(
    :root,
    repeat(parsec(:root_element)),
    inline: @inline,
    export_combinator: true
  )

  ###################################################################
  # Step #2: postprocess the list of tokens
  ###################################################################

  @impl Makeup.Lexer
  def postprocess(tokens, _opts \\ []), do: tokens

  #######################################################################
  # Step #3: highlight matching delimiters
  #######################################################################
  @impl Makeup.Lexer
  defgroupmatcher(:match_groups,
    start_closing_tag: [
      open: [[{:punctuation, _, "</"}]],
      close: [[{:punctuation, _, ">"}]]
    ],
    start_tag: [
      open: [[{:punctuation, _, "<"}]],
      close: [[{:punctuation, _, ">"}], [{:punctuation, _, "/>"}]]
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
