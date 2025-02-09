defmodule HTMLLexerTokenizer do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Makeup.Lexers.HTMLLexer
  alias Makeup.Lexer.Postprocess
  alias Helper

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

  defp tokenize_elements(element) do
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

    if attributes_tokens == [],
      do: {{:name_tag, %{}, element_name}, {:whitespace, %{}, " "}},
      else: {{:name_tag, %{}, element_name}, attributes_tokens}
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
  describe "DOCTYPE" do
    property "correct DOCTYPE is correctly tokenized" do
      check all(doctype <- HTMLGenerators.doctype()) do
        assert lex(doctype) == [{:comment_preproc, %{}, doctype}]
      end
    end

    property "incorrect DOCTYPE is incorrectly tokenized" do
      check all(doctype <- HTMLGenerators.incorrect_doctype()) do
        refute lex(doctype) == [{:comment_preproc, %{}, doctype}]
      end
    end

    test "<!DOCTYPE html>" do
      doctype = "<!DOCTYPE html>"

      assert lex(doctype) == [{:comment_preproc, %{}, "<!DOCTYPE html>"}]
    end

    test "<!DOCTYPE html SYSTEM 'about:legacy-compat'>" do
      doctype = "<!DOCTYPE html SYSTEM 'about:legacy-compat'>"

      assert lex(doctype) == [
               {:comment_preproc, %{}, "<!DOCTYPE html SYSTEM 'about:legacy-compat'>"}
             ]
    end
  end

  ###################################################################
  # Comment
  ###################################################################
  describe "comment" do
    property "correct comment is correctly tokenized" do
      check all(comment <- HTMLGenerators.comment()) do
        assert lex(comment) == [{:comment, %{}, comment}]
      end
    end

    test "<!--My favorite operators are > and <!-->" do
      comment = "<!--My favorite operators are > and <!-->"

      assert lex(comment) == [{:comment, %{}, "<!--My favorite operators are > and <!-->"}]
    end
  end

  ###################################################################
  # Void element
  ###################################################################
  describe "void element" do
    property "correct void_element is correctly tokenized" do
      check all(void_element <- HTMLGenerators.void_element()) do
        element =
          void_element
          |> String.replace_prefix("<", "")
          |> String.replace_suffix(">", "")

        assert lex(void_element) == [
                 {:punctuation, %{group_id: "group-1"}, "<"},
                 {:name_tag, %{}, element},
                 {:punctuation, %{group_id: "group-1"}, ">"}
               ]
      end
    end

    property "incorrect void_element is incorrectly tokenized" do
      check all(void_element <- HTMLGenerators.incorrect_void_element()) do
        element =
          void_element
          |> String.replace_prefix("<", "")
          |> String.replace_suffix(">", "")

        refute lex(void_element) == [
                 {:punctuation, %{group_id: "group-1"}, "<"},
                 {:name_tag, %{}, element},
                 {:punctuation, %{group_id: "group-1"}, ">"}
               ]
      end
    end

    test "<hr>" do
      void_element = "<hr>"

      assert lex(void_element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "hr"},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end
  end

  ###################################################################
  # Attribute
  ###################################################################
  describe "attribute" do
    property "correct attribute is correctly tokenized" do
      check all(attribute <- HTMLGenerators.attribute()) do
        [name | value] =
          attribute
          |> String.split("=")

        if value != [] do
          assert lex(attribute) == [
                   {:name_attribute, %{}, name},
                   {:operator, %{}, "="},
                   {:string, %{}, value |> Enum.at(0)}
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
               {:name_attribute, %{}, "type"},
               {:operator, %{}, "="},
               {:string, %{}, "'checkbox'"}
             ]
    end

    test "name=\"be evil\"" do
      attribute = "name=\"be evil\""

      assert lex(attribute) == [
               {:name_attribute, %{}, "name"},
               {:operator, %{}, "="},
               {:string, %{}, "\"be"},
               {:whitespace, %{}, " "},
               {:string, %{}, "evil\""}
             ]
    end
  end

  ###################################################################
  # Single element
  ###################################################################
  describe "single element" do
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
          [head | tail] =
            single_element
            |> String.split(">", trim: true)

          element_opening =
            head
            |> String.replace_prefix("<", "")

          {element, attributes_tokens} = tokenize_elements(element_opening)

          if tail != [] do
            [element_content | rest] =
              tail
              |> Enum.at(0)
              |> String.split("</", trim: true)

            content_tokens =
              if rest != [],
                do: [{:string, %{}, element_content}],
                else: rest

            assert lex(single_element) ==
                     [
                       {:punctuation, %{group_id: "group-1"}, "<"},
                       element
                     ] ++
                       attributes_tokens ++
                       [
                         {:punctuation, %{group_id: "group-1"}, ">"}
                       ] ++
                       content_tokens ++
                       [
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
               {:name_tag, %{}, "input"},
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
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:string, %{}, "Hello"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "<p></p>" do
      element = "<p></p>"

      assert lex(element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "<input disabled>" do
      element = "<input disabled>"

      assert lex(element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "input"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "disabled"},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end

    test "<a >" do
      element = "<a >"

      assert lex(element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "a"},
               {:whitespace, %{}, " "},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end
  end

  ###################################################################
  # Nested element
  ###################################################################
  describe "nested element" do
    test "<head><title>Hello</title></head>" do
      element = "<head><title>Hello</title></head>"

      assert lex(element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:punctuation, %{group_id: "group-2"}, "<"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-2"}, ">"},
               {:string, %{}, "Hello"},
               {:punctuation, %{group_id: "group-3"}, "</"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-3"}, ">"},
               {:punctuation, %{group_id: "group-4"}, "</"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-4"}, ">"}
             ]
    end

    test "<body><br></body>" do
      element = "<body><br></body>"

      assert lex(element) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:punctuation, %{group_id: "group-2"}, "<"},
               {:name_tag, %{}, "br"},
               {:punctuation, %{group_id: "group-2"}, ">"},
               {:punctuation, %{group_id: "group-3"}, "</"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-3"}, ">"}
             ]
    end
  end

  ###################################################################
  # Document
  ###################################################################
  describe "HTML document" do
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
               {:comment_preproc, %{}, "<!DOCTYPE HTML>"},
               {:whitespace, %{}, "\n  "},
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "html"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:string, %{}, "\n    "},
               {:comment, %{}, "<!-- this is a comment -->"},
               {:string, %{}, "\n    "},
               {:punctuation, %{group_id: "group-2"}, "<"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-2"}, ">"},
               {:string, %{}, "\n      "},
               {:punctuation, %{group_id: "group-3"}, "<"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-3"}, ">"},
               {:string, %{}, "\n        Hello\n      "},
               {:punctuation, %{group_id: "group-4"}, "</"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-4"}, ">"},
               {:string, %{}, "\n    "},
               {:punctuation, %{group_id: "group-5"}, "</"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-5"}, ">"},
               {:string, %{}, "\n    "},
               {:punctuation, %{group_id: "group-6"}, "<"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-6"}, ">"},
               {:string, %{}, "\n      "},
               {:punctuation, %{group_id: "group-7"}, "<"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-7"}, ">"},
               {:string, %{}, "\n        Welcome to this example.\n      "},
               {:punctuation, %{group_id: "group-8"}, "</"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-8"}, ">"},
               {:string, %{}, "\n    "},
               {:punctuation, %{group_id: "group-9"}, "</"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-9"}, ">"},
               {:string, %{}, "\n  "},
               {:punctuation, %{group_id: "group-10"}, "</"},
               {:name_tag, %{}, "html"},
               {:punctuation, %{group_id: "group-10"}, ">"},
               {:whitespace, %{}, "\n"}
             ]
    end
  end

  # Empty attributes (from HEEx)
  test "handles empty attributes" do
    element = """
    <.inputs_for :let= field=>
      <input type="hidden" name="list[emails_sort][]" value= />
      <.input type="text" field= placeholder="email" />
      <.input type="text" field= placeholder="name" />
      <label>
        <input type="checkbox" name="list[emails_drop][]" value= class="hidden" />
        delete
      </label>
    </.inputs_for>

    <label class="block cursor-pointer">
      <input type="checkbox" name="list[emails_sort][]" class="hidden" />
      add more
    </label>
    """

    assert [
             {:punctuation, %{group_id: "group-1"}, "<"},
             {:name_tag, %{}, ".inputs_for"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, ":let"},
             {:operator, %{}, "="},
             {:string, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:string, %{}, "\n  "},
             {:punctuation, %{group_id: "group-2"}, "<"},
             {:name_tag, %{}, "input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"hidden\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "name"},
             {:operator, %{}, "="},
             {:string, %{}, "\"list[emails_sort][]\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "value"},
             {:operator, %{}, "="},
             {:string, %{}, " "},
             {:punctuation, %{group_id: "group-2"}, "/>"},
             {:whitespace, %{}, "\n  "},
             {:punctuation, %{group_id: "group-3"}, "<"},
             {:name_tag, %{}, ".input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"text\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:string, %{}, " "},
             {:name_attribute, %{}, "placeholder"},
             {:operator, %{}, "="},
             {:string, %{}, "\"email\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-3"}, "/>"},
             {:whitespace, %{}, "\n  "},
             {:punctuation, %{group_id: "group-4"}, "<"},
             {:name_tag, %{}, ".input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"text\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:string, %{}, " "},
             {:name_attribute, %{}, "placeholder"},
             {:operator, %{}, "="},
             {:string, %{}, "\"name\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-4"}, "/>"},
             {:whitespace, %{}, "\n  "},
             {:punctuation, %{group_id: "group-5"}, "<"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-5"}, ">"},
             {:string, %{}, "\n    "},
             {:punctuation, %{group_id: "group-6"}, "<"},
             {:name_tag, %{}, "input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"checkbox\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "name"},
             {:operator, %{}, "="},
             {:string, %{}, "\"list[emails_drop][]\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "value"},
             {:operator, %{}, "="},
             {:string, %{}, " "},
             {:name_attribute, %{}, "class"},
             {:operator, %{}, "="},
             {:string, %{}, "\"hidden\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-6"}, "/>"},
             {:whitespace, %{}, "\n    "},
             {:string, %{}, "delete"},
             {:whitespace, %{}, "\n  "},
             {:punctuation, %{group_id: "group-7"}, "</"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-7"}, ">"},
             {:string, %{}, "\n"},
             {:punctuation, %{group_id: "group-8"}, "</"},
             {:name_tag, %{}, ".inputs_for"},
             {:punctuation, %{group_id: "group-8"}, ">"},
             {:string, %{}, "\n\n"},
             {:punctuation, %{group_id: "group-9"}, "<"},
             {:name_tag, %{}, "label"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "class"},
             {:operator, %{}, "="},
             {:string, %{}, "\"block"},
             {:whitespace, %{}, " "},
             {:string, %{}, "cursor-pointer\""},
             {:punctuation, %{group_id: "group-9"}, ">"},
             {:string, %{}, "\n  "},
             {:punctuation, %{group_id: "group-10"}, "<"},
             {:name_tag, %{}, "input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"checkbox\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "name"},
             {:operator, %{}, "="},
             {:string, %{}, "\"list[emails_sort][]\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "class"},
             {:operator, %{}, "="},
             {:string, %{}, "\"hidden\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-10"}, "/>"},
             {:whitespace, %{}, "\n  "},
             {:string, %{}, "add"},
             {:whitespace, %{}, " "},
             {:string, %{}, "more"},
             {:whitespace, %{}, "\n"},
             {:punctuation, %{group_id: "group-11"}, "</"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-11"}, ">"},
             {:whitespace, %{}, "\n"}
           ] = lex(element)
  end
end
