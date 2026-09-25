defmodule HighSocietyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: HighSocietyWeb.Gettext

  alias HighSociety.Tokens
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="font-serif text-2xl font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_class, :any,
    default: nil,
    doc: "the function for computing a row's extra class(es), given the row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class={@row_class && @row_class.(row)}
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a single playing card, given a two/three-character card string like
  `"AS"` or `"10H"` (rank followed by suit), as an SVG from
  `priv/static/images/cards/`. Used by War, Blackjack, and Poker.

  ## Examples

      <.card_face card="AS" />
      <.card_face card={nil} pending />
      <.card_face card="10H" face_down />
  """
  attr :id, :string,
    default: nil,
    doc:
      "required when deal_animation is set, so the entrance plays once per card, not per re-render"

  attr :card, :string, default: nil

  attr :dim, :boolean,
    default: false,
    doc: "darkens the card without resizing it, e.g. for burned cards or a hand ranking's kickers"

  attr :pending, :boolean,
    default: false,
    doc: "pulsing placeholder for a card yet to be revealed"

  attr :face_down, :boolean,
    default: false,
    doc: "renders a face-down card back instead of the card"

  attr :card_back, :string,
    default: "/images/cards/card_back.svg",
    doc:
      "src for the face-down image - pass a viewer's chosen design (see `card_back_image/1`) for a per-viewer skin; defaults to the classic back for callers (War, Blackjack) that don't offer a choice"

  attr :deal_animation, :boolean,
    default: false,
    doc: """
    swaps the plain CSS fade-in for a JS-driven anime.js entrance (a card
    tumbling in from above and settling into place) - opt-in, and requires
    `id`. Retriggers any time the card actually showing changes, so it plays
    equally well for a paced multi-card deal (Blackjack) or a single slot
    that's simply replaced every round (War).
    """

  attr :size, :atom,
    values: [:normal, :medium, :large],
    default: :normal,
    doc: """
    large is ~30% bigger, for screens with only one or two cards and little
    else on them. medium (~15% bigger) is for a viewer's own cards on a
    busier table (e.g. Poker) - bigger than everyone else's, short of
    crowding out the rest of the screen.
    """

  def card_face(assigns) do
    assigns =
      assigns
      |> assign(:image_name, assigns.card && card_image_name(assigns.card))
      |> assign(:deal_key, assigns.deal_animation && deal_key(assigns.card, assigns.face_down))

    ~H"""
    <div
      id={@id}
      phx-hook={@deal_animation && "#{inspect(__MODULE__)}.CardDealAnimation"}
      data-deal-key={@deal_key}
      class={
        [
          "@container flex aspect-[7/10] min-w-0 items-center justify-center overflow-hidden rounded-xl shadow-md transition-transform duration-300",
          @size == :normal && "[contain-intrinsic-width:7rem] flex-[0_1_7rem]",
          @size == :medium && "[contain-intrinsic-width:8rem] flex-[0_1_8rem]",
          @size == :large && "[contain-intrinsic-width:9rem] flex-[0_1_9rem]",
          # Below `lg:`, every card shrinks to a common compact size
          # regardless of `size` - a busy table (5 community cards plus
          # every seat's own hole cards) has nowhere near enough width for
          # even the `:normal` tier at full size until the felt is wide
          # enough (~1024px+) for its aspect-ratio-driven height to give
          # everything room too - see `#poker-felt`'s own `lg:` breakpoint.
          "max-lg:[contain-intrinsic-width:4rem]! max-lg:flex-[0_1_4rem]!",
          !@deal_animation && "card-deal-in",
          !@card && @pending && "border-2 border-error bg-error text-error-content animate-pulse",
          !@card && !@pending && !@face_down && "border-2 border-dashed border-base-300 bg-base-200",
          # `brightness` rather than `opacity` - the hand-rankings modal
          # overlaps cards with negative margins (`-space-x-8`), and opacity
          # would let each dimmed card show whatever's stacked behind it
          # (the next card, or another dimmed one) bleeding through right at
          # the overlap, reading as a highlight instead of a uniform dim.
          # Brightness darkens the card's own pixels without ever exposing
          # what's beneath it. Deliberately no size change alongside it -
          # every card in a hand stays the same size, dimmed or not.
          @dim && "brightness-50",
          card_z_class(@card, @face_down)
        ]
      }
    >
      <img
        :if={@card && !@face_down}
        src={"/images/cards/#{@image_name}.svg"}
        alt={@card}
        class="size-full object-contain"
      />
      <img
        :if={@face_down}
        src={@card_back}
        alt="Face-down card"
        class="size-full object-contain"
      />
      <.icon
        :if={!@card && !@face_down && @pending}
        name="hero-question-mark-circle"
        class="size-[36cqw] text-error-content"
      />
      <.icon
        :if={!@card && !@face_down && !@pending}
        name="hero-question-mark-circle"
        class="size-[29cqw] text-base-content/20"
      />
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CardDealAnimation">
      export default {
        // Fires once per genuine reveal, keyed off `data-deal-key` actually
        // changing to something real - covers both shapes of "dealt": a
        // fresh mount already showing its face (a card hit into an existing
        // hand, which never goes through a paced "empty" placeholder stage;
        // reconnecting mid-round mounts every already-shown card the same
        // way, replaying as a deal - an acceptable, honestly-labeled redraw
        // rather than a silent snap-into-place), and a later patch that
        // either fills a pending placeholder or swaps one already-shown
        // card straight for another (War replaces its single slot outright
        // every round, with no pending stage at all).
        mounted() {
          this.dealKey = this.el.dataset.dealKey
          if (this.dealKey) this.playEntrance()
        },
        updated() {
          const newKey = this.el.dataset.dealKey
          if (newKey && newKey !== this.dealKey) this.playEntrance()
          this.dealKey = newKey
        },
        playEntrance() {
          // The card's own `transition-transform` (for the unrelated `dim`
          // fade) would otherwise fight anime.js for the same CSS property:
          // every inline value anime.js sets mid-flight gets treated as a
          // brand new transition target, chasing a constantly-moving goal
          // and damping the motion down to a few percent of its real
          // distance - which is exactly what reads as "snapping into
          // place". Suspending it for the entrance and handing it back
          // afterward keeps that fade working for its actual purpose.
          this.el.style.transition = "none"
          this.el.style.opacity = "0"

          const rotate = Math.random() * 26 - 13
          const drift = Math.random() * 44 - 22

          window.animeAnimate(this.el, {
            opacity: [0, 1],
            translateY: [-64, 0],
            translateX: [drift, 0],
            rotate: [rotate, 0],
            scale: [0.7, 1],
            duration: 480,
            ease: "outBack",
            onComplete: () => { this.el.style.transition = "" }
          })
        }
      }
    </script>
    """
  end

  @doc """
  The face-down image src for a poker player's chosen card back design (see
  `HighSociety.Accounts.User.poker_settings_changeset/2`) - `"default"` (or
  `nil`, for a user who's never opened the settings modal) is the classic
  back every other game uses; anything else is one of the four alternate
  designs in `priv/static/images/cards/`.
  """
  @spec card_back_image(String.t() | nil) :: String.t()
  def card_back_image(color) when color in ~w(black blue green red),
    do: "/images/cards/card_back_#{color}.png"

  def card_back_image(_default_or_nil), do: "/images/cards/card_back.svg"

  # Overlapping hands (e.g. Blackjack's -space-x-* rows) rely on DOM order
  # for stacking - a later card should sit on top of an earlier one once
  # both are actually dealt. But an empty slot still awaiting its card is
  # also a later sibling, so without this it would paint over the
  # already-dealt card next to it the instant the row overlaps. Pinning
  # dealt/face-down cards above still-empty slots keeps the overlap looking
  # right at every stage of the deal.
  defp card_z_class(card, face_down), do: if(card || face_down, do: "z-10", else: "z-0")

  @doc """
  Renders a player's badge icon, resolved from their `active_days_count`,
  with a tooltip revealing the badge name on hover.

  `tooltip_position` picks which daisyUI tooltip side to open - the default
  `"tooltip-bottom"` suits the top navbar (an upward tooltip there would
  open off the top of the viewport); pass `"tooltip-top"` for a badge
  placed lower on the page.

  ## Examples

      <.player_badge active_days_count={@current_scope.user.active_days_count} />
  """
  attr :active_days_count, :integer, required: true
  attr :class, :string, default: "size-8"
  attr :tooltip_position, :string, default: "tooltip-bottom"

  def player_badge(assigns) do
    assigns =
      assign(assigns, :badge, HighSociety.Badges.for_active_days(assigns.active_days_count))

    ~H"""
    <span class={["tooltip", @tooltip_position]} data-tip={@badge.name}>
      <img
        src={"/images/badges/#{@badge.slug}.png"}
        alt={@badge.name}
        class={["inline-block object-contain align-middle", @class]}
      />
    </span>
    """
  end

  @doc """
  Renders a player's Token balance, counting up/down with an anime.js tween
  whenever `amount` changes across a LiveView patch (a bet, a payout, a
  claim...) instead of the digits just snapping to the new value.

  ## Examples

      <.token_balance amount={@current_scope.user.tokens_balance} />
  """
  attr :amount, :integer, required: true

  def token_balance(assigns) do
    ~H"""
    <div
      id="tokens-balance"
      phx-hook=".TokenBalanceCounter"
      data-amount={@amount}
      class="text-lg font-bold"
    >
      {Tokens.format(@amount)} Tokens
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TokenBalanceCounter">
      import { animate } from "@/vendor/anime.js"

      const formatAmount = (amount) => {
        const sign = amount < 0 ? "-" : ""
        const abs = Math.abs(Math.round(amount))
        return `${sign}${abs.toLocaleString("en-US")} Tokens`
      }

      export default {
        mounted() {
          this.counter = { amount: Number(this.el.dataset.amount) }
        },
        updated() {
          const target = Number(this.el.dataset.amount)
          if (target === this.counter.amount) return

          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            this.counter.amount = target
            return
          }

          this.el.textContent = formatAmount(this.counter.amount)

          animate(this.counter, {
            amount: target,
            duration: 700,
            ease: "outQuad",
            onUpdate: () => { this.el.textContent = formatAmount(this.counter.amount) }
          })
        }
      }
    </script>
    """
  end

  @doc """
  A large, labeled countdown to `target` (a future `DateTime`) - Days,
  Hours, Minutes, Seconds, each flipping via daisyUI's `.countdown`
  component (https://daisyui.com/components/countdown/). Ticks entirely
  client-side once mounted (no periodic server round-trip), so it stays
  accurate even on a long-lived connection.

  ## Examples

      <.countdown id="tournament-countdown" target={@tournament.scheduled_start_at} />
  """
  attr :id, :string, required: true
  attr :target, :any, required: true, doc: "a future DateTime.t() to count down to"

  def countdown(assigns) do
    assigns =
      assign(assigns, :units, [
        {"Days", "days"},
        {"Hours", "hours"},
        {"Minutes", "minutes"},
        {"Seconds", "seconds"}
      ])

    ~H"""
    <div
      id={@id}
      phx-hook=".Countdown"
      data-target={DateTime.to_iso8601(@target)}
      class="flex justify-center gap-4 sm:gap-8"
    >
      <div :for={{label, unit} <- @units} class="flex flex-col items-center">
        <span class="countdown font-mono text-4xl font-bold sm:text-6xl">
          <%!-- No inline `style="--value:..."` here - the CSP's
               `style-src 'self'` has no `unsafe-inline` for style
               *attributes*, so a literal one would silently stop applying
               in production (see csp_compliance_test.exs). `.Countdown`'s
               `mounted()` sets `--value` via `el.style.setProperty` on
               first tick instead - a CSSOM mutation, which CSP doesn't
               govern - so this starts at the CSS default (0) for the
               brief pre-hydration instant, then ticks immediately. --%>
          <span data-countdown-unit={unit} aria-live="polite" aria-label="0">0</span>
        </span>
        <span class="mt-1 text-xs font-semibold uppercase tracking-widest text-base-content/60 sm:text-sm">
          {label}
        </span>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
      export default {
        mounted() {
          this.targetMs = new Date(this.el.dataset.target).getTime()
          this.units = {
            days: this.el.querySelector('[data-countdown-unit="days"]'),
            hours: this.el.querySelector('[data-countdown-unit="hours"]'),
            minutes: this.el.querySelector('[data-countdown-unit="minutes"]'),
            seconds: this.el.querySelector('[data-countdown-unit="seconds"]')
          }
          this.tick()
          this.timer = setInterval(() => this.tick(), 1000)
        },
        destroyed() {
          clearInterval(this.timer)
        },
        tick() {
          const diff = Math.max(0, this.targetMs - Date.now())
          const values = {
            days: Math.floor(diff / 86400000),
            hours: Math.floor((diff % 86400000) / 3600000),
            minutes: Math.floor((diff % 3600000) / 60000),
            seconds: Math.floor((diff % 60000) / 1000)
          }

          for (const [unit, el] of Object.entries(this.units)) {
            if (!el) continue
            el.textContent = values[unit]
            el.style.setProperty("--value", values[unit])
            el.setAttribute("aria-label", values[unit])
          }

          if (diff <= 0) clearInterval(this.timer)
        }
      }
    </script>
    """
  end

  # Whether this card slot is showing a face - either the card itself or a
  # face-down back - as opposed to an empty/pending placeholder. Only
  # computed (and only meaningful) when `deal_animation` is set: it's what
  # `.CardDealAnimation` diffs against on every patch to catch the exact
  # moment a card is revealed.
  # Identifies what this card slot is currently showing, so
  # `.CardDealAnimation` can tell a genuine reveal from an unrelated
  # re-render: a paced Blackjack deal goes from `nil` to a card once, while
  # War replaces an already-shown card outright every round - both are just
  # "the key changed to something real", with the actual card string
  # doubling as that key so two different cards are never mistaken for the
  # same reveal. `nil` (an empty/pending slot) omits the attribute entirely
  # rather than sending an empty string, which reads as "nothing to compare
  # against yet" just as plainly on the JS side (`undefined`).
  defp deal_key(card, face_down) do
    cond do
      card -> card
      face_down -> "face-down"
      true -> nil
    end
  end

  defp card_split(card) do
    suit = String.last(card)
    rank = String.slice(card, 0, String.length(card) - 1)
    {rank, suit}
  end

  # Maps a card string like "AS"/"10H"/"2D" to the `<rank>_of_<suit>` asset
  # name used by the SVG deck in `priv/static/images/cards/`.
  defp card_image_name(card) do
    {rank, suit} = card_split(card)
    "#{card_rank_word(rank)}_of_#{card_suit_word(suit)}"
  end

  defp card_rank_word("A"), do: "ace"
  defp card_rank_word("K"), do: "king"
  defp card_rank_word("Q"), do: "queen"
  defp card_rank_word("J"), do: "jack"
  defp card_rank_word(rank), do: rank

  defp card_suit_word("S"), do: "spades"
  defp card_suit_word("H"), do: "hearts"
  defp card_suit_word("D"), do: "diamonds"
  defp card_suit_word("C"), do: "clubs"

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(HighSocietyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(HighSocietyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
