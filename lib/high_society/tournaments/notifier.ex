defmodule HighSociety.Tournaments.Notifier do
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

  defp placement_body(_tournament, %PokerTournamentEntry{finish_place: 1, ethereum_address: nil}) do
    """
    Congratulations - you won the High Society poker tournament!

    Your prize is $75 in ETH plus an exclusive High Society NFT, sent
    manually after the tournament. You didn't provide an Ethereum address
    for the payout - reply to this email (or update your registration, if
    it's still open) with one and we'll get it sent over.
    """
  end

  defp placement_body(_tournament, %PokerTournamentEntry{
         finish_place: 1,
         ethereum_address: address
       }) do
    """
    Congratulations - you won the High Society poker tournament!

    Your prize is $75 in ETH plus an exclusive High Society NFT, sent
    manually to the Ethereum address on file:

    #{address}

    If that address is wrong, reply to this email and we'll get it
    corrected before sending your prize.
    """
  end

  defp placement_body(_tournament, %PokerTournamentEntry{finish_place: 2, ethereum_address: nil}) do
    """
    Nicely played - you finished 2nd in the High Society poker tournament!

    Your prize is $25 in ETH, sent manually after the tournament. You
    didn't provide an Ethereum address for the payout - reply to this
    email (or update your registration, if it's still open) with one and
    we'll get it sent over.
    """
  end

  defp placement_body(_tournament, %PokerTournamentEntry{
         finish_place: 2,
         ethereum_address: address
       }) do
    """
    Nicely played - you finished 2nd in the High Society poker tournament!

    Your prize is $25 in ETH, sent manually to the Ethereum address on
    file:

    #{address}

    If that address is wrong, reply to this email and we'll get it
    corrected before sending your prize.
    """
  end

  defp placement_body(%PokerTournament{name: name}, %PokerTournamentEntry{finish_place: place}) do
    """
    Thanks for playing #{name}!

    You finished in #{ordinal(place)} place. We hope you had a great time -
    keep an eye out for the next one.
    """
  end

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
