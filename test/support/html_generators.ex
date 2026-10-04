defmodule HTMLGenerators do
  @moduledoc false
  use ExUnitProperties

  def tag_name do
    one_of([
      gen all(
            first <- string([?a..?z, ?A..?Z, ?., ?:], length: 1),
            rest <- string([?a..?z, ?A..?Z, ?0..?9, ?-, ?_, ?:, ?.], max_length: 5)
          ) do
        first <> rest
      end,
      member_of(["div", "DIV", "svg:rect", ".input", ":inner_block", "my-element", "_x"])
    ])
  end

  def attribute_name do
    string([?a..?z, ?A..?Z, ?0..?9, ?-, ?_, ?:, ?@, ?., ?#, ?<, ?{, ?}],
      min_length: 1,
      max_length: 8
    )
  end

  def attribute do
    gen all(
          name <- attribute_name(),
          quotation <- member_of(["\"", "'", ""]),
          value <- string(:alphanumeric, max_length: 6),
          before_equals <- member_of(["", " "]),
          after_equals <- member_of(["", " "]),
          valued? <- boolean()
        ) do
      if valued?,
        do: name <> before_equals <> "=" <> after_equals <> quotation <> value <> quotation,
        else: name
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
    gen all(
          name <- tag_name(),
          extra <- member_of(["", " ", " extra", " a=b"])
        ) do
      "</" <> name <> extra <> ">"
    end
  end

  def comment do
    gen all(
          body <- string([?a..?z, ?\s, ?<, ?>, ?!, ?-], max_length: 12),
          closing <- member_of(["-->", "--!>"])
        ) do
      "<!--" <> body <> closing
    end
  end

  def empty_comment do
    member_of(["<!-->", "<!--->", "<!---->"])
  end

  def cdata do
    gen all(
          opening <- member_of(["<![CDATA[", "<![cdata["]),
          body <- string([?a..?z, ?\s, ?<, ?>, ?]], max_length: 12)
        ) do
      opening <> body <> "]]>"
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

  def bogus_comment do
    gen all(
          opening <- member_of(["<!", "<?"]),
          body <- string([?a..?z, ?\s, ?!, ?[, ?], ?", ?=], max_length: 10)
        ) do
      opening <> body <> ">"
    end
  end

  def character_reference do
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
          name <- member_of(["script", "style", "SCRIPT", "Style"]),
          attributes <- attributes(),
          body <- string([?a..?z, ?<, ?>, ?=, ?/, ?!, ?\s], max_length: 14)
        ) do
      "<" <> name <> attributes <> ">" <> body <> "</" <> name <> ">"
    end
  end

  def text do
    string([?a..?z, ?A..?Z, ?0..?9, ?\s, ?\n, ?&, ?<, ?>, ?., ?-, ?!, ?é, ?€], max_length: 12)
  end

  # Drops the last character, so `<!-- hi -->` becomes `<!-- hi --`.
  def truncated(generator) do
    map(generator, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))
  end

  def fragment do
    one_of([
      start_tag(),
      end_tag(),
      comment(),
      empty_comment(),
      cdata(),
      doctype(),
      bogus_comment(),
      character_reference(),
      raw_element(),
      text(),
      truncated(start_tag()),
      truncated(end_tag()),
      truncated(comment()),
      truncated(cdata()),
      truncated(doctype()),
      truncated(raw_element())
    ])
  end

  def document do
    gen all(fragments <- list_of(fragment(), max_length: 12)) do
      Enum.join(fragments)
    end
  end
end
