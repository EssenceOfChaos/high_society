# Alias modules so we can use them without the full module name
alias HighSociety.Accounts.{
  Scope,
  User
}

alias HighSociety.Repo
alias HighSociety.Healthcheck

alias HighSociety.Games.{
  Blackjack,
  War,
  BlackjackGame,
  WarGame,
  Baccarat,
  BaccaratGame,
  Battleship,
  BattleshipGame,
  ZombieAttack,
  ZombieAttackGame,
  Poker,
  PokerTables,
  PokerGame,
  PokerTournament,
  TournamentBlinds,
  TournamentPlayers,
  TournamentPlayer,
  TournamentGame,
  TournamentGamePlayer,
  TournamentGamePlayerAction
}

alias HighSociety.Badges
import Ecto.{Query, Changeset}

IEx.configure(inspect: [charlists: :as_lists])
