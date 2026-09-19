defmodule HighSociety.Tournaments.NotifierTest do
  use HighSociety.DataCase, async: true

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures
  import Swoosh.TestAssertions

  alias HighSociety.Tournaments.Notifier
  alias HighSociety.Tournaments.PokerTournamentEntry

  setup do
    tournament = tournament_fixture()

    champion =
      entry_fixture(tournament, 1, ethereum_address: "0x" <> String.duplicate("a", 40))

    runner_up = entry_fixture(tournament, 2)
    third_place = entry_fixture(tournament, 3)

    # Drain the login/welcome/registration-confirmation mail each
    # `entry_fixture/2` triggers so `deliver_results/2`'s own assertions
    # below only ever see the placement emails it sends.
    Enum.each([champion, runner_up, third_place], fn entry ->
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")
      assert_email_sent(subject: "You're registered for the High Society poker tournament")
      entry
    end)

    %{tournament: tournament, champion: champion, runner_up: runner_up, third_place: third_place}
  end

  describe "deliver_results/2" do
    test "emails the champion about ETH and an NFT, addressed to their Ethereum address", %{
      tournament: tournament,
      champion: champion
    } do
      Notifier.deliver_results(tournament, [champion])

      assert_email_sent(fn email ->
        email.to == [{"", champion.user.email}] and
          email.subject == "You won the High Society poker tournament!" and
          email.text_body =~ "$75 in ETH" and
          email.text_body =~ "exclusive High Society NFT" and
          email.text_body =~ champion.ethereum_address
      end)
    end

    test "emails the runner-up about ETH, noting no address is on file", %{
      tournament: tournament,
      runner_up: runner_up
    } do
      Notifier.deliver_results(tournament, [runner_up])

      assert_email_sent(fn email ->
        email.to == [{"", runner_up.user.email}] and
          email.subject == "You took 2nd in the High Society poker tournament" and
          email.text_body =~ "$25 in ETH" and
          email.text_body =~ "haven't provided an Ethereum address"
      end)
    end

    test "asks an incomplete-KYC winner to provide it within 7 days, with a link back to the form",
         %{tournament: tournament, runner_up: runner_up} do
      Notifier.deliver_results(tournament, [runner_up])

      assert_email_sent(fn email ->
        email.text_body =~ "within 7 days" and
          email.text_body =~ "verify your\nidentity" and
          email.text_body =~ "/tournament/#{tournament.id}/register"
      end)
    end

    test "tells a complete-KYC winner no further action is needed", %{tournament: tournament} do
      champion =
        entry_fixture(tournament, 1,
          ethereum_address: "0x" <> String.duplicate("a", 40),
          first_name: "Jane",
          last_name: "Doe",
          address: "123 Main St",
          city: "Philadelphia",
          state: "PA",
          zip_code: "19102",
          date_of_birth: ~D[1990-01-15]
        )

      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")
      assert_email_sent(subject: "You're registered for the High Society poker tournament")

      Notifier.deliver_results(tournament, [champion])

      assert_email_sent(fn email ->
        email.text_body =~ "no further action needed" and
          email.text_body =~ "/tournament/#{tournament.id}/register"
      end)
    end

    test "emails everyone else a thank-you with their finish place", %{
      tournament: tournament,
      third_place: third_place
    } do
      Notifier.deliver_results(tournament, [third_place])

      assert_email_sent(fn email ->
        email.to == [{"", third_place.user.email}] and
          email.subject == "Thanks for playing the High Society poker tournament" and
          email.text_body =~ "3rd place"
      end)
    end

    test "sends every entry's email concurrently", %{
      tournament: tournament,
      champion: champion,
      runner_up: runner_up,
      third_place: third_place
    } do
      assert :ok = Notifier.deliver_results(tournament, [champion, runner_up, third_place])

      # Sent via `Task.async_stream/3`, so the 3 emails can arrive in any
      # order - collect all 3 first, then compare as a set.
      subjects =
        for _ <- 1..3 do
          assert_receive {:email, email}
          email.subject
        end

      assert Enum.sort(subjects) ==
               Enum.sort([
                 "You won the High Society poker tournament!",
                 "You took 2nd in the High Society poker tournament",
                 "Thanks for playing the High Society poker tournament"
               ])
    end
  end

  @registration_fields ~w(ethereum_address first_name last_name address city state zip_code date_of_birth)a

  defp entry_fixture(tournament, finish_place, opts \\ []) do
    user = user_fixture()
    scope = HighSociety.Accounts.Scope.for_user(user)
    registration_attrs = opts |> Keyword.take(@registration_fields) |> Map.new()
    {:ok, entry} = HighSociety.Tournaments.register(scope, tournament, registration_attrs)

    {:ok, entry} =
      entry
      |> PokerTournamentEntry.placement_changeset(%{finish_place: finish_place})
      |> Repo.update()

    %{entry | user: user}
  end
end
