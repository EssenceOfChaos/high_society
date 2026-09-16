# Alias modules so we can use them without the full module name
alias HighSociety.Accounts.{
  Scope,
  User
}

alias HighSociety.Repo

alias HighSociety.Games.{
  Blackjack,
  War,
  BlackjackGame,
  WarGame
}

alias HighSociety.Badges
import Ecto.{Query, Changeset}

IEx.configure(inspect: [charlists: :as_lists])
