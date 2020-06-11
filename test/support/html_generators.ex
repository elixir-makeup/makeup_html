defmodule HTMLGenerators do
  use ExUnitProperties

  def doctype do
    ExUnitProperties.gen all(
                           one_or_more <- StreamData.integer(1..5),
                           optional <- StreamData.integer(0..5)
                         ) do
      "<!" <>
        insensitive_case_string("DOCTYPE") <>
        String.duplicate(" ", one_or_more) <>
        insensitive_case_string("html") <> String.duplicate(" ", optional) <> ">"
    end
  end

  def comment do
    ExUnitProperties.gen all(
                           text <- StreamData.string(:alphanumeric),
                           !String.starts_with?(text, ["<", "->"]),
                           !String.contains?(text, ["<!--", "-->", "--!>"]),
                           !String.ends_with?(text, "<!-")
                         ) do
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
                           name <-
                             StreamData.member_of(
                               HTMLAttributes.get_attributes() ++
                                 HTMLAttributes.get_event_handler_attributes()
                             ),
                           value <- StreamData.string(:alphanumeric)
                         ) do
      if String.length(value) != 0,
        do: name <> "=" <> quotation <> value <> quotation,
        else: name
    end
  end

  def single_element do
    ExUnitProperties.gen all(
                           element_name <- StreamData.member_of(HTMLElements.get_elements()),
                           content <- StreamData.string(:alphanumeric),
                           attributes <- StreamData.list_of(attribute()),
                           attributes_string <-
                             StreamData.constant(" " <> Enum.join(attributes, " ")),
                           element <-
                             StreamData.member_of([
                               "<" <>
                                 element_name <>
                                 attributes_string <>
                                 ">" <> content <> "</" <> element_name <> ">",
                               "<" <> element_name <> attributes_string <> "/>"
                             ])
                         ) do
      element
    end
  end

  def nested_element do
    ExUnitProperties.gen all(
                           element_name <- StreamData.member_of(HTMLElements.get_elements()),
                           content <- single_element(),
                           attributes <- StreamData.list_of(attribute())
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

  defp insensitive_case_string(string) do
    string
    |> String.split("", trim: true)
    |> aux_insensitive_case_string([])
    |> Enum.join("")
  end

  defp aux_insensitive_case_string([], result), do: result

  defp aux_insensitive_case_string([h | t], result) do
    aux_insensitive_case_string(t, result ++ [aux_insensitive_fun(Enum.random(0..1), h)])
  end

  defp aux_insensitive_fun(0, string), do: String.downcase(string)
  defp aux_insensitive_fun(1, string), do: String.upcase(string)
end
