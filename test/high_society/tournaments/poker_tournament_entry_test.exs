defmodule HighSociety.Tournaments.PokerTournamentEntryTest do
  use HighSociety.DataCase, async: true

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Accounts.Scope
  alias HighSociety.Tournaments
  alias HighSociety.Tournaments.PokerTournamentEntry

  setup do
    tournament = tournament_fixture()
    user = user_fixture()
    %{tournament: tournament, scope: Scope.for_user(user)}
  end

  describe "changeset/2 - KYC fields" do
    test "all optional - a bare registration with none of them is valid", %{
      scope: scope,
      tournament: tournament
    } do
      changeset = PokerTournamentEntry.changeset(entry(scope, tournament), %{})
      assert changeset.valid?
    end

    test "accepts a full set of KYC fields", %{scope: scope, tournament: tournament} do
      attrs = %{
        "first_name" => "Jane",
        "last_name" => "Doe",
        "address" => "123 Main St",
        "city" => "Philadelphia",
        "state" => "PA",
        "zip_code" => "19102",
        "date_of_birth" => "1990-01-15"
      }

      changeset = PokerTournamentEntry.changeset(entry(scope, tournament), attrs)
      assert changeset.valid?
      assert get_change(changeset, :date_of_birth) == ~D[1990-01-15]
    end

    test "blank strings are treated as not provided, same as the Ethereum address", %{
      scope: scope,
      tournament: tournament
    } do
      attrs = %{"first_name" => "  ", "city" => "", "state" => "   "}
      changeset = PokerTournamentEntry.changeset(entry(scope, tournament), attrs)

      assert get_change(changeset, :first_name) == nil
      assert get_change(changeset, :city) == nil
      assert get_change(changeset, :state) == nil
    end

    test "rejects a date of birth in the future", %{scope: scope, tournament: tournament} do
      future = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      changeset =
        PokerTournamentEntry.changeset(entry(scope, tournament), %{"date_of_birth" => future})

      assert %{date_of_birth: ["can't be in the future"]} = errors_on(changeset)
    end

    test "rejects a date of birth under 18 years ago", %{scope: scope, tournament: tournament} do
      too_young = Date.utc_today() |> Date.add(-365 * 10) |> Date.to_iso8601()

      changeset =
        PokerTournamentEntry.changeset(entry(scope, tournament), %{"date_of_birth" => too_young})

      assert %{date_of_birth: ["must be at least 18 years old"]} = errors_on(changeset)
    end

    test "accepts a date of birth exactly 18 years ago today", %{
      scope: scope,
      tournament: tournament
    } do
      today = Date.utc_today()
      exactly_18 = %{today | year: today.year - 18} |> Date.to_iso8601()

      changeset =
        PokerTournamentEntry.changeset(entry(scope, tournament), %{"date_of_birth" => exactly_18})

      assert changeset.valid?
    end
  end

  describe "encryption at rest" do
    test "KYC fields round-trip through the database correctly decrypted, and are not stored as plaintext",
         %{scope: scope, tournament: tournament} do
      attrs = %{
        "ethereum_address" => "0x" <> String.duplicate("a", 40),
        "first_name" => "Jane",
        "last_name" => "Doe",
        "address" => "123 Main St",
        "city" => "Philadelphia",
        "state" => "PA",
        "zip_code" => "19102",
        "date_of_birth" => "1990-01-15"
      }

      {:ok, entry} = Tournaments.register(scope, tournament, attrs)

      reloaded = Repo.get!(PokerTournamentEntry, entry.id)
      assert reloaded.first_name == "Jane"
      assert reloaded.last_name == "Doe"
      assert reloaded.address == "123 Main St"
      assert reloaded.city == "Philadelphia"
      assert reloaded.state == "PA"
      assert reloaded.zip_code == "19102"
      assert reloaded.date_of_birth == ~D[1990-01-15]

      # The raw bytes on disk must never contain the plaintext - read via
      # a raw SQL query to bypass Ecto's automatic decryption entirely.
      %{rows: [[raw_first_name, raw_last_name, raw_dob]]} =
        Repo.query!(
          "SELECT first_name, last_name, date_of_birth FROM poker_tournament_entries WHERE id = $1",
          [entry.id]
        )

      assert is_binary(raw_first_name)
      refute raw_first_name =~ "Jane"
      refute raw_last_name =~ "Doe"
      refute raw_dob =~ "1990"
    end
  end

  defp entry(%Scope{} = scope, tournament) do
    Tournaments.get_entry(scope, tournament) ||
      %PokerTournamentEntry{user_id: scope.user.id, tournament_id: tournament.id}
  end
end
