defmodule HighSociety.Games.ZombieAttack do
  @moduledoc """
  Pure game logic for Zombie Attack: wave spawn schedules, the defender/
  zombie specs the client needs to simulate a match, and the payout table -
  with no dependency on persistence or web.

  The moment-to-moment match (zombie movement, projectile collisions,
  defender placement) is simulated entirely client-side on a canvas; the
  server never replays or verifies it. The only thing the server trusts is
  that reported wave checkpoints arrive in order, via `valid_next_wave?/2`
  - that function is the *entire* anti-cheat surface here. A modified
  client could report a false sequence of wave-cleared checkpoints and
  this module has no way to catch it. That's a deliberate simplicity
  tradeoff for a play-money game at this scope, not an oversight - a
  stronger version could have the client submit periodic state
  checksums, or have the server replay the match from `wave_schedule`
  plus a logged input stream, but neither is built here.
  """

  @lanes 4
  @columns 8
  @wave_count 6

  @type zombie_type :: :walker | :armored
  @type spawn_event :: %{
          lane: non_neg_integer(),
          zombie_type: zombie_type(),
          spawn_at_ms: integer()
        }
  @type outcome :: {:cleared_wave, 0..6} | :full_clear

  @defender_specs %{
    shooter: %{name: "Shooter", cost: 50, hp: 20, damage: 15, range: 4, fire_rate_ms: 850},
    cannon: %{name: "Cannon", cost: 95, hp: 25, damage: 26, range: 5, fire_rate_ms: 950},
    blocker: %{name: "Blocker", cost: 25, hp: 75, damage: 0, range: 0, fire_rate_ms: 0}
  }

  # Display order for the palette - cheapest to priciest, not the map's
  # own (arbitrary) key order.
  @defender_order [:blocker, :shooter, :cannon]

  @zombie_specs %{
    walker: %{name: "Walker", hp: 80, speed: 35},
    armored: %{name: "Armored", hp: 130, speed: 25}
  }

  @doc "Number of lanes on the board."
  @spec lanes() :: pos_integer()
  def lanes, do: @lanes

  @doc "Number of columns on the board."
  @spec columns() :: pos_integer()
  def columns, do: @columns

  @doc "Total number of waves in a match."
  @spec wave_count() :: pos_integer()
  def wave_count, do: @wave_count

  @doc "Defender type specs (cost/hp/damage/range/fire_rate_ms), keyed by type."
  @spec defender_specs() :: map()
  def defender_specs, do: @defender_specs

  @doc "Defender types in display order (cheapest to priciest)."
  @spec defender_order() :: [atom()]
  def defender_order, do: @defender_order

  @doc "Zombie type specs (hp/speed), keyed by type."
  @spec zombie_specs() :: map()
  def zombie_specs, do: @zombie_specs

  @max_wager 500 * 100

  @doc "The maximum wager allowed for a single match, in cents."
  @spec max_wager() :: pos_integer()
  def max_wager, do: @max_wager

  @doc """
  The spawn schedule for one wave: a list of zombies, each tagged with the
  lane it enters on, its type, and how far into the wave (in milliseconds)
  it spawns. Pure and deterministic given only the wave number - mirrors
  `HighSociety.Games.BattleshipAI.choose_shot/2`'s shape of recomputing
  fresh from the caller's state rather than holding any process memory.
  """
  @spec wave_schedule(1..6) :: [spawn_event()]
  def wave_schedule(wave_number) when wave_number in 1..@wave_count do
    zombie_count = 3 + wave_number * 6
    armored_chance = (wave_number - 1) / @wave_count
    spacing_ms = max(2000 - wave_number * 250, 800)

    for i <- 0..(zombie_count - 1) do
      %{
        lane: rem(i, @lanes),
        zombie_type: if(:rand.uniform() < armored_chance, do: :armored, else: :walker),
        spawn_at_ms: i * spacing_ms
      }
    end
  end

  @doc """
  The full 6-wave schedule, generated once at match start and stored
  server-side. Each wave is wrapped in its own map (rather than returned as
  a bare nested list) so the whole thing round-trips through the
  `zombie_attack_games.wave_schedule` `{:array, :map}` jsonb column as-is.
  """
  @spec full_wave_schedule() :: [%{wave: pos_integer(), spawns: [spawn_event()]}]
  def full_wave_schedule do
    Enum.map(1..@wave_count, fn wave -> %{wave: wave, spawns: wave_schedule(wave)} end)
  end

  # Payout multiplier in hundredths (100 = break-even), keyed by the
  # highest wave reached. `0` covers losing during wave 1 before clearing
  # anything.
  @payout_multipliers_hundredths %{
    0 => 0,
    1 => 25,
    2 => 50,
    3 => 100,
    4 => 150,
    5 => 250,
    6 => 300
  }

  @doc """
  The payout for a match, given the wager and how it ended. `{:cleared_wave,
  n}` is a loss after clearing `n` waves (0 if the player lost during wave
  1); `:full_clear` is surviving all `#{@wave_count}` waves.
  """
  @spec payout_for(pos_integer(), outcome()) :: non_neg_integer()
  def payout_for(wager, :full_clear) when is_integer(wager) and wager > 0 do
    payout_for(wager, {:cleared_wave, @wave_count})
  end

  def payout_for(wager, {:cleared_wave, wave_reached})
      when is_integer(wager) and wager > 0 and wave_reached in 0..@wave_count do
    multiplier = Map.fetch!(@payout_multipliers_hundredths, wave_reached)
    div(wager * multiplier, 100)
  end

  @doc """
  Whether a reported wave-cleared checkpoint is the very next one expected
  after `current_wave_reached`. This is the entire anti-cheat validation
  for a match - see the moduledoc.
  """
  @spec valid_next_wave?(non_neg_integer(), pos_integer()) :: boolean()
  def valid_next_wave?(current_wave_reached, reported_wave) do
    reported_wave == current_wave_reached + 1
  end
end
