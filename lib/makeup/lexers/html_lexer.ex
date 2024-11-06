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

  @keywords (HTMLElements.get_elements() ++
               HTMLAttributes.get_attributes() ++ HTMLAttributes.get_event_handler_attributes())
            |> Enum.sort_by(&String.length/1)
            |> Enum.reverse()

  @attributes (HTMLAttributes.get_attributes() ++ HTMLAttributes.get_event_handler_attributes())
              |> MapSet.new()
              |> MapSet.difference(MapSet.new(HTMLElements.get_elements()))
              |> MapSet.to_list()

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
    |> token(:keyword)

  # Operators
  operators =
    "="
    |> string()
    |> token(:operator)

  # Combinators that highlight expressions surrounded by a pair of delimiters.
  comment_tag = many_surrounded_by(parsec(:root_element), "<!--", "-->", eos: false)

  # Single punctuation symbols
  open_tag =
    "<"
    |> string()
    |> token(:punctuation)

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

  # Keywords
  keywords =
    Enum.map(
      @keywords,
      &keyword/1
    )

  # Unmatched
  insensitive_char = utf8_char([]) |> token(:char)

  # Tag the tokens with the language name.
  # This makes it easier to postprocess files with multiple languages.
  @doc false
  def __as_html_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :html), value}
  end

  root_element_combinator =
    choice(
      [
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
        # Whitespaces
        whitespace
      ] ++
        keywords ++
        [
          # Unmatched
          insensitive_char
        ]
    )

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
  defp char_stringify(tokens), do: tokens |> char_stringify([], [])

  defp char_stringify([{:char, _attr, _value} = token | tokens], charlist, result),
    do: char_stringify(tokens, charlist ++ [token], result)

  defp char_stringify([token | tokens], charlist, result),
    do: char_stringify(tokens, [], result ++ merge_string(charlist) ++ [token])

  defp char_stringify([], charlist, result), do: result ++ merge_string(charlist)

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
       ),
       do:
         attributify(
           tokens,
           false,
           result ++ [{:name_attribute, attr, value}, operator, {:punctuation, attr2, value2}]
         )

  defp attributify(
         [
           {:keyword, attr, value},
           {:operator, _, _} = operator,
           {_, attr2, value2} | tokens
         ],
         flag,
         result
       ),
       do:
         attributify(
           tokens,
           flag,
           result ++ [{:name_attribute, attr, value}, operator, {:string, attr2, value2}]
         )

  defp attributify(
         [
           {:punctuation, _, "<"} = punctuation,
           {:keyword, _, _} = keyword,
           {:whitespace, _, _} = whitespace | tokens
         ],
         _,
         result
       ),
       do:
         attributify(
           tokens,
           true,
           result ++
             [punctuation, keyword, whitespace]
         )

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
        else: {:keyword, attr, value}

    attributify(
      tokens,
      flag,
      result ++
        [attribute]
    )
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

  ###
  # Converts traces of the form "<!--"[token]*"-->" into a comment
  ###
  defp commentify(tokens), do: tokens |> commentify({nil, []}, [])

  defp commentify([{:punctuation, group, "<!--"} = token | tokens], {nil, []}, result),
    do: commentify(tokens, {group, [token]}, result)

  defp commentify([{:punctuation, group, "-->"} = token | tokens], {group, queue}, result) do
    [{_type, _attr, string}] = merge_string(queue ++ [token])

    comment_content =
      string
      |> List.to_string()
      |> String.replace_prefix("<!--", "")
      |> String.replace_suffix("-->", "")

    if String.starts_with?(comment_content, [">", "->"]) or
         String.contains?(comment_content, ["<!--", "-->", "--!>"]) or
         String.ends_with?(comment_content, "<!-"),
       do:
         commentify(
           tokens,
           {nil, []},
           result ++ [{:string, %{language: :html}, string}]
         ),
       else:
         commentify(
           tokens,
           {nil, []},
           result ++ [{:comment, %{language: :html}, string}]
         )
  end

  defp commentify([], {_group, queue}, result),
    do: result ++ merge_string(queue)

  defp commentify([token | tokens], {nil, _}, result),
    do: commentify(tokens, {nil, []}, result ++ [token])

  defp commentify([token | tokens], {group, queue}, result),
    do: commentify(tokens, {group, queue ++ [token]}, result)

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
    |> commentify()
    |> keyword_stringify()
    |> attributify()
    |> element_stringify()
  end

  #######################################################################
  # Step #3: highlight matching delimiters
  #######################################################################
  @impl Makeup.Lexer
  defgroupmatcher(:match_groups,
    comment_tag: [
      open: [[{:punctuation, _, "<!--"}]],
      close: [[{:punctuation, _, "-->"}]]
    ],
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
