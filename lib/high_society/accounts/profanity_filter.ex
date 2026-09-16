defmodule HighSociety.Accounts.ProfanityFilter do
  @moduledoc """
  A best-effort check for common English profanity/slurs in user-supplied
  display names. Matches whole words only (case-insensitive, punctuation-
  and digit-stripped), so a blocked word has to appear as its own token -
  "assassin" doesn't trip on "ass", "class" doesn't trip on "las", etc.

  This is intentionally a small, maintainable blocklist covering the most
  common cases, not an exhaustive or unbeatable filter - determined users
  can always route around word-based matching (spacing, leetspeak,
  homoglyphs...). Treat it as a courtesy check, not a security boundary.
  """

  @blocked ~w(
    fuck fucker fucking fuckface fuckwit motherfucker
    shit shitty bullshit
    bitch bastard asshole ass cunt dick pussy cock
    nigger nigga faggot fag retard retarded spic chink gook kike tranny
    whore slut skank
    rape rapist nazi hitler
  )

  @doc """
  Whether `text` contains a blocked word as one of its whole tokens.
  """
  @spec blocked?(String.t()) :: boolean()
  def blocked?(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.any?(&(&1 in @blocked))
  end
end
