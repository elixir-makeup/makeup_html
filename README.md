# MakeupHTML

[![Build Status](https://github.com/elixir-makeup/makeup_html/workflows/CI/badge.svg)](https://github.com/elixir-makeup/makeup_html/actions)

A [Makeup](https://github.com/elixir-makeup/makeup/) lexer for the `HTML` language.

## Installation

Add `makeup_html` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:makeup_html, "~> 0.1.0"}
  ]
end
```

The lexer will automatically register itself with `Makeup` for the HTML language as well as the `.html` extension.
