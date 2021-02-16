defmodule HTMLGenerators do
  @moduledoc false
  use ExUnitProperties

  alias Makeup.Lexers.HTMLLexer.HTMLElements
  alias Makeup.Lexers.HTMLLexer.HTMLAttributes
  alias Helper

  @keywords HTMLElements.get_elements() ++
              HTMLAttributes.get_attributes() ++ HTMLAttributes.get_event_handler_attributes()

  def doctype_legacy_string do
    ExUnitProperties.gen all(
                           one_or_more <- StreamData.integer(1..5),
                           quotation <- StreamData.member_of(["\"", "\'"])
                         ) do
      String.duplicate(" ", one_or_more) <>
        Helper.insensitive_case_string("SYSTEM") <>
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
        Helper.insensitive_case_string("DOCTYPE") <>
        String.duplicate(" ", one_or_more) <>
        Helper.insensitive_case_string("html") <>
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
    ExUnitProperties.gen all(element <- StreamData.member_of(HTMLElements.get_elements())) do
      "<" <> element <> ">"
    end
  end

  def attribute do
    ExUnitProperties.gen all(
                           quotation <- StreamData.member_of(["\"", "\'", ""]),
                           single_name <-
                             StreamData.member_of(
                               (HTMLAttributes.get_attributes() ++
                                  HTMLAttributes.get_event_handler_attributes())
                               |> MapSet.new()
                               |> MapSet.difference(MapSet.new(HTMLElements.get_elements()))
                               |> MapSet.to_list()
                             ),
                           name <-
                             StreamData.member_of(
                               HTMLAttributes.get_attributes() ++
                                 HTMLAttributes.get_event_handler_attributes()
                             ),
                           value <- StreamData.string(:alphanumeric),
                           !Enum.any?(@keywords, &(&1 == value))
                         ) do
      if String.length(value) != 0,
        do: name <> "=" <> quotation <> value <> quotation,
        else: single_name
    end
  end

  def element_attribute do
    ExUnitProperties.gen all(
                           quotation <- StreamData.member_of(["\"", "\'", ""]),
                           name <-
                             StreamData.member_of(
                               HTMLAttributes.get_attributes() ++
                                 HTMLAttributes.get_event_handler_attributes()
                             ),
                           value <- StreamData.string(:alphanumeric),
                           !Enum.any?(@keywords, &(&1 == value))
                         ) do
      if String.length(value) != 0,
        do: name <> "=" <> quotation <> value <> quotation,
        else: name
    end
  end

  def single_element do
    ExUnitProperties.gen all(
                           element_name <- StreamData.member_of(HTMLElements.get_elements()),
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
                           element_name <- StreamData.member_of(HTMLElements.get_elements()),
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

  def incorrect_comment do
    ExUnitProperties.gen all(
                           text <- StreamData.string(:ascii),
                           start_text <- StreamData.member_of([">", "->", ""]),
                           contain_text <- StreamData.member_of(["<!--", "-->", "--!>", ""]),
                           end_text <- StreamData.member_of(["<!-", ""]),
                           !Enum.all?([start_text, contain_text, end_text], &(&1 == ""))
                         ) do
      "<!--" <> start_text <> text <> contain_text <> end_text <> "-->"
    end
  end

  def incorrect_void_element do
    ExUnitProperties.gen all(void_element <- void_element()) do
      void_element
      |> String.replace_suffix(">", "")
    end
  end

  def incorrect_attribute do
    ExUnitProperties.gen all(attribute <- element_attribute()) do
      attribute
      |> String.slice(0..0)
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
