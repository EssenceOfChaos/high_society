defmodule HighSociety.Games.TournamentBlinds do
  @moduledoc """
  The canonical poker tournament structure - starting stack, blind
  schedule, and level/break timing - compile-time data in the same spirit
  as `HighSociety.Games.PokerTables`' cash-table config. Unlike
  `PokerTables`, nothing reads this live at runtime: `default_schedule/0`
  and friends are snapshotted onto a `HighSociety.Tournaments.PokerTournament`
  row at creation time (see `HighSociety.Tournaments.create_tournament/1`),
  so a later change here never retroactively alters a tournament that's
  already scheduled, running, or finished.
  """

  @starting_stack 10_000
  @level_minutes 12
  @break_every_minutes 60
  @break_minutes 5
  @late_registration_minutes 60

  @blind_levels [
    %{small_blind: 100, big_blind: 200},
    %{small_blind: 150, big_blind: 300},
    %{small_blind: 200, big_blind: 400},
    %{small_blind: 250, big_blind: 500},
    %{small_blind: 400, big_blind: 800},
    %{small_blind: 700, big_blind: 1_400},
    %{small_blind: 1_200, big_blind: 2_400},
    %{small_blind: 2_000, big_blind: 4_000},
    %{small_blind: 3_000, big_blind: 6_000},
    %{small_blind: 4_000, big_blind: 8_000},
    %{small_blind: 5_000, big_blind: 10_000},
    %{small_blind: 6_000, big_blind: 12_000},
    %{small_blind: 8_000, big_blind: 16_000},
    %{small_blind: 10_000, big_blind: 20_000},
    %{small_blind: 15_000, big_blind: 30_000}
  ]

  @type blind_level :: %{small_blind: pos_integer(), big_blind: pos_integer()}

  @doc "The default 15-level blind schedule, smallest blinds first."
  @spec default_schedule() :: [blind_level()]
  def default_schedule, do: @blind_levels

  @doc "How many chips every entrant starts a tournament with."
  @spec starting_stack() :: pos_integer()
  def starting_stack, do: @starting_stack

  @doc "How long (minutes) each blind level lasts by default."
  @spec level_minutes() :: pos_integer()
  def level_minutes, do: @level_minutes

  @doc "How often (minutes of play) a tournament-wide break happens by default."
  @spec break_every_minutes() :: pos_integer()
  def break_every_minutes, do: @break_every_minutes

  @doc "How long (minutes) a tournament-wide break lasts by default."
  @spec break_minutes() :: pos_integer()
  def break_minutes, do: @break_minutes

  @doc "How long (minutes) after start new entrants can still buy in, by default."
  @spec late_registration_minutes() :: pos_integer()
  def late_registration_minutes, do: @late_registration_minutes

  @doc "How many levels are in the default schedule."
  @spec level_count() :: pos_integer()
  def level_count, do: length(@blind_levels)
end
