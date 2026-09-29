defmodule HTMLLexerTokenizer do
  use ExUnit.Case, async: false

  alias Makeup.Lexers.HTMLLexer
  alias Makeup.Lexer.Postprocess

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
    test "<!--My favorite operators are > and <!-->" do
      comment = "<!--My favorite operators are > and <!-->"

      assert lex(comment) == [
               {:comment_multiline, %{}, "<!--My favorite operators are > and <!-->"}
             ]
    end

    test "an empty comment closes on >" do
      assert lex("<!-->x") == [{:comment_multiline, %{}, "<!-->"}, {:text, %{}, "x"}]
    end

    test "an empty comment closes on ->" do
      assert lex("<!--->x") == [{:comment_multiline, %{}, "<!--->"}, {:text, %{}, "x"}]
    end

    test "<!----> is a comment" do
      assert lex("<!---->") == [{:comment_multiline, %{}, "<!---->"}]
    end

    test "--!> closes the comment" do
      assert lex("<!-- x --!><p>y</p>") == [
               {:comment_multiline, %{}, "<!-- x --!>"},
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "y"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "--!> closes the comment before a later -->" do
      assert lex("<!-- a --!> b -->") == [
               {:comment_multiline, %{}, "<!-- a --!>"},
               {:text, %{}, " b -->"}
             ]
    end

    test "an unterminated comment runs to the end of the input" do
      assert lex("<!-- x") == [{:comment_multiline, %{}, "<!-- x"}]
    end
  end

  ###################################################################
  # Character reference
  ###################################################################
  describe "character reference" do
    test "named" do
      assert lex("Tom &amp; Jerry") == [
               {:text, %{}, "Tom "},
               {:name_entity, %{}, "&amp;"},
               {:text, %{}, " Jerry"}
             ]
    end

    test "decimal" do
      assert lex("&#169;") == [{:name_entity, %{}, "&#169;"}]
    end

    test "hexadecimal" do
      assert lex("&#xA9;") == [{:name_entity, %{}, "&#xA9;"}]
    end

    test "an ampersand with no semicolon is text" do
      assert lex("a & b") == [{:text, %{}, "a "}, {:text, %{}, "&"}, {:text, %{}, " b"}]
    end
  end

  ###################################################################
  # CDATA section
  ###################################################################
  describe "CDATA section" do
    test "<![CDATA[x<y]]>" do
      cdata = "<![CDATA[x<y]]>"

      assert lex(cdata) == [{:comment_preproc, %{}, cdata}]
    end

    test "inside a MathML element" do
      assert lex("<ms><![CDATA[x<y]]></ms>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "ms"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:comment_preproc, %{}, "<![CDATA[x<y]]>"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "ms"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end
  end

  ###################################################################
  # Processing instruction
  ###################################################################
  describe "processing instruction" do
    test "with a target only" do
      assert lex("<?target>") == [{:comment_preproc, %{}, "<?target>"}]
    end

    test "with data" do
      instruction = ~S|<?xml version="1.0"?>|

      assert lex(instruction) == [{:comment_preproc, %{}, instruction}]
    end
  end

  ###################################################################
  # Tag name
  ###################################################################
  describe "tag name" do
    test "a digit does not start a tag" do
      assert lex("<p>1<2</p>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "1"},
               {:text, %{}, "<"},
               {:text, %{}, "2"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "a HEEx function component" do
      assert lex("<.input />") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, ".input"},
               {:whitespace, %{}, " "},
               {:punctuation, %{group_id: "group-1"}, "/>"}
             ]
    end

    test "a HEEx slot" do
      assert lex("<:inner_block>x</:inner_block>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, ":inner_block"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "x"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, ":inner_block"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "a namespaced tag" do
      assert lex("<svg:rect />") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "svg:rect"},
               {:whitespace, %{}, " "},
               {:punctuation, %{group_id: "group-1"}, "/>"}
             ]
    end
  end

  ###################################################################
  # Void element
  ###################################################################
  describe "void element" do
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
    test "<input disabled>" do
      assert lex("<input disabled>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "input"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "disabled"},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end

    test "<input value=yes>" do
      assert lex("<input value=yes>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "input"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "value"},
               {:operator, %{}, "="},
               {:string, %{}, "yes"},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end

    test "<input type='checkbox'>" do
      assert lex("<input type='checkbox'>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "input"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "type"},
               {:operator, %{}, "="},
               {:string, %{}, "'checkbox'"},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end

    test "<input name=\"be evil\">" do
      assert lex("<input name=\"be evil\">") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "input"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "name"},
               {:operator, %{}, "="},
               {:string, %{}, "\"be evil\""},
               {:punctuation, %{group_id: "group-1"}, ">"}
             ]
    end
  end

  ###################################################################
  # Unterminated tag
  ###################################################################
  describe "unterminated tag" do
    test "with only a name" do
      assert lex("<div") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "div"}
             ]
    end

    test "with an attribute and no value" do
      assert lex("<div class=") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "div"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "class"},
               {:operator, %{}, "="}
             ]
    end

    test "with an unterminated quoted value" do
      assert lex(~S|<div class="x|) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "div"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "class"},
               {:operator, %{}, "="},
               {:string, %{}, ~S|"x|}
             ]
    end

    test "with a trailing solidus" do
      assert lex("<br/") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "br"},
               {:punctuation, %{}, "/"}
             ]
    end
  end

  ###################################################################
  # Single element
  ###################################################################
  describe "single element" do
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
               {:text, %{}, "Hello"},
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
               {:text, %{}, "Hello"},
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
  # Raw text element
  ###################################################################
  describe "raw text element" do
    test "<style>ul > li { color: red }</style>" do
      assert lex("<style>ul > li { color: red }</style>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "style"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "ul > li { color: red }"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "style"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "comparison operators in a script are not tags" do
      assert lex("<script>if (a<b && c>d) f()</script>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "script"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "if (a<b && c>d) f()"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "script"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "an end tag inside a string is not a tag" do
      assert lex(~S|<script>w("</p>")</script>|) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "script"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, ~S|w("</p>")|},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "script"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "with attributes and no body" do
      assert lex(~S|<script src="a.js"></script>|) == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "script"},
               {:whitespace, %{}, " "},
               {:name_attribute, %{}, "src"},
               {:operator, %{}, "="},
               {:string, %{}, ~S|"a.js"|},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "script"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "the close tag is matched case-insensitively" do
      assert lex("<SCRIPT>x</SCRIPT>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "SCRIPT"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "x"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "SCRIPT"},
               {:punctuation, %{group_id: "group-2"}, ">"}
             ]
    end

    test "a longer name that starts with script is an ordinary element" do
      assert lex("<scripty>a</scripty>") == [
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "scripty"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "a"},
               {:punctuation, %{group_id: "group-2"}, "</"},
               {:name_tag, %{}, "scripty"},
               {:punctuation, %{group_id: "group-2"}, ">"}
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
               {:text, %{}, "
  "},
               {:punctuation, %{group_id: "group-1"}, "<"},
               {:name_tag, %{}, "html"},
               {:punctuation, %{group_id: "group-1"}, ">"},
               {:text, %{}, "
    "},
               {:comment_multiline, %{}, "<!-- this is a comment -->"},
               {:text, %{}, "
    "},
               {:punctuation, %{group_id: "group-2"}, "<"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-2"}, ">"},
               {:text, %{}, "
      "},
               {:punctuation, %{group_id: "group-3"}, "<"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-3"}, ">"},
               {:text, %{}, "
        Hello
      "},
               {:punctuation, %{group_id: "group-4"}, "</"},
               {:name_tag, %{}, "title"},
               {:punctuation, %{group_id: "group-4"}, ">"},
               {:text, %{}, "
    "},
               {:punctuation, %{group_id: "group-5"}, "</"},
               {:name_tag, %{}, "head"},
               {:punctuation, %{group_id: "group-5"}, ">"},
               {:text, %{}, "
    "},
               {:punctuation, %{group_id: "group-6"}, "<"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-6"}, ">"},
               {:text, %{}, "
      "},
               {:punctuation, %{group_id: "group-7"}, "<"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-7"}, ">"},
               {:text, %{}, "
        Welcome to this example.
      "},
               {:punctuation, %{group_id: "group-8"}, "</"},
               {:name_tag, %{}, "p"},
               {:punctuation, %{group_id: "group-8"}, ">"},
               {:text, %{}, "
    "},
               {:punctuation, %{group_id: "group-9"}, "</"},
               {:name_tag, %{}, "body"},
               {:punctuation, %{group_id: "group-9"}, ">"},
               {:text, %{}, "
  "},
               {:punctuation, %{group_id: "group-10"}, "</"},
               {:name_tag, %{}, "html"},
               {:punctuation, %{group_id: "group-10"}, ">"},
               {:text, %{}, "
"}
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
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:punctuation, %{group_id: "group-1"}, ">"},
             {:text, %{}, "
  "},
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
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-2"}, "/>"},
             {:text, %{}, "
  "},
             {:punctuation, %{group_id: "group-3"}, "<"},
             {:name_tag, %{}, ".input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"text\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "placeholder"},
             {:operator, %{}, "="},
             {:string, %{}, "\"email\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-3"}, "/>"},
             {:text, %{}, "
  "},
             {:punctuation, %{group_id: "group-4"}, "<"},
             {:name_tag, %{}, ".input"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "type"},
             {:operator, %{}, "="},
             {:string, %{}, "\"text\""},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "field"},
             {:operator, %{}, "="},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "placeholder"},
             {:operator, %{}, "="},
             {:string, %{}, "\"name\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-4"}, "/>"},
             {:text, %{}, "
  "},
             {:punctuation, %{group_id: "group-5"}, "<"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-5"}, ">"},
             {:text, %{}, "
    "},
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
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "class"},
             {:operator, %{}, "="},
             {:string, %{}, "\"hidden\""},
             {:whitespace, %{}, " "},
             {:punctuation, %{group_id: "group-6"}, "/>"},
             {:text, %{}, "
    delete
  "},
             {:punctuation, %{group_id: "group-7"}, "</"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-7"}, ">"},
             {:text, %{}, "
"},
             {:punctuation, %{group_id: "group-8"}, "</"},
             {:name_tag, %{}, ".inputs_for"},
             {:punctuation, %{group_id: "group-8"}, ">"},
             {:text, %{}, "

"},
             {:punctuation, %{group_id: "group-9"}, "<"},
             {:name_tag, %{}, "label"},
             {:whitespace, %{}, " "},
             {:name_attribute, %{}, "class"},
             {:operator, %{}, "="},
             {:string, %{}, "\"block cursor-pointer\""},
             {:punctuation, %{group_id: "group-9"}, ">"},
             {:text, %{}, "
  "},
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
             {:text, %{}, "
  add more
"},
             {:punctuation, %{group_id: "group-11"}, "</"},
             {:name_tag, %{}, "label"},
             {:punctuation, %{group_id: "group-11"}, ">"},
             {:text, %{}, "
"}
           ] = lex(element)
  end
end
