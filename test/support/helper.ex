defmodule Helper do
  @moduledoc false

  def insensitive_case_string(string) do
    string
    |> String.split("", trim: true)
    |> insensitive_case_string([])
    |> Enum.join("")
  end

  def insensitive_case_string([], result), do: result

  def insensitive_case_string([h | t], result) do
    insensitive_case_string(t, result ++ [insensitive_fun(Enum.random(0..1), h)])
  end

  defp insensitive_fun(0, string), do: String.downcase(string)
  defp insensitive_fun(1, string), do: String.upcase(string)
end
