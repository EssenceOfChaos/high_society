defmodule HighSocietyWeb.LegalLive do
  @moduledoc """
  Static legal/compliance pages - Terms and Conditions, Privacy Policy,
  Cookies Policy, Responsible Gaming Statement, Age Restriction, and the
  Poker Tournament's Official Rules - picked by `@live_action` (see the
  routes in the router). These are plain informational content with no
  state beyond the current scope (for the shared layout's nav), so one
  LiveView with a page per action is simpler than several near-identical
  modules.
  """
  use HighSocietyWeb, :live_view

  @last_updated "September 17, 2026"
  @tournament_rules_updated "September 18, 2026"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, page_title(socket.assigns.live_action))}
  end

  defp page_title(:terms), do: "Terms and Conditions"
  defp page_title(:privacy), do: "Privacy Policy"
  defp page_title(:cookies), do: "Cookies Policy"
  defp page_title(:responsible_gaming), do: "Responsible Gaming Statement"
  defp page_title(:age_restriction), do: "Age Restriction"
  defp page_title(:tournament_rules), do: "Official Tournament Rules"

  @impl true
  def render(%{live_action: :terms} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Terms and Conditions" updated_on={last_updated()}>
        <p>
          These Terms and Conditions ("Terms") govern your access to and use of High Society
          (the "Service"). By creating an account or using the Service, you agree to these
          Terms. If you do not agree, please do not use the Service.
        </p>

        <h2>Eligibility</h2>
        <p>
          You must be at least 18 years old to create an account or use the Service. See our
          <.link navigate={~p"/age-restriction"} class="link">Age Restriction</.link>
          page for details. By using the Service, you represent that you meet this requirement.
        </p>

        <h2>Tokens</h2>
        <p>
          High Society awards a closed-loop virtual currency called Tokens for play within the
          Service. Tokens:
        </p>
        <ul>
          <li>have no cash value and cannot be purchased with real money;</li>
          <li>
            cannot be redeemed, exchanged, sold, or transferred for money, goods, or anything of
            value outside the Service;
          </li>
          <li>are awarded as a starting stake or won through gameplay; and</li>
          <li>
            may be adjusted, reset, or removed at our discretion, including to correct errors or
            prevent abuse.
          </li>
        </ul>

        <h2>Your Account</h2>
        <p>
          You're responsible for maintaining accurate account information and for activity that
          happens under your account. We may suspend or terminate accounts that violate these
          Terms, attempt to circumvent the age requirement above, or abuse the Service.
        </p>

        <h2>Acceptable Use</h2>
        <p>When using the Service, you agree not to:</p>
        <ul>
          <li>cheat, exploit bugs, or use automation/bots to play on your behalf;</li>
          <li>harass, threaten, or abuse other players, including through display names; or</li>
          <li>attempt to access another user's account or circumvent account restrictions.</li>
        </ul>

        <h2>Multiplayer Conduct</h2>
        <p>
          Poker and Battleship seat you with other real players. Play fairly and treat other
          players with respect — the same rules above apply at the table.
        </p>

        <h2>Intellectual Property</h2>
        <p>
          The Service, including its design, graphics, and game content, is owned by High
          Society and protected by intellectual property law. You may not copy, modify, or
          distribute it without permission.
        </p>

        <h2>Disclaimer of Warranties</h2>
        <p>
          The Service is provided "as is" without warranties of any kind. We don't guarantee
          uninterrupted, error-free, or continuously available play.
        </p>

        <h2>Limitation of Liability</h2>
        <p>
          Because Tokens have no cash value, using the Service carries no risk of monetary loss
          through Token play. To the fullest extent permitted by law, High Society is not liable
          for any indirect, incidental, or consequential damages arising from your use of the
          Service.
        </p>

        <h2>Changes</h2>
        <p>
          We may update these Terms from time to time. We'll update the date at the top of this
          page when we do. Continued use of the Service after a change means you accept the
          updated Terms.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about these Terms? Reach out through our
          <.link navigate={~p"/support"} class="link">Support</.link>
          page.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  def render(%{live_action: :privacy} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Privacy Policy" updated_on={last_updated()}>
        <p>
          This Privacy Policy explains what information High Society collects, how we use it,
          and the choices you have.
        </p>

        <h2>Information We Collect</h2>
        <ul>
          <li>
            <strong>Email address</strong>
            — used to sign you in via a magic link and to identify your account.
          </li>
          <li>
            <strong>Display name</strong>
            — optional, chosen by you, shown at multiplayer tables and on leaderboards instead
            of your email.
          </li>
          <li>
            <strong>Gameplay data</strong>
            — your Token balance, bets, and game/transaction history, so your progress and
            balance are saved between visits.
          </li>
          <li>
            <strong>Tournament identity verification data</strong>
            — optional, and only ever needed if you place 1st or 2nd in a poker tournament: an
            Ethereum address, plus legal name, address, and date of birth, collected solely to
            verify your identity before sending a prize (so we're not paying a sanctioned or
            blacklisted person or entity - see the
            <.link navigate={~p"/tournament/rules"} class="link">Official Tournament Rules</.link>
            ). Encrypted at rest, unlike anything else in this list.
          </li>
          <li>
            <strong>Technical data</strong>
            — standard web request information (such as IP address and browser type) used for
            security and troubleshooting.
          </li>
          <li>
            <strong>Analytics data</strong>
            — we use Google Analytics to see which pages are viewed and where traffic comes
            from, so we can improve the Service.
          </li>
        </ul>
        <p>
          Your theme preference (light/dark) is stored only in your browser's local storage and
          is never sent to us. See our
          <.link navigate={~p"/cookies"} class="link">Cookies Policy</.link>
          for more on what we store in your browser, including Google Analytics.
        </p>

        <h2>How We Use Information</h2>
        <p>We use the information above to:</p>
        <ul>
          <li>operate and maintain the Service, including signing you in;</li>
          <li>track Token balances, game history, and leaderboards;</li>
          <li>respond to support requests; and</li>
          <li>detect and prevent abuse of the Service.</li>
        </ul>

        <h2>How We Share Information</h2>
        <p>
          We do not sell your personal information. We may share it with service providers who
          help us operate the Service — for example, delivering login emails, or Google
          Analytics for traffic and usage insights (governed by
          <span class="font-medium">policies.google.com/privacy</span>
          ) — or when required by law.
        </p>

        <h2>Data Retention</h2>
        <p>
          We retain account information for as long as your account is active. Token transaction
          records are kept as an append-only ledger to preserve the integrity of balances and
          leaderboards.
        </p>

        <h2>Your Choices</h2>
        <p>
          You can update your display name and email at any time from <.link
            navigate={~p"/users/settings"}
            class="link"
          >Settings</.link>. To request account
          deletion, contact us through <.link navigate={~p"/support"} class="link">Support</.link>.
        </p>

        <h2>Children's Privacy</h2>
        <p>
          The Service is not directed to anyone under 18 (see our
          <.link navigate={~p"/age-restriction"} class="link">Age Restriction</.link>
          page) and we do not knowingly collect information from minors.
        </p>

        <h2>Security</h2>
        <p>
          We take reasonable measures to protect your information, but no method of transmission
          or storage is perfectly secure.
        </p>

        <h2>Changes</h2>
        <p>
          We may update this Policy from time to time. We'll update the date at the top of this
          page when we do.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about this Policy? Reach out through our
          <.link navigate={~p"/support"} class="link">Support</.link>
          page.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  def render(%{live_action: :cookies} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Cookies Policy" updated_on={last_updated()}>
        <p>
          Cookies are small pieces of data websites store in your browser. This page explains
          how High Society uses them.
        </p>

        <h2>What We Use</h2>
        <ul>
          <li>
            <strong>Essential session cookie</strong>
            — keeps you signed in and is required for the Service to work. Without it, you can't
            stay logged in.
          </li>
          <li>
            <strong>Theme preference</strong>
            — your light/dark/system choice is stored in your browser's local storage, not a
            cookie, and is never sent to us.
          </li>
          <li>
            <strong>Google Analytics</strong>
            — we use Google Analytics to understand how visitors use the Service (for example,
            which pages are viewed and general traffic sources). It sets cookies such as
            <code>_ga</code>
            to distinguish visitors. See <span class="font-medium">policies.google.com/privacy</span>
            for how Google handles this data, and the
            <span class="font-medium">Google Analytics Opt-out Browser Add-on</span>
            if you'd like to opt out.
          </li>
        </ul>
        <p>
          High Society enforces a strict content security policy that only allows scripts and
          styles to load from our own domain and Google Analytics — we don't load any other
          third-party advertising or tracking scripts.
        </p>

        <h2>Managing Cookies</h2>
        <p>
          You can control or delete cookies through your browser settings. Blocking the
          essential session cookie will prevent you from signing in; blocking analytics cookies
          won't affect your ability to use the Service.
        </p>

        <h2>Changes</h2>
        <p>
          We may update this Policy from time to time. We'll update the date at the top of this
          page when we do.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about this Policy? Reach out through our
          <.link navigate={~p"/support"} class="link">Support</.link>
          page.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  def render(%{live_action: :responsible_gaming} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Responsible Gaming Statement" updated_on={last_updated()}>
        <p>
          High Society's games are modeled on classic casino games for entertainment. Tokens are
          a free, closed-loop rewards currency with no cash value — they can't be purchased with
          real money or redeemed for money, goods, or anything of value. No real-money wagering
          happens on High Society.
        </p>

        <h2>Play Responsibly</h2>
        <p>
          Even without money at stake, casino-style games are designed to be engaging, so we
          encourage healthy habits:
        </p>
        <ul>
          <li>set a time limit for your sessions and take breaks;</li>
          <li>treat Token wins and losses as part of a game, not a measure of real-world value;</li>
          <li>play because it's fun, not to chase a streak; and</li>
          <li>stop if it stops feeling fun.</li>
        </ul>

        <h2>Signs to Watch For</h2>
        <p>
          If playing starts to feel compulsive, or is affecting your sleep, work, or
          relationships, take a step back.
        </p>

        <h2>Support Resources</h2>
        <p>
          If gambling more broadly — including for real money elsewhere — is a concern for you
          or someone you know, free, confidential help is available 24/7 from the National
          Council on Problem Gambling: call or text 1-800-522-4700, or visit <span class="font-medium">ncpgambling.org</span>.
        </p>

        <h2>Taking a Break</h2>
        <p>
          If you'd like help pausing or closing your account, contact us through
          <.link navigate={~p"/support"} class="link">Support</.link>
          and we'll assist you.
        </p>

        <h2>Age Requirement</h2>
        <p>
          High Society is only available to users 18 and older. See our
          <.link navigate={~p"/age-restriction"} class="link">Age Restriction</.link>
          page for details.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  def render(%{live_action: :age_restriction} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Age Restriction" updated_on={last_updated()}>
        <div class="flex items-center gap-4 rounded-box border border-base-300 bg-base-200 p-4">
          <span class="flex size-14 shrink-0 items-center justify-center rounded-full bg-primary text-xl font-bold text-primary-content">
            18+
          </span>
          <p class="text-base-content">
            You must be at least <strong>18 years old</strong>
            to create an account or use High Society.
          </p>
        </div>

        <h2>Why We Have This Rule</h2>
        <p>
          High Society's games are modeled on classic casino games. Regardless of whether Tokens
          have any cash value (they don't — see our
          <.link navigate={~p"/terms"} class="link">Terms</.link>
          and
          <.link navigate={~p"/responsible-gaming"} class="link">Responsible Gaming Statement</.link>
          ), we restrict the Service to adults.
        </p>

        <h2>Verification</h2>
        <p>
          By registering, you represent and warrant that you're 18 or older. We may ask for
          proof of age if we have reason to believe an account belongs to a minor, and we'll
          suspend or terminate any account that doesn't meet this requirement.
        </p>

        <h2>Parents and Guardians</h2>
        <p>
          If you believe a minor has created an account, please contact us through
          <.link navigate={~p"/support"} class="link">Support</.link>
          so we can investigate and remove it.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  def render(%{live_action: :tournament_rules} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.legal_page title="Official Tournament Rules" updated_on={tournament_rules_updated()}>
        <div class="flex items-start gap-3 rounded-box border border-primary/30 bg-primary/10 p-4">
          <.icon
            name="hero-megaphone"
            class="mt-0.5 size-6 shrink-0 text-primary [[data-theme=dark]_&]:text-secondary"
          />
          <p class="font-semibold text-base-content">
            NO PURCHASE OR PAYMENT OF ANY KIND IS NECESSARY TO ENTER OR WIN THIS TOURNAMENT.
            A PURCHASE WILL NOT INCREASE YOUR CHANCES OF WINNING.
          </p>
        </div>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-identification"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 1. Eligibility
        </h2>
        <p>
          The High Society Poker Tournament (the "Tournament") is open only to legal residents
          of jurisdictions where online sweepstakes are permitted by law. Residents of the US
          states of Washington and Idaho, and residents of Cuba, Iran, North Korea, Sudan,
          Syria, and China, are strictly excluded from participating. Participants must be at
          least <strong>18 years old</strong>
          at the time of entry — see our
          <.link navigate={~p"/age-restriction"} class="link">Age Restriction</.link>
          page. Void where prohibited or restricted by law.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-building-office"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 2. Sponsor
        </h2>
        <p>The Tournament is sponsored by High Society ("Sponsor").</p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-document-check"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 3. Agreement to Rules
        </h2>
        <p>
          By registering for or participating in a Tournament, you agree to be fully and
          unconditionally bound by these Rules, and you represent and warrant that you meet the
          eligibility requirements set forth herein.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-calendar"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 4. Tournament Period &amp; Entry
        </h2>
        <p>
          Each Tournament's date and time are announced on the
          <.link navigate={~p"/tournament"} class="link">Tournament</.link>
          page ahead of time. Entry is completely free of charge. No real money or
          cryptocurrency may be deposited, wagered, or used to buy into any Tournament — every
          player starts with the same number of tournament chips, which have no cash value and
          exist only for the Tournament itself.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon name="hero-trophy" class="size-5 text-primary [[data-theme=dark]_&]:text-secondary" />
          5. Prize &amp; Odds of Winning
        </h2>
        <p>One (1) First Place winner and one (1) Second Place winner will be selected:</p>
        <ul>
          <li>
            <strong>First Place:</strong>
            $75 USD worth of Ethereum (ETH), plus one (1) exclusive High Society NFT.
          </li>
          <li>
            <strong>Second Place:</strong> $25 USD worth of Ethereum (ETH).
          </li>
        </ul>
        <p>
          The exact amount of ETH transferred will be calculated based on the fair market value
          of ETH at the time the prize is sent. The odds of winning depend entirely on the total number of eligible
          participants and each player's individual skill level.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-envelope"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 6. Winner Selection and Notification
        </h2>
        <p>
          Winners are determined by the final standing of the Tournament software once every
          other player has been eliminated. Winners will have seven (7) days from the Tournament's completion to claim their prize. If a winner does not claim their prize within this time frame, the prize may be forfeited or may be awarded to the next eligible participant at Sponsor's discretion. Winners will be notified via the email address associated with their High Society account. All that is required to claim the prize is to complete the identity verification process and provide a valid cryptocurrency wallet address capable of receiving ETH. Winners must respond to the notification within
          <strong>7 days</strong>
          of the Tournament's completion.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-shield-check"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 7. Prize Claim &amp; Compliance Requirements
        </h2>
        <p>
          As a condition of receiving a prize, the First and Second Place winners must provide a
          valid cryptocurrency wallet address capable of receiving ETH. Because Sponsor cannot
          send payment to sanctioned, blacklisted, or otherwise restricted individuals or
          entities, First and Second Place winners are required to complete identity
          verification ("KYC") — full legal name, address, and date of birth, entered on the
          same registration page used to enter the Tournament — within <strong>7 days</strong>
          of the Tournament ending, before any prize is sent. Providing this information is
          entirely optional for every other participant. If a winner is found to have used a
          VPN or other location-masking software to bypass the geographic restrictions in
          Section 1, the prize will be immediately forfeited.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon
            name="hero-receipt-percent"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          /> 8. Taxes
        </h2>
        <p>
          All federal, state, and local taxes associated with the receipt or use of a
          cryptocurrency prize are the sole responsibility of the winner. Prize value will be
          reported where required by law.
        </p>

        <h2 class="flex items-center gap-2">
          <.icon name="hero-scale" class="size-5 text-primary [[data-theme=dark]_&]:text-secondary" />
          9. Limitation of Liability
        </h2>
        <p>
          By entering, you agree to release and hold harmless Sponsor and its subsidiaries,
          affiliates, and advertising agencies from any liability, illness, injury, litigation,
          or damage that may occur, directly or indirectly, from participation in a Tournament
          or the receipt or use of a prize.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about these Rules? Reach out through our
          <.link navigate={~p"/support"} class="link">Support</.link>
          page.
        </p>
      </.legal_page>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :updated_on, :string, required: true
  slot :inner_block, required: true

  defp legal_page(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl">
      <.header>
        {@title}
        <:subtitle>Last updated {@updated_on}</:subtitle>
      </.header>

      <div class="mt-6 space-y-4 text-base-content/80 [&_h2]:mt-8 [&_h2]:mb-1 [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:text-base-content [&_p]:leading-relaxed [&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp last_updated, do: @last_updated
  defp tournament_rules_updated, do: @tournament_rules_updated
end
