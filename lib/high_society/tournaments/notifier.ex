defmodule HighSociety.Tournaments.Notifier do
  use HighSocietyWeb, :verified_routes

  import Swoosh.Email
  require Logger

  alias HighSociety.Accounts.User
  alias HighSociety.Mailer
  alias HighSociety.Tournaments.PokerTournament
  alias HighSociety.Tournaments.PokerTournamentEntry

  @doc """
  Confirms a tournament registration (or an update to one) by email.
  Logs and swallows delivery failures rather than failing the
  registration itself - the entry is already saved either way.
  """
  def deliver_registration_confirmation(%User{} = user, %PokerTournamentEntry{} = entry) do
    email =
      new()
      |> to(user.email)
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> subject("You're registered for the High Society poker tournament")
      |> text_body(text_body(entry))

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to deliver tournament registration confirmation to #{user.email}: #{inspect(reason)}"
        )

        :error
    end
  end

  defp text_body(%PokerTournamentEntry{ethereum_address: nil}) do
    """
    You're in! We'll email you here with the tournament schedule and details
    as the date gets closer.

    You didn't provide an Ethereum address for prize payouts. If you'd like
    to add one later, you can update your registration any time before the
    tournament starts.
    """
  end

  defp text_body(%PokerTournamentEntry{ethereum_address: address}) do
    """
    You're in! We'll email you here with the tournament schedule and details
    as the date gets closer.

    Ethereum address on file for prize payouts: #{address}

    Prizes (ETH and High Society NFTs) are sent manually after the
    tournament, not automatically - if this address is wrong, you can
    update it any time before the tournament starts.
    """
  end

  @doc """
  Delivers every entry in `entries` (each with `:user` preloaded) their
  result for `tournament` once it's finished - the champion (1st: ETH +
  an exclusive NFT), runner-up (2nd: ETH), everyone else a thank-you -
  concurrently via `Task.async_stream/3`. This is the app's first
  batch-send; nothing existing to follow, but `Task.async_stream` is the
  primitive `AGENTS.md` recommends for exactly this shape of work. Never
  raises past an individual failure - logs and moves on, same as
  `deliver_registration_confirmation/2`.
  """
  @spec deliver_results(PokerTournament.t(), [PokerTournamentEntry.t()]) :: :ok
  def deliver_results(%PokerTournament{} = tournament, entries) do
    entries
    |> Task.async_stream(&deliver_placement_email(tournament, &1), timeout: :infinity)
    |> Stream.run()

    :ok
  end

  defp deliver_placement_email(
         %PokerTournament{} = tournament,
         %PokerTournamentEntry{user: %User{} = user} = entry
       ) do
    email =
      new()
      |> to(user.email)
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> subject(placement_subject(entry))
      |> text_body(placement_body(tournament, entry))

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to deliver tournament results to #{user.email}: #{inspect(reason)}")
        :error
    end
  end

  defp placement_subject(%PokerTournamentEntry{finish_place: 1}),
    do: "You won the High Society poker tournament!"

  defp placement_subject(%PokerTournamentEntry{finish_place: 2}),
    do: "You took 2nd in the High Society poker tournament"

  defp placement_subject(_entry), do: "Thanks for playing the High Society poker tournament"

  defp placement_body(
         %PokerTournament{} = tournament,
         %PokerTournamentEntry{finish_place: 1} = entry
       ) do
    """
    Congratulations - you won the High Society poker tournament!

    Your prize is $75 in ETH plus an exclusive High Society NFT.
    #{ethereum_address_line(entry)}
    #{kyc_paragraph(tournament, entry)}
    """
  end

  defp placement_body(
         %PokerTournament{} = tournament,
         %PokerTournamentEntry{finish_place: 2} = entry
       ) do
    """
    Nicely played - you finished 2nd in the High Society poker tournament!

    Your prize is $25 in ETH.
    #{ethereum_address_line(entry)}
    #{kyc_paragraph(tournament, entry)}
    """
  end

  defp placement_body(%PokerTournament{name: name}, %PokerTournamentEntry{finish_place: place}) do
    """
    Thanks for playing #{name}!

    You finished in #{ordinal(place)} place. We hope you had a great time -
    keep an eye out for the next one.
    """
  end

  defp ethereum_address_line(%PokerTournamentEntry{ethereum_address: nil}) do
    "You haven't provided an Ethereum address yet - see below for where to add one."
  end

  defp ethereum_address_line(%PokerTournamentEntry{ethereum_address: address}) do
    "Sent manually to the Ethereum address on file: #{address}"
  end

  # KYC ("know your customer") identity verification is a legal
  # requirement before any prize payout, so it can't skip straight to
  # "you're all set" just because an Ethereum address is on file - see
  # HighSociety.Tournaments.PokerTournamentEntry's moduledoc.
  defp kyc_paragraph(%PokerTournament{} = tournament, %PokerTournamentEntry{} = entry) do
    registration_url = url(~p"/tournament/#{tournament.id}/register")

    if kyc_complete?(entry) do
      """
      You've already provided the identity verification info we need to
      process your payout - no further action needed. If any of it was
      wrong, you can still update it here:

      #{registration_url}
      """
    else
      """
      Before we can send your prize, we're required to verify your
      identity (so we can't send payment to a sanctioned or blacklisted
      person or entity) - please provide your legal name, address, and
      date of birth within 7 days of this email at:

      #{registration_url}
      """
    end
  end

  @kyc_fields ~w(first_name last_name address city state zip_code date_of_birth)a

  defp kyc_complete?(entry), do: Enum.all?(@kyc_fields, &(Map.fetch!(entry, &1) not in [nil, ""]))

  defp ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"

  defp ordinal(n) do
    suffix =
      case rem(n, 10) do
        1 -> "st"
        2 -> "nd"
        3 -> "rd"
        _ -> "th"
      end

    "#{n}#{suffix}"
  end
end
