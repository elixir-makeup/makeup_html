defmodule HTMLLexerTokenizer do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Makeup.Lexers.HTMLLexer
  alias Makeup.Lexer.Postprocess
  alias Helper
  alias Makeup.Lexers.HTMLLexer.HTMLElements

  # This function has three purposes:
  # 1. Ensure deterministic lexer output (no random prefix)
  # 2. Convert the token values into binaries so that the output
  #    is more obvious on visual inspection
  #    (iolists are hard to parse by a human)
  # 3. remove language metadata
  def lex(text) do
    text
    |> HTMLLexer.lex(group_prefix: "group")
    |> Postprocess.token_values_to_binaries()
    |> Enum.map(fn {ttype, meta, value} -> {ttype, Map.delete(meta, :language), value} end)
  end

  # This function receives an element and returns a tuple of the form:
  # {element_token, [attribute_token]}
  def tokenize_elements(element) do
    [element_name | attributes] =
      element
      |> String.split(" ")

    attributes_tokens =
      attributes
      |> Enum.flat_map(fn attr ->
        [name | value] =
          attr
          |> String.split("=")

        cond do
          value != [] ->
            [
              {:whitespace, %{}, " "},
              {:name_attribute, %{}, name},
              {:operator, %{}, "="},
              {:string, %{}, hd(value)}
            ]

          String.length(name) == 0 ->
            [
              {:whitespace, %{}, " "}
            ]

          true ->
            [
              {:whitespace, %{}, " "},
              {:name_attribute, %{}, name}
            ]
        end
      end)

    {{:keyword, %{}, element_name}, attributes_tokens}
  end

  ###################################################################
  # Empty string
  ###################################################################
  test "empty string" do
    assert lex("") == []
  end

  ###################################################################
  # Doctype
  ###################################################################
  property "correct DOCTYPE does not produce errors" do
    check all(doctype <- HTMLGenerators.doctype()) do
      assert !Enum.any?(lex(doctype), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect DOCTYPE produces errors" do
    check all(doctype <- HTMLGenerators.incorrect_doctype()) do
      assert Enum.any?(lex(doctype), &match?({:error, _, _}, &1))
    end
  end

  property "correct DOCTYPE is correctly tokenized" do
    Enum.each(0..99, fn _ ->
      doctype = Helper.insensitive_case_string("doctype")
      html = Helper.insensitive_case_string("html")

      assert lex("<!" <> doctype <> "  " <> html <> " >") == [
               {:keyword, %{}, "<!" <> doctype <> "  " <> html <> " >"}
             ]
    end)
  end

  test "<!DOCTYPE html>" do
    doctype = "<!DOCTYPE html>"

    assert lex(doctype) == [
             {:keyword, %{}, "<!DOCTYPE html>"}
           ]
  end

  ###################################################################
  # Comment
  ###################################################################
  property "correct comment does not produce errors" do
    check all(comment <- HTMLGenerators.comment()) do
      assert !Enum.any?(lex(comment), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect comment produces errors" do
    check all(comment <- HTMLGenerators.incorrect_comment()) do
      assert Enum.any?(lex(comment), &match?({:error, _, _}, &1))
    end
  end

  property "correct comment is correctly tokenized" do
    check all(comment <- HTMLGenerators.comment()) do
      assert lex(comment) == [
               {:comment, %{}, comment}
             ]
    end
  end

  test "<!--My favorite operators are > and <!-->" do
    comment = "<!--My favorite operators are > and <!-->"

    assert lex(comment) == [
             {:comment, %{}, "<!--My favorite operators are > and <!-->"}
           ]
  end

  ###################################################################
  # Void element
  ###################################################################
  property "correct void_element does not produce errors" do
    check all(void_element <- HTMLGenerators.void_element()) do
      assert !Enum.any?(lex(void_element), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect void_element produces_errors" do
    check all(void_element <- HTMLGenerators.incorrect_void_element()) do
      assert Enum.any?(lex(void_element), &match?({:error, _, _}, &1))
    end
  end

  property "correct void_element is correctly tokenized" do
    check all(element <- StreamData.member_of(HTMLElements.get_elements())) do
      void_element = "<" <> element <> " >"

      assert lex(void_element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:keyword, %{}, element},
               {:whitespace, %{}, " "},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end
  end

  test "<hr>" do
    void_element = "<hr>"

    assert lex(void_element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "hr"},
             {:punctuation, %{group_id: "group-1"}, ">"}
           ]
  end

  ###################################################################
  # Attribute
  ###################################################################
  property "correct attribute does not produce errors" do
    check all(attribute <- HTMLGenerators.attribute()) do
      assert !Enum.any?(lex(attribute), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect attribute produces errors" do
    check all(attribute <- HTMLGenerators.incorrect_attribute()) do
      assert Enum.any?(lex(attribute), &match?({:error, _, _}, &1))
    end
  end

  property "correct attribute is correctly tokenized" do
    check all(attribute <- HTMLGenerators.attribute()) do
      [name | value] =
        attribute
        |> String.split("=")

      if value != [] do
        assert lex(attribute) == [
                 {:name_attribute, %{}, name},
                 {:operator, %{}, "="},
                 {:string, %{}, value}
               ]
      else
        assert lex(attribute) == [
                 {:name_attribute, %{}, name}
               ]
      end
    end
  end

  test "disabled" do
    attribute = "disabled"

    assert lex(attribute) == [
             {:name_attribute, %{}, attribute}
           ]
  end

  test "value=yes" do
    attribute = "value=yes"

    assert lex(attribute) == [
             {:name_attribute, %{}, "value"},
             {:operator, %{}, "="},
             {:string, %{}, "yes"}
           ]
  end

  test "type='checkbox'" do
    attribute = "type='checkbox'"

    assert lex(attribute) == [
             {:name_attribute, %{}, "value"},
             {:operator, %{}, "="},
             {:string, %{}, "'checkbox'"}
           ]
  end

  test "name=\"be evil\"" do
    attribute = "name=\"be evil\""

    assert lex(attribute) == [
             {:name_attribute, %{}, "name"},
             {:operator, %{}, "="},
             {:string, %{}, "\"be evil\""}
           ]
  end

  ###################################################################
  # Single element
  ###################################################################
  property "correct single element does not produce errors" do
    check all(single_element <- HTMLGenerators.single_element()) do
      assert !Enum.any?(lex(single_element), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect single element produces errors" do
    check all(single_element <- HTMLGenerators.incorrect_single_element()) do
      assert Enum.any?(lex(single_element), &match?({:error, _, _}, &1))
    end
  end

  property "correct single element is correctly tokenized" do
    check all(single_element <- HTMLGenerators.single_element()) do
      if String.ends_with?(single_element, "/>") do
        element_opening =
          single_element
          |> String.replace_prefix("<", "")
          |> String.replace_suffix("/>", "")

        {element, attributes_tokens} = tokenize_elements(element_opening)

        assert lex(single_element) ==
                 [
                   {:punctuation, %{group_id: "group-1"}, "<"},
                   element
                 ] ++
                   attributes_tokens ++
                   [
                     {:punctuation, %{group_id: "group-1"}, "/>"}
                   ]
      else
        [head, tail] =
          single_element
          |> String.split(">", trim: true)

        element_opening =
          head
          |> String.replace_prefix("<", "")

        {element, attributes_tokens} = tokenize_elements(element_opening)

        if tail != [] do
          [element_content | element_ending] =
            tail
            |> String.split("<", trim: true)

          if element_ending != [] do
            assert lex(single_element) ==
                     [
                       {:punctuation, %{group_id: "group-1"}, "<"},
                       element
                     ] ++
                       attributes_tokens ++
                       [
                         {:punctuation, %{group_id: "group-1"}, ">"},
                         {:string, %{}, element_content},
                         {:punctuation, %{group_id: "group-2"}, "</"},
                         element,
                         {:punctuation, %{group_id: "group-2"}, ">"}
                       ]
          else
            assert lex(single_element) ==
                     [
                       {:punctuation, %{group_id: "group-1"}, "<"},
                       element
                     ] ++
                       attributes_tokens ++
                       [
                         {:punctuation, %{group_id: "group-1"}, ">"},
                         {:punctuation, %{group_id: "group-2"}, "</"},
                         element,
                         {:punctuation, %{group_id: "group-2"}, ">"}
                       ]
          end
        else
          assert lex(single_element) ==
                   [
                     {:punctuation, %{group_id: "group-1"}, "<"},
                     element
                   ] ++
                     attributes_tokens ++
                     [
                       {:punctuation, %{group_id: "group-1"}, ">"}
                     ]
        end
      end
    end
  end

  test "<input value=yes />" do
    element = "<input value=yes />"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "value"},
             {:operator, %{}, "="},
             {:string, %{}, "yes"},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-1"}, "/>"}
           ]
  end

  test "<title>Hello</title>" do
    element = "<title>Hello</title>"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:string, %{}, "Hello"},
             {:punctuation, %{group_id: "group-2"}, "</"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-2"}, ">"}
           ]
  end

  test "<p></p>" do
    element = "<p></p>"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "p"},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:punctuation, %{group_id: "group-2"}, "</"},
             {:keyword, %{}, "p"},
             {:punctuation, %{group_id: "group-2"}, ">"}
           ]
  end

  test "<input disabled>" do
    element = "<input disabled>"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "disabled"},
             {:punctuation, %{group_id: "group-1"}, ">"}
           ]
  end

  ###################################################################
  # Nested element
  ###################################################################
  property "correct nested element does not produce errors" do
    check all(nested_element <- HTMLGenerators.nested_element()) do
      assert !Enum.any?(lex(nested_element), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect nested element produces errors" do
    check all(nested_element <- HTMLGenerators.incorrect_nested_element()) do
      assert Enum.any?(lex(nested_element), &match?({:error, _, _}, &1))
    end
  end

  test "<head><title>Hello</title></head>" do
    element = "<head><title>Hello</title></head>"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "head"},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:punctuation, %{group_id: "group-2"}, "<"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-2"}, ">"},
             {:string, %{}, "Hello"},
             {:punctuation, %{group_id: "group-3"}, "</"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-3"}, ">"},
             {:punctuation, %{group_id: "group-4"}, "</"},
             {:keyword, %{}, "head"},
             {:punctuation, %{group_id: "group-4"}, ">"}
           ]
  end

  test "<body><br></body>" do
    element = "<body><br></body>"

    assert lex(element) == [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "body"},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:punctuation, %{group_id: "group-2"}, "<"},
             {:keyword, %{}, "br"},
             {:punctuation, %{group_id: "group-2"}, ">"},
             {:punctuation, %{group_id: "group-3"}, "</"},
             {:keyword, %{}, "body"},
             {:punctuation, %{group_id: "group-3"}, ">"}
           ]
  end

  ###################################################################
  # Element
  ###################################################################
  property "correct element does not produce errors" do
    check all(element <- HTMLGenerators.element()) do
      assert !Enum.any?(lex(element), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect element produces errors" do
    check all(element <- HTMLGenerators.incorrect_element()) do
      assert Enum.any?(lex(element), &match?({:error, _, _}, &1))
    end
  end

  ###################################################################
  # Document
  ###################################################################
  property "correct HTML document does not produce errors" do
    check all(document <- HTMLGenerators.document()) do
      assert !Enum.any?(lex(document), &match?({:error, _, _}, &1))
    end
  end

  property "incorrect HTML document produces errors" do
    check all(document <- HTMLGenerators.incorrect_document()) do
      assert Enum.any?(lex(document), &match?({:error, _, _}, &1))
    end
  end

  test "HTML document" do
    document = """
    <!DOCTYPE HTML>
      <html>
        <!-- this is a comment -->
        <head>
          <title>
            Hello
          </title>
        </head>
        <body>
          <p>
            Welcome to this example.
          </p>
        </body>
      </html>
    """

    assert lex(document) == [
             {:keyword, %{}, "<!DOCTYPE HTML>"},
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:keyword, %{}, "html"},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:comment, %{}, "<!-- this is a comment -->"},
             {:punctuation, %{group_id: "group-2"}, "<"},
             {:keyword, %{}, "head"},
             {:punctuation, %{group_id: "group-2"}, ">"},
             {:punctuation, %{group_id: "group-3"}, "<"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-3"}, ">"},
             {:string, %{}, "Hello"},
             {:punctuation, %{group_id: "group-4"}, "</"},
             {:keyword, %{}, "title"},
             {:punctuation, %{group_id: "group-4"}, ">"},
             {:punctuation, %{group_id: "group-5"}, "</"},
             {:keyword, %{}, "head"},
             {:punctuation, %{group_id: "group-5"}, ">"},
             {:punctuation, %{group_id: "group-6"}, "<"},
             {:keyword, %{}, "body"},
             {:punctuation, %{group_id: "group-6"}, ">"},
             {:punctuation, %{group_id: "group-7"}, "<"},
             {:keyword, %{}, "p"},
             {:punctuation, %{group_id: "group-7"}, ">"},
             {:string, %{}, "Welcome to this example."},
             {:punctuation, %{group_id: "group-8"}, "</"},
             {:keyword, %{}, "p"},
             {:punctuation, %{group_id: "group-8"}, ">"},
             {:punctuation, %{group_id: "group-9"}, "</"},
             {:keyword, %{}, "body"},
             {:punctuation, %{group_id: "group-9"}, ">"},
             {:punctuation, %{group_id: "group-10"}, "</"},
             {:keyword, %{}, "html"},
             {:punctuation, %{group_id: "group-10"}, ">"}
           ]
  end
end
