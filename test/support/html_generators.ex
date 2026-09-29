defmodule HTMLGenerators do
  @moduledoc false
  use ExUnitProperties

  def tag_name do
    gen all(
          first <- string([?a..?z], length: 1),
          rest <- string([?a..?z, ?0..?9, ?-], max_length: 5)
        ) do
      first <> rest
    end
  end

  def attribute_name do
    string([?a..?z, ?A..?Z, ?0..?9, ?-, ?_, ?:, ?@, ?., ?#], min_length: 1, max_length: 8)
  end

  def attribute do
    gen all(
          name <- attribute_name(),
          quotation <- member_of(["\"", "'", ""]),
          value <- string(:alphanumeric, max_length: 6),
          valued? <- boolean()
        ) do
      if valued?, do: name <> "=" <> quotation <> value <> quotation, else: name
    end
  end

  def attributes do
    gen all(attributes <- list_of(attribute(), max_length: 3)) do
      Enum.map_join(attributes, &(" " <> &1))
    end
  end

  def start_tag do
    gen all(
          name <- tag_name(),
          attributes <- attributes(),
          closing <- member_of([">", "/>"])
        ) do
      "<" <> name <> attributes <> closing
    end
  end

  def end_tag do
    gen all(name <- tag_name()) do
      "</" <> name <> ">"
    end
  end

  def comment do
    gen all(body <- string([?a..?z, ?\s, ?<, ?>, ?!], max_length: 12)) do
      "<!--" <> body <> "-->"
    end
  end

  def cdata do
    gen all(body <- string([?a..?z, ?\s, ?<, ?>], max_length: 12)) do
      "<![CDATA[" <> body <> "]]>"
    end
  end

  def doctype do
    gen all(
          keyword <- member_of(["DOCTYPE", "doctype", "DocType"]),
          rest <- string([?a..?z, ?\s], max_length: 8)
        ) do
      "<!" <> keyword <> " " <> rest <> ">"
    end
  end

  def processing_instruction do
    gen all(body <- string([?a..?z, ?\s, ?=, ?"], max_length: 10)) do
      "<?" <> body <> ">"
    end
  end

  def entity do
    gen all(
          reference <-
            one_of([
              string([?a..?z], min_length: 2, max_length: 5),
              map(string([?0..?9], min_length: 1, max_length: 4), &("#" <> &1))
            ])
        ) do
      "&" <> reference <> ";"
    end
  end

  def raw_element do
    gen all(
          name <- member_of(["script", "style"]),
          body <- string([?a..?z, ?<, ?>, ?=, ?\s], max_length: 14)
        ) do
      "<" <> name <> ">" <> body <> "</" <> name <> ">"
    end
  end

  def text do
    string([?a..?z, ?A..?Z, ?0..?9, ?\s, ?\n, ?&, ?>, ?., ?é, ?€], max_length: 12)
  end

  def truncated(generator) do
    map(generator, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))
  end

  def fragment do
    one_of([
      start_tag(),
      end_tag(),
      comment(),
      cdata(),
      doctype(),
      processing_instruction(),
      entity(),
      raw_element(),
      text(),
      truncated(start_tag()),
      truncated(comment()),
      truncated(cdata()),
      truncated(raw_element())
    ])
  end

  def document do
    gen all(fragments <- list_of(fragment(), max_length: 12)) do
      Enum.join(fragments)
    end
  end
end
