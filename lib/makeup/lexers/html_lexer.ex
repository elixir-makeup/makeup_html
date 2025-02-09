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

  @attributes MapSet.new(get_attributes() ++ get_event_handler_attributes())

  ###################################################################
  # Step #1: tokenize the input (into a list of tokens)
  ###################################################################

  # Whitespaces
  wspace = ascii_string([?\r, ?\s, ?\n, ?\f], min: 1)

  whitespace =
    wspace
    |> token(:whitespace)

  # Doctype
  legacy_doctype_string =
    wspace
    |> optional()
    |> concat(anycase_string("SYSTEM"))
    |> optional(wspace)
    |> concat(
      choice([
        string("\"about:legacy-compat\""),
        string("'about:legacy-compat'")
      ])
    )

  doctype =
    "<!"
    |> string()
    |> concat(anycase_string("DOCTYPE"))
    |> optional(wspace)
    |> concat(anycase_string("html"))
    |> optional(legacy_doctype_string)
    |> optional(wspace)
    |> concat(string(">"))
    |> token(:comment_preproc)

  # Operators
  operators =
    "="
    |> string()
    |> token(:operator)

  # Combinators that highlight expressions surrounded by a pair of delimiters.
  comment_tag =
    string("<!--")
    |> concat(
      repeat(
        lookahead_not(string("-->"))
        |> utf8_string([], 1)
      )
    )
    |> string("-->")
    |> token(:comment)

  name_tag =
    ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?-, ?:, ?.], min: 1)
    |> token(:name_tag)

  # Single punctuation symbols
  open_tag =
    "<"
    |> string()
    |> token(:punctuation)
    |> concat(name_tag)

  close_tag =
    ">"
    |> string()
    |> token(:punctuation)

  close_self_tag =
    "/>"
    |> string()
    |> token(:punctuation)

  open_closing_tag =
    "</"
    |> string()
    |> token(:punctuation)
    |> concat(name_tag)

  # Currently we match attributes anywhere in the text
  attributes = utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?-, ?:, ?.], min: 1) |> token(:keyword)

  # Unmatched
  insensitive_char = utf8_char([]) |> token(:char)

  # Tag the tokens with the language name.
  # This makes it easier to postprocess files with multiple languages.
  @doc false
  def __as_html_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :html), value}
  end

  root_element_combinator =
    choice([
      # Doctype
      doctype,
      # Operators
      operators,
      # Delimiters
      comment_tag,
      open_closing_tag,
      open_tag,
      close_self_tag,
      close_tag,
      # Text
      whitespace,
      attributes,
      insensitive_char
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
    inline: @inline
  )

  # @impl Makeup.Lexer
  defparsec(
    :root,
    repeat(parsec(:root_element)),
    inline: @inline
  )

  ###################################################################
  # Step #2: postprocess the list of tokens
  ###################################################################

  ###
  # Merges a list of tokens into a single 'string' token
  ###
  defp merge_string([{_, _, string} | tokens], result) when is_list(string),
    do: merge_string(tokens, result ++ string)

  defp merge_string([{_, _, string} | tokens], result) when is_binary(string),
    do: merge_string(tokens, result ++ [string])

  defp merge_string([{_, _, string} | tokens], result) when is_integer(string),
    do: merge_string(tokens, result ++ [string])

  defp merge_string([], []), do: []
  defp merge_string([], result), do: [{:string, %{language: :html}, result}]

  defp merge_string(stringlist), do: stringlist |> merge_string([])

  ###
  # Converts traces of the form [char]+ into a single string
  ###
  defp char_stringify([{:char, attr, value} | tokens]),
    do: char_stringify([{:string, attr, <<value::utf8>>} | tokens])

  defp char_stringify([{:string, attr, value1}, {:char, _attr, value2} | tokens]),
    do: char_stringify([{:string, attr, <<value1::binary, value2::utf8>>} | tokens])

  defp char_stringify([token | tokens]),
    do: [token | char_stringify(tokens)]

  defp char_stringify([]), do: []

  ###
  # Converts the proper keywords into attributes
  ###
  defp attributify(tokens),
    do: tokens |> attributify(false, [])

  # when using the HTMLLexer from HEEx, we often have to deal with
  # strings like <div class=>...</div> where an attribute starts, but is missing
  # a value. We special case this "missing attribute value" case here to avoid
  # formatting the closing tag as an attribute.
  defp attributify(
         [
           {:keyword, attr, value},
           {:operator, _, _} = operator,
           {:punctuation, attr2, value2} | tokens
         ],
         _flag,
         result
       ) do
    attributify(
      tokens,
      false,
      result ++ [{:name_attribute, attr, value}, operator, {:punctuation, attr2, value2}]
    )
  end

  defp attributify(
         [
           {:keyword, attr, value},
           {:operator, _, _} = operator,
           {_, attr2, value2} | tokens
         ],
         flag,
         result
       ) do
    attributify(
      tokens,
      flag,
      result ++ [{:name_attribute, attr, value}, operator, {:string, attr2, value2}]
    )
  end

  defp attributify(
         [
           {:punctuation, _, "<"} = punctuation,
           {:name_tag, _, _} = name_tag,
           {:whitespace, _, _} = whitespace | tokens
         ],
         _,
         result
       ) do
    attributify(tokens, true, result ++ [punctuation, name_tag, whitespace])
  end

  defp attributify([{:punctuation, _, ">"} = punctuation | tokens], true, result),
    do: attributify(tokens, false, result ++ [punctuation])

  defp attributify([{:punctuation, _, "/>"} = punctuation | tokens], true, result),
    do: attributify(tokens, false, result ++ [punctuation])

  defp attributify([{:keyword, attr, value} | tokens], true, result),
    do: attributify(tokens, true, result ++ [{:name_attribute, attr, value}])

  defp attributify([{:keyword, attr, value} | tokens], flag, result) do
    attribute =
      if Enum.member?(@attributes, value),
        do: {:name_attribute, attr, value},
        else: {:string, attr, value}

    attributify(tokens, flag, result ++ [attribute])
  end

  defp attributify([token | tokens], flag, result),
    do: attributify(tokens, flag, result ++ [token])

  defp attributify([], _, result), do: result

  ###
  # Converts traces of the forms
  # string[keyword]+
  # keyword[keyword]+
  # [keyword]+string
  # into a single string
  ###
  defp keyword_stringify(tokens), do: tokens |> keyword_stringify([], [])

  defp keyword_stringify(
         [{:string, _, _} = string, {:keyword, _, _} = keyword | tokens],
         queue,
         result
       ),
       do: keyword_stringify(tokens, queue ++ [string, keyword], result)

  defp keyword_stringify(
         [{:keyword, _, _} = keyword, {:string, _, _} = string | tokens],
         queue,
         result
       ),
       do: keyword_stringify(tokens, queue ++ [keyword, string], result)

  defp keyword_stringify(
         [{:keyword, _, _} = keyword1, {:keyword, _, _} = keyword2 | tokens],
         queue,
         result
       ),
       do: keyword_stringify(tokens, queue ++ [keyword1, keyword2], result)

  defp keyword_stringify([{:keyword, _, _} = token | tokens], [], result),
    do: keyword_stringify(tokens, [], result ++ [token])

  defp keyword_stringify([{:keyword, _, _} = token | tokens], queue, result),
    do: keyword_stringify(tokens, queue ++ [token], result)

  defp keyword_stringify([], queue, result),
    do: result ++ merge_string(queue)

  defp keyword_stringify([{:string, _, _} = token | tokens], queue, result),
    do: keyword_stringify(tokens, [], result ++ merge_string(queue ++ [token]))

  defp keyword_stringify([token | tokens], queue, result),
    do: keyword_stringify(tokens, [], result ++ merge_string(queue) ++ [token])

  ##
  # Converts the content of an element into a string
  ##
  defp element_stringify(tokens), do: tokens |> element_stringify(false, [], [])

  defp element_stringify(
         [{:punctuation, _, ">"} = punctuation | tokens],
         _,
         queue,
         result
       ),
       do: element_stringify(tokens, true, [], result ++ merge_string(queue) ++ [punctuation])

  # We respect the comments
  defp element_stringify(
         [{:comment, _, _} = comment | tokens],
         _,
         queue,
         result
       ),
       do: element_stringify(tokens, true, [], result ++ merge_string(queue) ++ [comment])

  defp element_stringify(
         [{:punctuation, _, "</"} = punctuation | tokens],
         true,
         queue,
         result
       ),
       do: element_stringify(tokens, false, [], result ++ merge_string(queue) ++ [punctuation])

  defp element_stringify(
         [{:punctuation, _, "<"} = punctuation | tokens],
         true,
         queue,
         result
       ),
       do: element_stringify(tokens, false, [], result ++ merge_string(queue) ++ [punctuation])

  defp element_stringify([token | tokens], false, _, result),
    do: element_stringify(tokens, false, [], result ++ [token])

  defp element_stringify([token | tokens], true, queue, result),
    do: element_stringify(tokens, true, queue ++ [token], result)

  defp element_stringify([], _, queue, result),
    do: result ++ queue

  @impl Makeup.Lexer
  def postprocess(tokens, _opts \\ []) do
    tokens
    |> char_stringify()
    |> keyword_stringify()
    |> attributify()
    |> element_stringify()
  end

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
