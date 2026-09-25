defmodule HighSociety.Tournaments.NotifierTemplatedTest do
  # Mutates the global `:resend_templates` config for the duration of
  # each test (see the `setup` below) - unsafe alongside
  # `NotifierTest`'s own `async: true` tests if this ran in the same
  # module, so it's a separate file instead.
  use HighSociety.DataCase, async: false

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures
  import Swoosh.TestAssertions

  alias HighSociety.Accounts.Scope
  alias HighSociety.Tournaments
  alias HighSociety.Tournaments.Notifier
  alias HighSociety.Tournaments.PokerTournamentEntry

  # `resend_templates` is normally empty in test (see config/config.exs),
  # so both notifier functions below always fall back to their
  # plain-text bodies - these tests configure template ids for the
  # duration of each one, mirroring what prod looks like once a template
  # is actually published, specifically to catch the class of bug that
  # motivated writing this file: Resend matches a template's own
  # `{{{PLACEHOLDER}}}` variables by name *and case*, so a variables map
  # built with the wrong casing sends successfully, looks fine in every
  # assertion that doesn't check the keys themselves, and then silently
  # renders each placeholder as its configured fallback value in the
  # actual email - see `HighSociety.Tournaments.Notifier`'s `deliver/4`
  # moduledoc comment.
  setup do
    previous = Application.get_env(:high_society, :resend_templates, [])

    Application.put_env(:high_society, :resend_templates,
      tournament_registration: "test-registration-template-id",
      tournament_results: "test-results-template-id"
    )

    on_exit(fn ->
      Application.put_env(:high_society, :resend_templates, previous)
    end)

    %{tournament: tournament_fixture()}
  end

  # `user_fixture/1` sends and consumes its own "Confirmation
  # instructions" email (to build a confirmed user) and then, via
  # `Accounts.login_user_by_magic_link/1` confirming a first-time user,
  # a "Welcome to HighSociety!" one - both land in the same mailbox this
  # module's own `assert_email_sent/1` calls read from.
  # `Swoosh.TestAssertions.assert_email_sent/1` given a matcher function
  # checks the *next* unconsumed message, not "any message that
  # matches" - so without draining these two first, a test asserting on
  # the tournament-registration email would actually be asserting on the
  # unrelated confirmation email underneath it, exactly the trap
  # `NotifierTest`'s own `setup` already documents and works around the
  # same way.
  defp confirmed_user_fixture! do
    user = user_fixture()
    assert_email_sent(subject: "Confirmation instructions")
    assert_email_sent(subject: "Welcome to HighSociety!")
    user
  end

  describe "deliver_registration_confirmation/3 with a configured template" do
    test "variables use the exact uppercase keys the template expects, address on file", %{
      tournament: tournament
    } do
      user = confirmed_user_fixture!()
      scope = Scope.for_user(user)

      {:ok, entry} =
        Tournaments.register(scope, tournament, %{
          ethereum_address: "0x" <> String.duplicate("a", 40)
        })

      assert_email_sent(fn email ->
        %{template: %{id: "test-registration-template-id", variables: variables}} =
          email.provider_options

        variables == %{
          "TOURNAMENT_NAME" => tournament.name,
          "ETHEREUM_SECTION" =>
            "Ethereum address on file for prize payouts: <strong>#{entry.ethereum_address}</strong>. " <>
              "Prizes (ETH and High Society NFTs) are sent manually after the tournament, not " <>
              "automatically - if this address is wrong, you can update it any time before the " <>
              "tournament starts."
        }
      end)
    end

    test "variables use the exact uppercase keys the template expects, no address on file", %{
      tournament: tournament
    } do
      user = confirmed_user_fixture!()
      scope = Scope.for_user(user)
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})

      assert_email_sent(fn email ->
        %{template: %{id: "test-registration-template-id", variables: variables}} =
          email.provider_options

        variables["TOURNAMENT_NAME"] == tournament.name and
          variables["ETHEREUM_SECTION"] =~ "haven't provided an Ethereum address"
      end)
    end

    test "HTML-escapes an admin-entered tournament name containing markup" do
      tournament = tournament_fixture(name: "<script>alert(1)</script>")
      user = confirmed_user_fixture!()
      scope = Scope.for_user(user)
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})

      assert_email_sent(fn email ->
        %{template: %{variables: variables}} = email.provider_options
        variables["TOURNAMENT_NAME"] == "&lt;script&gt;alert(1)&lt;/script&gt;"
      end)
    end
  end

  describe "deliver_results/2 with a configured template" do
    test "the champion's variables use the exact uppercase keys the template expects, and HTML content",
         %{tournament: tournament} do
      champion = entry_fixture(tournament, 1, ethereum_address: "0x" <> String.duplicate("a", 40))
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")
      assert_email_sent(subject: "You're registered for the High Society poker tournament")

      Notifier.deliver_results(tournament, [champion])

      assert_email_sent(fn email ->
        %{template: %{id: "test-results-template-id", variables: variables}} =
          email.provider_options

        variables["HEADLINE"] =~ "Won" and
          variables["TOURNAMENT_NAME"] == tournament.name and
          variables["BODY_HTML"] =~ "$75 in ETH" and
          variables["BODY_HTML"] =~ "<p>" and
          map_size(variables) == 3
      end)
    end

    test "sends no html_body or text_body alongside a template, per Swoosh.Adapters.Resend's requirement",
         %{tournament: tournament} do
      third_place = entry_fixture(tournament, 3)
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")
      assert_email_sent(subject: "You're registered for the High Society poker tournament")

      Notifier.deliver_results(tournament, [third_place])

      assert_email_sent(fn email -> is_nil(email.html_body) and is_nil(email.text_body) end)
    end
  end

  defp entry_fixture(tournament, finish_place, opts \\ []) do
    user = user_fixture()
    scope = Scope.for_user(user)

    registration_fields =
      ~w(ethereum_address first_name last_name address city state zip_code date_of_birth)a

    registration_attrs = opts |> Keyword.take(registration_fields) |> Map.new()
    {:ok, entry} = Tournaments.register(scope, tournament, registration_attrs)

    {:ok, entry} =
      entry
      |> PokerTournamentEntry.placement_changeset(%{finish_place: finish_place})
      |> HighSociety.Repo.update()

    %{entry | user: user}
  end
end
