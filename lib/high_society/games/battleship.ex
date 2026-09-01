defmodule HighSociety.Games.Battleship do
  @moduledoc """
  Pure game logic for Battleship: fleet placement, firing, and win
  detection, with no dependency on persistence or web. Used by both game
  modes (vs. computer and live vs. another human) - sides are named
  generically (`:player`/`:opponent`) so the same struct and functions
  work whether "opponent" is an AI or a second human.

  Coordinates are `{col, row}` tuples, zero-indexed (`{0, 0}` is "A1").
  `parse_coord/1` and `format_coord/1` convert to/from the "B4"-style
  strings used at the LiveView-params and jsonb-persistence boundary -
  since those already serialize directly to strings, the shot maps
  round-trip through jsonb with no atom/integer-key translation needed.
  """

  @board_size 10
  @columns ~w(A B C D E F G H I J)

  @ship_specs [
    %{type: :carrier, length: 5},
    %{type: :battleship, length: 4},
    %{type: :cruiser, length: 3},
    %{type: :submarine, length: 3},
    %{type: :destroyer, length: 2}
  ]

  @ship_types Enum.map(@ship_specs, & &1.type)

  @type coord :: {0..9, 0..9}
  @type orientation :: :horizontal | :vertical
  @type side :: :player | :opponent
  @type shot_result :: :hit | :miss | :sunk
  @type ship :: %{type: atom, cells: [coord], hits: MapSet.t(coord)}
  @type fleet :: [ship]
  @type status ::
          :placing_fleets
          | :player_turn
          | :opponent_turn
          | :player_won
          | :opponent_won

  @type t :: %__MODULE__{
          player_fleet: fleet,
          opponent_fleet: fleet,
          player_ready?: boolean,
          opponent_ready?: boolean,
          player_shots: %{String.t() => String.t()},
          opponent_shots: %{String.t() => String.t()},
          status: status
        }

  defstruct player_fleet: [],
            opponent_fleet: [],
            player_ready?: false,
            opponent_ready?: false,
            player_shots: %{},
            opponent_shots: %{},
            status: :placing_fleets

  @doc "The ship types and lengths required to complete a fleet."
  def ship_specs, do: @ship_specs

  @doc "The board is #{@board_size}x#{@board_size}."
  def board_size, do: @board_size

  @doc "Splits a \"B4\"-style coordinate into a zero-indexed `{col, row}` tuple."
  @spec parse_coord(String.t()) :: {:ok, coord} | :error
  def parse_coord(<<col_letter, rest::binary>>) do
    with col when col != nil <- Enum.find_index(@columns, &(&1 == <<col_letter>>)),
         {row_number, ""} <- Integer.parse(rest),
         row = row_number - 1,
         true <- col in 0..(@board_size - 1) and row in 0..(@board_size - 1) do
      {:ok, {col, row}}
    else
      _ -> :error
    end
  end

  def parse_coord(_), do: :error

  @doc "Formats a zero-indexed `{col, row}` tuple as a \"B4\"-style coordinate."
  @spec format_coord(coord) :: String.t()
  def format_coord({col, row}), do: Enum.at(@columns, col) <> Integer.to_string(row + 1)

  @doc """
  Attempts to add `ship_type` to `fleet` at `coord` (its topmost/leftmost
  cell) extending in `orientation`. Rejects an unknown or already-placed
  ship type, a run that leaves the board, or one that overlaps an
  existing ship.
  """
  @spec place_ship(fleet, atom, coord, orientation) ::
          {:ok, fleet} | {:error, :invalid_ship_type | :duplicate_ship_type | :out_of_bounds | :overlaps}
  def place_ship(fleet, ship_type, coord, orientation) do
    cond do
      ship_type not in @ship_types ->
        {:error, :invalid_ship_type}

      Enum.any?(fleet, &(&1.type == ship_type)) ->
        {:error, :duplicate_ship_type}

      true ->
        cells = ship_cells(coord, orientation, ship_length(ship_type))

        cond do
          not Enum.all?(cells, &on_board?/1) ->
            {:error, :out_of_bounds}

          Enum.any?(cells, &cell_occupied?(fleet, &1)) ->
            {:error, :overlaps}

          true ->
            {:ok, fleet ++ [%{type: ship_type, cells: cells, hits: MapSet.new()}]}
        end
    end
  end

  @doc "The number of cells `ship_type` occupies."
  @spec ship_length(atom) :: pos_integer | nil
  def ship_length(ship_type), do: Enum.find_value(@ship_specs, &(&1.type == ship_type && &1.length))

  @doc "True once all 5 required ship types have been placed."
  @spec fleet_complete?(fleet) :: boolean
  def fleet_complete?(fleet) do
    placed = MapSet.new(fleet, & &1.type)
    MapSet.new(@ship_types) |> MapSet.equal?(placed)
  end

  @doc """
  Builds a complete, validly-placed fleet by placing each ship (largest
  first) at a random coordinate/orientation, retrying on rejection. Used
  both by the "randomize" UI action and to generate the computer's own
  fleet - there is no separate placement logic for the AI.
  """
  @spec random_fleet() :: fleet
  def random_fleet do
    @ship_specs
    |> Enum.sort_by(& &1.length, :desc)
    |> Enum.reduce([], fn spec, fleet -> place_randomly(fleet, spec.type) end)
  end

  defp place_randomly(fleet, ship_type, attempts_left \\ 200)

  defp place_randomly(_fleet, ship_type, 0) do
    # Pathologically unlucky RNG run - start this ship's placement over
    # from an empty fleet rather than looping forever. In practice, a
    # 10x10 board with these ship lengths converges almost immediately.
    place_randomly([], ship_type, 200)
  end

  defp place_randomly(fleet, ship_type, attempts_left) do
    coord = {Enum.random(0..(@board_size - 1)), Enum.random(0..(@board_size - 1))}
    orientation = Enum.random([:horizontal, :vertical])

    case place_ship(fleet, ship_type, coord, orientation) do
      {:ok, fleet} -> fleet
      {:error, _reason} -> place_randomly(fleet, ship_type, attempts_left - 1)
    end
  end

  @doc """
  Marks `side`'s fleet as locked in, provided it's complete. Once both
  sides are ready, starts the match - the first turn is a coin flip, so
  neither mode (vs. computer or vs. human) has a built-in first-move
  advantage.
  """
  @spec ready_up(t(), side) :: {:ok, t()} | {:error, :fleet_incomplete}
  def ready_up(%__MODULE__{status: :placing_fleets} = battleship, side) do
    fleet = Map.fetch!(battleship, fleet_field(side))

    if fleet_complete?(fleet) do
      battleship = Map.put(battleship, ready_field(side), true)

      battleship =
        if battleship.player_ready? and battleship.opponent_ready? do
          %{battleship | status: Enum.random([:player_turn, :opponent_turn])}
        else
          battleship
        end

      {:ok, battleship}
    else
      {:error, :fleet_incomplete}
    end
  end

  @doc """
  Resolves `side` firing at `coord`. Validates it's `side`'s turn and
  that cell hasn't already been shot, records a hit/miss/sunk against
  the opponent's fleet, and either declares a win (every opponent ship
  fully sunk) or flips whose turn it is. Turns strictly alternate one
  shot at a time - a hit does not grant a bonus shot.
  """
  @spec fire(t(), side, coord) ::
          {:ok, %{result: shot_result, ship_type: atom | nil}, t()}
          | {:error, :not_your_turn | :already_shot | :game_over}
  def fire(%__MODULE__{} = battleship, side, coord) do
    cond do
      battleship.status not in [:player_turn, :opponent_turn] ->
        {:error, :game_over}

      battleship.status != turn_status(side) ->
        {:error, :not_your_turn}

      Map.has_key?(Map.fetch!(battleship, shots_field(side)), format_coord(coord)) ->
        {:error, :already_shot}

      true ->
        resolve_shot(battleship, side, coord)
    end
  end

  defp resolve_shot(battleship, side, coord) do
    opponent_fleet_field = fleet_field(opposite(side))
    opponent_fleet = Map.fetch!(battleship, opponent_fleet_field)

    case Enum.find_index(opponent_fleet, &(coord in &1.cells)) do
      nil ->
        outcome = %{result: :miss, ship_type: nil}
        battleship = record_shot(battleship, side, coord, "miss") |> flip_turn(side)
        {:ok, outcome, battleship}

      ship_index ->
        ship = Enum.at(opponent_fleet, ship_index)
        hits = MapSet.put(ship.hits, coord)
        ship = %{ship | hits: hits}
        opponent_fleet = List.replace_at(opponent_fleet, ship_index, ship)

        sunk? = MapSet.size(hits) == length(ship.cells)
        result = if sunk?, do: :sunk, else: :hit

        battleship =
          battleship
          |> Map.put(opponent_fleet_field, opponent_fleet)
          |> record_shot(side, coord, Atom.to_string(result))

        battleship =
          if all_sunk?(opponent_fleet) do
            %{battleship | status: won_status(side)}
          else
            flip_turn(battleship, side)
          end

        {:ok, %{result: result, ship_type: ship.type}, battleship}
    end
  end

  defp all_sunk?(fleet), do: Enum.all?(fleet, &(MapSet.size(&1.hits) == length(&1.cells)))

  defp record_shot(battleship, side, coord, result) do
    field = shots_field(side)
    shots = Map.fetch!(battleship, field)
    Map.put(battleship, field, Map.put(shots, format_coord(coord), result))
  end

  defp flip_turn(battleship, side), do: %{battleship | status: turn_status(opposite(side))}

  defp opposite(:player), do: :opponent
  defp opposite(:opponent), do: :player

  defp fleet_field(:player), do: :player_fleet
  defp fleet_field(:opponent), do: :opponent_fleet

  defp ready_field(:player), do: :player_ready?
  defp ready_field(:opponent), do: :opponent_ready?

  defp shots_field(:player), do: :player_shots
  defp shots_field(:opponent), do: :opponent_shots

  defp turn_status(:player), do: :player_turn
  defp turn_status(:opponent), do: :opponent_turn

  defp won_status(:player), do: :player_won
  defp won_status(:opponent), do: :opponent_won

  defp ship_cells({col, row}, :horizontal, length),
    do: for(i <- 0..(length - 1), do: {col + i, row})

  defp ship_cells({col, row}, :vertical, length),
    do: for(i <- 0..(length - 1), do: {col, row + i})

  defp on_board?({col, row}), do: col in 0..(@board_size - 1) and row in 0..(@board_size - 1)

  defp cell_occupied?(fleet, cell), do: Enum.any?(fleet, &(cell in &1.cells))

  ## JSON (de)serialization - shared by both persistence paths (the
  ## vs-computer Postgres row and the vs-human match's jsonb column), so it
  ## lives here rather than being duplicated in each caller the way Poker's
  ## own hand-rolled (de)serializers are (Poker only ever has one caller).
  ## Coordinates already serialize directly to "B4"-style strings, so -
  ## unlike Poker's seats/hand - nothing here needs integer-key or
  ## tuple-key gymnastics to survive a jsonb round trip.

  @doc "Encodes a match as a plain, jsonb-storable map."
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = battleship) do
    %{
      "player_fleet" => Enum.map(battleship.player_fleet, &ship_to_json/1),
      "opponent_fleet" => Enum.map(battleship.opponent_fleet, &ship_to_json/1),
      "player_ready" => battleship.player_ready?,
      "opponent_ready" => battleship.opponent_ready?,
      "player_shots" => battleship.player_shots,
      "opponent_shots" => battleship.opponent_shots,
      "status" => Atom.to_string(battleship.status)
    }
  end

  defp ship_to_json(ship) do
    %{
      "type" => Atom.to_string(ship.type),
      "cells" => Enum.map(ship.cells, &format_coord/1),
      "hits" => ship.hits |> MapSet.to_list() |> Enum.map(&format_coord/1)
    }
  end

  @doc """
  Decodes a match from its jsonb-storable map (see `to_json/1`), or
  returns a fresh match for `nil` (a game/match row that hasn't started
  placement yet). Callers that deserialize this at process boot time
  (i.e. a GenServer's `init/1`) should call `Code.ensure_loaded!(#{inspect(__MODULE__)})`
  first, exactly like `HighSociety.Games.PokerTable` does for `Poker` -
  otherwise `String.to_existing_atom/1` below can raise on a genuine
  restart if this module's own atoms haven't been interned yet.
  """
  @spec from_json(map() | nil) :: t()
  def from_json(nil), do: %__MODULE__{}

  def from_json(%{} = json) do
    %__MODULE__{
      player_fleet: Enum.map(json["player_fleet"] || [], &ship_from_json/1),
      opponent_fleet: Enum.map(json["opponent_fleet"] || [], &ship_from_json/1),
      player_ready?: json["player_ready"] || false,
      opponent_ready?: json["opponent_ready"] || false,
      player_shots: json["player_shots"] || %{},
      opponent_shots: json["opponent_shots"] || %{},
      status: String.to_existing_atom(json["status"] || "placing_fleets")
    }
  end

  defp ship_from_json(%{"type" => type, "cells" => cells, "hits" => hits}) do
    %{
      type: String.to_existing_atom(type),
      cells: Enum.map(cells, &coord!/1),
      hits: hits |> Enum.map(&coord!/1) |> MapSet.new()
    }
  end

  defp coord!(str) do
    {:ok, coord} = parse_coord(str)
    coord
  end
end
