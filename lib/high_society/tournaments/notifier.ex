defmodule HighSociety.Tournaments.Notifier do
  use HighSocietyWeb, :verified_routes

  import Swoosh.Email
  require Logger

  alias HighSociety.Accounts.User
  alias HighSociety.Mailer
  alias HighSociety.Tournaments.PokerTournament
  alias HighSociety.Tournaments.PokerTournamentEntry

  # Sends `email` (already carrying `to`/`from`/`subject`) through a
  # Resend dashboard Template (see `priv/resend_templates/` for the HTML
  # pasted in when creating each one, and `Swoosh.Adapters.Resend`'s
  # "Using Templates" moduledoc section for how `template_key`'s id +
  # `variables` become the actual API request) whenever one's configured
  # for `template_key` - falling back to the plain-text `body` otherwise,
  # so dev/test and any environment before a template's been created in
  # Resend still send a readable email instead of a blank one no
  # non-Resend adapter could ever render from a template id alone. Logs
  # and swallows delivery failures rather than raising - every caller
  # already has its own data saved (an entry, a placement) regardless of
  # whether the email about it actually goes out.
  #
  # `variables`' keys must match the template's own `{{{PLACEHOLDER}}}`
  # names *and case* exactly - Resend does not lowercase/normalize either
  # side before comparing, so e.g. `"TOURNAMENT_NAME" => ...` here has to
  # line up with `{{{TOURNAMENT_NAME}}}` in the HTML and the
  # "TOURNAMENT_NAME" variable name entered in Resend's dashboard, not
  # `:tournament_name` or any other casing. A mismatch fails silently -
  # the placeholder just renders as whatever fallback value was
  # configured for it in Resend, with no error anywhere in this app to
  # catch it.
  defp deliver(email, template_key, variables, body) do
    email =
      case Keyword.get(Application.get_env(:high_society, :resend_templates, []), template_key) do
        nil ->
          text_body(email, body)

        template_id ->
          put_provider_option(email, :template, %{id: template_id, variables: variables})
      end

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        [{_name, recipient} | _] = email.to

        Logger.error(
          "Failed to deliver #{inspect(email.subject)} to #{inspect(recipient)}: #{inspect(reason)}"
        )

        :error
    end
  end

  @doc """
  Confirms a tournament registration (or an update to one) by email.
  Logs and swallows delivery failures rather than failing the
  registration itself - the entry is already saved either way.
  """
  def deliver_registration_confirmation(
        %User{} = user,
        %PokerTournament{} = tournament,
        %PokerTournamentEntry{} = entry
      ) do
    email =
      new()
      |> to(user.email)
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> subject("You're registered for the High Society poker tournament")

    variables = %{
      "TOURNAMENT_NAME" => html_escape(tournament.name),
      "ETHEREUM_SECTION" => ethereum_section_html(entry)
    }

    deliver(email, :tournament_registration, variables, text_body(entry))
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

  defp ethereum_section_html(%PokerTournamentEntry{ethereum_address: nil}) do
    "You haven't provided an Ethereum address for prize payouts yet. If you'd like to add " <>
      "one later, you can update your registration any time before the tournament starts."
  end

  defp ethereum_section_html(%PokerTournamentEntry{ethereum_address: address}) do
    "Ethereum address on file for prize payouts: <strong>#{html_escape(address)}</strong>. " <>
      "Prizes (ETH and High Society NFTs) are sent manually after the tournament, not " <>
      "automatically - if this address is wrong, you can update it any time before the " <>
      "tournament starts."
  end

  @doc """
  Delivers every entry in `entries` (each with `:user` preloaded) their
  result for `tournament` once it's finished - the champion (1st: ETH +
  an exclusive NFT), runner-up (2nd: ETH), everyone else a thank-you -
  concurrently via `Task.async_stream/3`. This is the app's first
  batch-send; nothing existing to follow, but `Task.async_stream` is the
  primitive `AGENTS.md` recommends for exactly this shape of work. Never
  raises past an individual failure - logs and moves on, same as
  `deliver_registration_confirmation/3`.
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

    variables = %{
      "HEADLINE" => placement_headline(entry),
      "TOURNAMENT_NAME" => html_escape(tournament.name),
      "BODY_HTML" => placement_body_html(tournament, entry)
    }

    deliver(email, :tournament_results, variables, placement_body(tournament, entry))
  end

  defp placement_subject(%PokerTournamentEntry{finish_place: 1}),
    do: "You won the High Society poker tournament!"

  defp placement_subject(%PokerTournamentEntry{finish_place: 2}),
    do: "You took 2nd in the High Society poker tournament"

  defp placement_subject(_entry), do: "Thanks for playing the High Society poker tournament"

  defp placement_headline(%PokerTournamentEntry{finish_place: 1}), do: "You Won! \u{1F3C6}"
  defp placement_headline(%PokerTournamentEntry{finish_place: 2}), do: "2nd Place!"
  defp placement_headline(_entry), do: "Thanks for Playing"

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

  defp placement_body_html(
         %PokerTournament{} = tournament,
         %PokerTournamentEntry{finish_place: 1} = entry
       ) do
    """
    <p>Congratulations — you won the High Society poker tournament!</p>
    #{prize_box_html("$75 in ETH plus one exclusive High Society NFT.")}
    <p>#{ethereum_address_line_html(entry)}</p>
    #{kyc_paragraph_html(tournament, entry)}
    """
  end

  defp placement_body_html(
         %PokerTournament{} = tournament,
         %PokerTournamentEntry{finish_place: 2} = entry
       ) do
    """
    <p>Nicely played — you finished 2nd in the High Society poker tournament!</p>
    #{prize_box_html("$25 in ETH.")}
    <p>#{ethereum_address_line_html(entry)}</p>
    #{kyc_paragraph_html(tournament, entry)}
    """
  end

  defp placement_body_html(%PokerTournament{name: name}, %PokerTournamentEntry{
         finish_place: place
       }) do
    """
    <p>Thanks for playing #{html_escape(name)}!</p>
    <p>You finished in #{ordinal(place)} place. We hope you had a great time — keep an eye out for the next one.</p>
    """
  end

  defp prize_box_html(text) do
    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#fdf6e3; border-radius:8px; margin:8px 0 20px 0;">
      <tr>
        <td style="padding:16px 20px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#78350f;">
          <strong>Your prize:</strong> #{text}
        </td>
      </tr>
    </table>
    """
  end

  defp ethereum_address_line(%PokerTournamentEntry{ethereum_address: nil}) do
    "You haven't provided an Ethereum address yet - see below for where to add one."
  end

  defp ethereum_address_line(%PokerTournamentEntry{ethereum_address: address}) do
    "Sent manually to the Ethereum address on file: #{address}"
  end

  defp ethereum_address_line_html(%PokerTournamentEntry{ethereum_address: nil}) do
    "You haven't provided an Ethereum address yet — see below for where to add one."
  end

  defp ethereum_address_line_html(%PokerTournamentEntry{ethereum_address: address}) do
    "Sent manually to the Ethereum address on file: <strong>#{html_escape(address)}</strong>"
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

  defp kyc_paragraph_html(%PokerTournament{} = tournament, %PokerTournamentEntry{} = entry) do
    registration_url = url(~p"/tournament/#{tournament.id}/register")

    if kyc_complete?(entry) do
      """
      <p>You've already provided the identity verification info we need to process your
      payout — no further action needed. If any of it was wrong, you can still update it
      <a href="#{registration_url}" style="color:#0e3f73;">here</a>.</p>
      """
    else
      """
      <p>Before we can send your prize, we're required to verify your identity (so we can't
      send payment to a sanctioned or blacklisted person or entity) — please provide your
      legal name, address, and date of birth within 7 days of this email at
      <a href="#{registration_url}" style="color:#0e3f73;">this link</a>.</p>
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

  # Every value spliced into one of the `_html` bodies above ultimately
  # lands in an HTML email via a Resend Template's raw (`{{{...}}}`, not
  # HTML-escaped) variable substitution - `tournament.name` is
  # admin-entered, but `entry.ethereum_address` is user-supplied, so
  # nothing here can skip escaping just because it "should" be plain
  # text already.
  defp html_escape(string),
    do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
