defmodule Makeup.Lexers.HTMLLexer.RegistryTest do
  use ExUnit.Case, async: true

  alias Makeup.Registry
  alias Makeup.Lexers.HTMLLexer

  describe "the html lexer has successfully registered itself:" do
    test "language name" do
      assert {:ok, {HTMLLexer, []}} == Registry.fetch_lexer_by_name("html")
    end

    test "file extension" do
      assert {:ok, {HTMLLexer, []}} == Registry.fetch_lexer_by_extension("html")
    end
  end
end
