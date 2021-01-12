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

  insensitive_char = utf8_char([]) |> token(:char)

  keywords = Enum.map(@keywords, &keyword/1)

  doctype =
    "<!"
    |> string()
    |> concat(anycase_string("DOCTYPE"))
    |> optional(wspace)
    |> concat(anycase_string("html"))
    # TODO: optional doctype legacy string
    |> optional(wspace)
    |> concat(string(">"))
    |> token(:keyword)

  # Combinators that highlight expressions surrounded by a pair of delimiters.
  start_tag = many_surrounded_by(parsec(:root_element), "<", ">")
  end_tag = many_surrounded_by(parsec(:root_element), "</", ">")
  single_tag = many_surrounded_by(parsec(:root_element), "<", "/>")
  comment_tag = many_surrounded_by(parsec(:root_element), "<!--", "-->")
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
        # Delimiters
        comment_tag,
        # Unmatched
        insensitive_char
      ] ++
        keywords
    )

  ##############################################################################
  # Semi-public API: these two functions can be used by someone who wants to
  # embed this lexer into another lexer, but other than that, they are not
  # meant to be used by end-users
  ##############################################################################

  @inline Application.get_env(:makeup_html, :inline, false)

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
  defp merge_string_helper([{_, _, string} | tokens], result) when is_list(string),
    do: merge_string_helper(tokens, result ++ string)

  defp merge_string_helper([{_, _, string} | tokens], result) when is_binary(string),
    do: merge_string_helper(tokens, result ++ [string])

  defp merge_string_helper([{_, _, string} | tokens], result) when is_integer(string),
    do: merge_string_helper(tokens, result ++ [string])

  defp merge_string_helper([], []), do: []
  defp merge_string_helper([], result), do: [{:string, %{language: :html}, result}]

  defp merge_string(stringlist), do: stringlist |> merge_string_helper([])

  defp stringify_helper([{:char, _attr, _value} = token | tokens], charlist, result),
    do: stringify_helper(tokens, charlist ++ [token], result)

  defp stringify_helper([token | tokens], charlist, result),
    do: stringify_helper(tokens, [], result ++ merge_string(charlist) ++ [token])

  defp stringify_helper([], charlist, result), do: result ++ merge_string(charlist)

  # commentify_helper(tokens, {group, queue}, result)
  defp commentify_helper([{:punctuation, group, "<!--"} = token | tokens], {nil, []}, result),
    do: commentify_helper(tokens, {group, [token]}, result)

  defp commentify_helper([{:punctuation, group, "-->"} = token | tokens], {group, queue}, result) do
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
         commentify_helper(
           tokens,
           {nil, []},
           result ++ [{:string, %{language: :html}, string}]
         ),
       else:
         commentify_helper(
           tokens,
           {nil, []},
           result ++ [{:comment, %{language: :html}, string}]
         )
  end

  defp commentify_helper([token | tokens], {nil, _}, result),
    do: commentify_helper(tokens, {nil, []}, result ++ [token])

  defp commentify_helper([token | tokens], {group, queue}, result),
    do: commentify_helper(tokens, {group, queue ++ [token]}, result)

  defp commentify_helper([], {_group, []}, result), do: result

  defp commentify_helper([], {_group, queue}, result),
    do: result ++ [{:string, %{language: :html}, merge_string(queue)}]

  # Converts traces of the form "char"+ into a single string
  defp stringify(tokens), do: tokens |> stringify_helper([], [])

  # Convert traces of the form "<!--"-string-"-->" into a comment
  defp commentify(tokens), do: tokens |> commentify_helper({nil, []}, [])

  @impl Makeup.Lexer
  def postprocess(tokens, _opts \\ []), do: tokens |> stringify() |> commentify()

  #######################################################################
  # Step #3: highlight matching delimiters
  # By default, this includes delimiters that are used in many languages,
  # but feel free to delete these or add more.
  #######################################################################

  @impl Makeup.Lexer
  defgroupmatcher(:match_groups,
    single_tag: [
      open: [[{:punctuation, _, "<"}]],
      close: [[{:punctuation, _, "/>"}]]
    ],
    comment_tag: [
      open: [[{:punctuation, _, "<!--"}]],
      close: [[{:punctuation, _, "-->"}]]
    ],
    attribute_delimiters: [
      open: [[{:punctuation, _, "\""}]],
      close: [[{:punctuation, _, "\""}]]
    ],
    start_tag: [
      open: [[{:punctuation, _, "<"}]],
      close: [[{:punctuation, _, ">"}]]
    ],
    end_tag: [
      open: [[{:punctuation, _, "</"}]],
      close: [[{:punctuation, _, ">"}]]
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
