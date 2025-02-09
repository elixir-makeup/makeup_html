defmodule HTMLGenerators do
  @moduledoc false
  use ExUnitProperties

  alias Makeup.Lexers.HTMLLexer.Combinators

  @attributes Combinators.get_attributes() ++ Combinators.get_event_handler_attributes()

  defp get_attributes do
    @attributes
  end

  defp get_elements do
    [
      "a",
      "abbr",
      "address",
      "area",
      "article",
      "aside",
      "audio",
      "b",
      "base",
      "bdi",
      "bdo",
      "blockquote",
      "body",
      "br",
      "button",
      "canvas",
      "caption",
      "cite",
      "code",
      "col",
      "colgroup",
      "data",
      "datalist",
      "dd",
      "del",
      "details",
      "dfn",
      "dialog",
      "div",
      "dl",
      "dt",
      "em",
      "embed",
      "fieldset",
      "figcaption",
      "figure",
      "footer",
      "form",
      "h1",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "head",
      "header",
      "hgroup",
      "hr",
      "html",
      "i",
      "iframe",
      "img",
      "input",
      "ins",
      "kbd",
      "label",
      "legend",
      "li",
      "link",
      "main",
      "map",
      "mark",
      "math",
      "menu",
      "meta",
      "meter",
      "nav",
      "noscript",
      "object",
      "ol",
      "optgroup",
      "option",
      "output",
      "p",
      "param",
      "picture",
      "pre",
      "progress",
      "q",
      "rp",
      "rt",
      "ruby",
      "s",
      "samp",
      "script",
      "section",
      "select",
      "slot",
      "small",
      "source",
      "span",
      "strong",
      "style",
      "sub",
      "summary",
      "sup",
      "svg",
      "table",
      "tbody",
      "td",
      "template",
      "textarea",
      "tfoot",
      "th",
      "thead",
      "time",
      "title",
      "tr",
      "track",
      "u",
      "ul",
      "var",
      "video",
      "wbr"
    ]
  end

  defp insensitive_case_string(string) do
    string
    |> String.split("", trim: true)
    |> insensitive_case_string([])
    |> Enum.join("")
  end

  defp insensitive_case_string([], result), do: result

  defp insensitive_case_string([h | t], result) do
    insensitive_case_string(t, result ++ [insensitive_fun(Enum.random(0..1), h)])
  end

  defp insensitive_fun(0, string), do: String.downcase(string)
  defp insensitive_fun(1, string), do: String.upcase(string)

  ## Generators

  def doctype_legacy_string do
    ExUnitProperties.gen all(
                           one_or_more <- StreamData.integer(1..5),
                           quotation <- StreamData.member_of(["\"", "\'"])
                         ) do
      String.duplicate(" ", one_or_more) <>
        insensitive_case_string("SYSTEM") <>
        String.duplicate(" ", one_or_more) <> quotation <> "about:legacy-compat" <> quotation
    end
  end

  def doctype do
    ExUnitProperties.gen all(
                           one_or_more <- StreamData.integer(1..5),
                           optional <- StreamData.integer(0..5),
                           legacy_string <- doctype_legacy_string()
                         ) do
      "<!" <>
        insensitive_case_string("DOCTYPE") <>
        String.duplicate(" ", one_or_more) <>
        insensitive_case_string("html") <>
        legacy_string <>
        String.duplicate(" ", optional) <> ">"
    end
  end

  def comment do
    ExUnitProperties.gen all(gen_text <- StreamData.string(:ascii)) do
      text =
        gen_text
        |> String.replace_leading(">", "")
        |> String.replace_leading("->", "")
        |> String.replace("<!--", "")
        |> String.replace("-->", "")
        |> String.replace("--!>", "")
        |> String.replace_trailing("<!-", "")

      "<!--" <> text <> "-->"
    end
  end

  def void_element do
    ExUnitProperties.gen all(element <- StreamData.member_of(get_elements())) do
      "<" <> element <> ">"
    end
  end

  def attribute do
    ExUnitProperties.gen all(
                           quotation <- StreamData.member_of(["\"", "\'", ""]),
                           name <- StreamData.member_of(get_attributes()),
                           value <- StreamData.string(:alphanumeric),
                           value not in get_attributes()
                         ) do
      if String.length(value) != 0,
        do: name <> "=" <> quotation <> value <> quotation,
        else: name
    end
  end

  def element_attribute do
    ExUnitProperties.gen all(
                           quotation <- StreamData.member_of(["\"", "\'", ""]),
                           name <- StreamData.member_of(get_attributes()),
                           value <- StreamData.string(:alphanumeric),
                           value not in get_attributes()
                         ) do
      if String.length(value) != 0,
        do: name <> "=" <> quotation <> value <> quotation,
        else: name
    end
  end

  def single_element do
    ExUnitProperties.gen all(
                           element_name <- StreamData.member_of(get_elements()),
                           content <- StreamData.string(:ascii),
                           attributes <- StreamData.list_of(element_attribute(), max_length: 3),
                           attributes_string <-
                             StreamData.constant(" " <> Enum.join(attributes, " ")),
                           element <-
                             StreamData.member_of([
                               "<" <>
                                 element_name <>
                                 attributes_string <>
                                 ">" <>
                                 (content
                                  |> String.replace("<", "")
                                  # TODO: Element content can contain ">"
                                  |> String.replace(">", "")) <>
                                 "</" <> element_name <> ">",
                               "<" <> element_name <> attributes_string <> "/>",
                               "<" <> element_name <> attributes_string <> ">"
                             ])
                         ) do
      element
    end
  end

  def nested_element do
    ExUnitProperties.gen all(
                           element_name <- StreamData.member_of(get_elements()),
                           content <- StreamData.one_of([void_element(), single_element()]),
                           attributes <- StreamData.list_of(element_attribute(), max_length: 3)
                         ) do
      "<" <>
        element_name <>
        " " <>
        Enum.join(attributes, " ") <>
        ">" <> content <> "</" <> element_name <> ">"
    end
  end

  def element do
    ExUnitProperties.gen all(
                           element <-
                             StreamData.one_of([
                               void_element(),
                               single_element(),
                               nested_element()
                             ])
                         ) do
      element
    end
  end

  def document do
    ExUnitProperties.gen all(
                           bom <- StreamData.member_of([:unicode.encoding_to_bom(:utf8), ""]),
                           any_comments <- StreamData.list_of(comment(), max_length: 3),
                           doctype <- doctype(),
                           document_content <- StreamData.list_of(element(), max_length: 3)
                         ) do
      comments = Enum.join(any_comments, "\n")
      document = "<html>\n" <> Enum.join(document_content, "\n") <> "\n</html>"

      bom <>
        comments <> "\n" <> doctype <> "\n" <> comments <> "\n" <> document <> "\n" <> comments
    end
  end

  ###################################################################
  # Incorrect
  ###################################################################

  def incorrect_doctype do
    ExUnitProperties.gen all(doctype <- doctype()) do
      doctype
      |> String.replace_suffix(">", "")
    end
  end

  def incorrect_void_element do
    ExUnitProperties.gen all(void_element <- void_element()) do
      void_element
      |> String.replace_suffix(">", "")
    end
  end

  def incorrect_single_element do
    ExUnitProperties.gen all(single_element <- single_element()) do
      single_element
      |> String.replace_suffix(">", "")
    end
  end

  def incorrect_nested_element do
    ExUnitProperties.gen all(nested_element <- nested_element()) do
      nested_element
      |> String.replace_suffix(">", "")
    end
  end

  def incorrect_element do
    ExUnitProperties.gen all(
                           incorrect_element <-
                             StreamData.one_of([
                               incorrect_void_element(),
                               incorrect_single_element(),
                               incorrect_nested_element()
                             ])
                         ) do
      incorrect_element
    end
  end

  def incorrect_document do
    ExUnitProperties.gen all(document <- document()) do
      document
      |> String.replace("<", "")
    end
  end
end
