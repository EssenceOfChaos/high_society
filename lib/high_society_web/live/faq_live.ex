defmodule HighSocietyWeb.FaqLive do
  @moduledoc """
  Public, self-service FAQ page - answers the questions that would
  otherwise land as support tickets (what Tokens are, whether we offer
  real-money play, how tournament prizes work, and so on). Static content,
  reachable with or without an account like `TokensLive`/`LegalLive` (see
  the `:current_user` live_session in the router).
  """
  use HighSocietyWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "FAQ")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hero_fixed_dark?={true}>
      <:hero>
        <div class="glamorous-bg fixed inset-0" />

        <div class="relative z-10 flex min-h-[40vh] flex-col items-center justify-center px-4 py-20 text-center sm:px-6 lg:px-8">
          <.header>
            <span class="text-white">Frequently Asked Questions</span>
            <:subtitle>
              <span class="text-white/70">
                Answers to the most common questions about High Society, Tokens, and tournaments.
              </span>
            </:subtitle>
          </.header>
        </div>
      </:hero>

      <div class="mx-auto max-w-3xl">
        <.faq_section title="Getting Started">
          <.faq_item question="What is High Society?">
            <p>
              High Society is a gaming platform offering a curated collection of classic games,
              original games, and new takes on familiar favorites. Our collection includes poker,
              blackjack, slots, roulette, War, Baccarat, Zombie Attack, Fleet Strike, and other
              games, with new experiences being introduced on an ongoing basis.
            </p>
            <p>
              Our goal is to create a sophisticated gaming destination where players can discover
              both familiar classics and something new to play.
            </p>
          </.faq_item>

          <.faq_item question="Where can I play High Society?">
            <p>
              High Society is an online gaming platform accessible through our website, subject to
              availability, eligibility requirements, and applicable law.
            </p>
            <p>
              Certain games, promotions, tournaments, or features may not be available in every
              jurisdiction.
            </p>
          </.faq_item>

          <.faq_item question="Is there an age requirement to play?">
            <p>
              Yes. You must be at least 18 years old to create an account or use High Society. See
              our <.link navigate={~p"/age-restriction"} class="link">Age Restriction</.link>
              page for details.
            </p>
          </.faq_item>
        </.faq_section>

        <.faq_section title="High Society Tokens">
          <.faq_item question="What are High Society Tokens?">
            <p>
              High Society Tokens are the in-platform tokens used to play games and interact with
              the High Society gaming platform.
            </p>
            <p>
              High Society Tokens have <strong>no real-world monetary value</strong>. They are not
              currency, cryptocurrency, or an investment, and they do not represent a claim to
              money or other assets.
            </p>
          </.faq_item>

          <.faq_item question="Can I buy or sell High Society Tokens?">
            <p>
              High Society Tokens cannot currently be traded, sold, transferred for value, or
              exchanged for cash.
            </p>
            <p>They are intended solely for use within the High Society gaming platform.</p>
          </.faq_item>

          <.faq_item question="Can I withdraw my High Society Tokens?">
            <p>
              No. High Society Tokens cannot be withdrawn or redeemed for cash or other monetary value.
            </p>
            <p>They are platform-specific tokens intended for gameplay within High Society.</p>
          </.faq_item>

          <.faq_item question="Can High Society Tokens be redeemed for prizes?">
            <p>Not currently.</p>
            <p>
              We are exploring the possibility of introducing a
              <strong>High Society Tokens Store</strong>
              where eligible tokens could potentially be redeemed for prizes or other items. Any
              such program is subject to applicable laws and regulations and will not be
              introduced unless and until the necessary legal and regulatory requirements have
              been satisfied.
            </p>
            <p>
              Details of any future Tokens Store, including eligibility, available prizes,
              redemption requirements, and applicable terms, will be announced separately.
            </p>
          </.faq_item>

          <.faq_item question="Are High Society Tokens cryptocurrency?">
            <p>No.</p>
            <p>
              High Society Tokens are <strong>not cryptocurrency</strong>
              and are not intended to function as a cryptocurrency or financial asset.
            </p>
            <p>
              They have no real-world monetary value, cannot currently be withdrawn or traded for
              value, and are intended for use solely within the High Society platform.
            </p>
            <p>
              This is separate from any cryptocurrency prizes that may be offered in eligible
              promotional tournaments, such as ETH prizes.
            </p>
          </.faq_item>

          <.faq_item question="Can I exchange High Society Tokens for ETH?">
            <p>No.</p>
            <p>High Society Tokens cannot be exchanged for ETH, cash, or other monetary value.</p>
            <p>
              ETH may be awarded separately as a prize in eligible promotional tournaments
              pursuant to the applicable official rules.
            </p>
          </.faq_item>
        </.faq_section>

        <.faq_section title="Real-Money Gaming">
          <.faq_item question="Does High Society offer real-money gambling?">
            <p>Not currently.</p>
            <p>
              High Society does <strong>not currently offer real-money wagering</strong>. We are
              exploring the possibility of offering real-money gameplay in the future, subject to
              obtaining all required regulatory approvals, licenses, and other authorizations.
            </p>
            <p>
              If and when the necessary approvals are obtained, High Society may introduce
              real-money wagering in jurisdictions where it is legally permitted.
            </p>
            <p>
              Until that time, players should not consider High Society Tokens to have monetary
              value or any cash-equivalent value.
            </p>
          </.faq_item>

          <.faq_item question="Is High Society a real-money casino?">
            <p>Not currently.</p>
            <p>
              High Society currently operates as a gaming platform using High Society Tokens that
              have no real-world monetary value. We may introduce regulated real-money wagering in
              the future, but only after obtaining the regulatory approvals, licenses, and other
              authorizations required for the jurisdictions in which such wagering is offered.
            </p>
            <p>
              Until then, High Society Tokens cannot be withdrawn, traded for value, or exchanged
              for cash.
            </p>
          </.faq_item>

          <.faq_item question="Does High Society guarantee that real-money gaming will be introduced?">
            <p>No.</p>
            <p>
              We are exploring the possibility of introducing real-money wagering in the future.
              Any such feature will depend on obtaining the necessary regulatory approvals and
              satisfying applicable legal and operational requirements.
            </p>
            <p>
              We will announce any real-money gaming availability when and where it becomes legally authorized.
            </p>
          </.faq_item>
        </.faq_section>

        <.faq_section title="Games">
          <.faq_item question="What type of poker does High Society offer?">
            <p>
              High Society offers <strong>Texas Hold'em</strong>, including No-Limit Texas Hold'em
              tournaments.
            </p>
            <p>
              Our free tournaments give eligible players an opportunity to compete against other
              players without paying an entry fee, with prizes awarded according to the applicable
              tournament rules.
            </p>
          </.faq_item>

          <.faq_item question="What other games does High Society offer?">
            <p>High Society is about more than card games.</p>
            <p>Our platform includes a growing collection of games that may include:</p>
            <ul>
              <li>Poker</li>
              <li>Blackjack</li>
              <li>Slots</li>
              <li>Roulette</li>
              <li>War</li>
              <li>Baccarat</li>
              <li>Zombie Attack</li>
              <li>Fleet Strike</li>
              <li>Original games developed for High Society</li>
              <li>New interpretations and spin-offs of classic games</li>
              <li>Additional games introduced over time</li>
            </ul>
            <p>
              We are continuously working on new games and experiences, so the High Society
              collection will continue to evolve.
            </p>
          </.faq_item>

          <.faq_item question="Will new games be added?">
            <p>Yes.</p>
            <p>
              We are actively developing and introducing new games on an ongoing basis. Some will
              be original High Society creations, while others will draw inspiration from classic
              gaming experiences.
            </p>
            <p>Check back regularly to discover what's new.</p>
          </.faq_item>
        </.faq_section>

        <.faq_section title="Tournaments">
          <.faq_item question="Can I win real prizes on High Society?">
            <p>
              Yes. High Society currently offers promotional free poker tournaments in which
              eligible players can compete for real prizes.
            </p>
            <p>
              These tournaments are offered <strong>free of charge, with no purchase necessary</strong>,
              and are subject to official tournament rules and applicable law.
              <strong>Void where prohibited by law.</strong>
            </p>
            <p>For example, our current No-Limit Texas Hold'em tournament offers:</p>
            <p class="font-semibold text-base-content">1st Place</p>
            <ul>
              <li>$75 in ETH</li>
              <li>Exclusive High Society Poker Tournament Champion NFT</li>
            </ul>
            <p class="font-semibold text-base-content">2nd Place</p>
            <ul>
              <li>$25 in ETH</li>
            </ul>
            <p>
              Prize details, eligibility requirements, tournament dates, and official rules may
              vary by tournament. Players should review the
              <.link navigate={~p"/tournament/rules"} class="link">applicable official rules</.link>
              before participating.
            </p>
          </.faq_item>

          <.faq_item question="Do I need to purchase anything to enter a free poker tournament?">
            <p>
              No. Our free poker tournaments are offered with <strong>no purchase necessary</strong>.
            </p>
            <p>
              Participation is subject to the applicable eligibility requirements, official
              tournament rules, and local laws. Some jurisdictions may prohibit participation.
            </p>
          </.faq_item>

          <.faq_item question="Who can participate in High Society tournaments?">
            <p>
              Participation is subject to the eligibility requirements stated in the official rules for each tournament.
            </p>
            <p>
              Age, geographic, and other eligibility restrictions may apply. Certain jurisdictions
              may be excluded where participation is prohibited by applicable law.
            </p>
            <p>
              Players are responsible for determining whether they are eligible to participate in a particular tournament.
            </p>
          </.faq_item>

          <.faq_item question="Is High Society available everywhere?">
            <p>Not necessarily.</p>
            <p>
              Certain games, tournaments, promotions, prizes, and future features may be
              unavailable in particular jurisdictions because of applicable laws and regulations.
            </p>
            <p>Where a promotion or tournament is prohibited by law, it is void.</p>
          </.faq_item>

          <.faq_item question="Where can I find the rules for a tournament?">
            <p>
              Each promotional tournament is governed by its <.link
                navigate={~p"/tournament/rules"}
                class="link"
              >applicable official rules</.link>. Players should review those rules before entering.
            </p>
            <p>
              The official rules may contain important information concerning eligibility, entry,
              tournament structure, prizes, geographic restrictions, claim procedures, and other
              requirements.
            </p>
          </.faq_item>

          <.faq_item question="What is the High Society Poker Tournament Champion NFT?">
            <p>
              Eligible winners of designated High Society poker tournaments may receive an
              exclusive <strong>High Society Poker Tournament Champion NFT</strong>
              as part of their tournament prize.
            </p>
            <p>
              The NFT is a digital collectible associated with the tournament and the player's achievement.
            </p>
            <p>
              NFT availability, eligibility, and any applicable terms are determined by the
              official rules of the applicable tournament.
            </p>
          </.faq_item>

          <.faq_item question="Is the Champion NFT worth money?">
            <p>
              The High Society Poker Tournament Champion NFT is awarded as a tournament prize and
              digital collectible. High Society does not represent or guarantee that it has any
              particular monetary value, resale value, or market value.
            </p>
            <p>Any terms governing the NFT will be provided separately where applicable.</p>
          </.faq_item>
        </.faq_section>

        <.faq_section title="Still Need Help?">
          <.faq_item question="Where can I get help?">
            <p>
              For questions about your account, gameplay, tournaments, or other High Society
              features, please <.link navigate={~p"/support"} class="link">contact High Society support</.link>.
            </p>
            <p>
              For tournament-specific questions, please review the applicable official rules before contacting support.
            </p>
          </.faq_item>
        </.faq_section>

        <div class="mt-12 rounded-lg border border-base-300 bg-base-200/50 p-6 text-sm text-base-content/70">
          <p class="font-semibold text-base-content">A Note About Future Features</p>
          <p class="mt-2">
            High Society is continually evolving. Features described as planned, proposed, or
            under consideration — including a Tokens Store and real-money wagering — are
            <strong>not currently available</strong>
            and should not be interpreted as guarantees that they will be introduced.
          </p>
          <p class="mt-2">
            Any future feature involving prizes, token redemption, real-money wagering, or other
            regulated activity will be introduced only subject to applicable legal and regulatory
            requirements.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp faq_section(assigns) do
    ~H"""
    <section class="mt-12 first:mt-0">
      <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
      <div class="mt-4 divide-y divide-base-300 border-y border-base-300">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :question, :string, required: true
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <details class="group py-4">
      <summary class="flex cursor-pointer list-none items-center justify-between gap-4 font-medium text-base-content marker:content-none">
        {@question}
        <.icon
          name="hero-chevron-down"
          class="size-5 shrink-0 text-base-content/50 transition-transform group-open:rotate-180"
        />
      </summary>
      <div class="mt-3 space-y-2 text-sm leading-relaxed text-base-content/80 [&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-6">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end
end
