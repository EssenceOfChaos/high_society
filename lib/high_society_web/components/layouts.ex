defmodule HighSocietyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HighSocietyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :hero,
    doc:
      "optional full-bleed section rendered between the header and the constrained main content"

  attr :hero_video?, :boolean,
    default: false,
    doc:
      "true when the hero slot is unpredictable video content (only the dashboard, currently) " <>
        "rather than a fixed dark background - the brand icon needs a guaranteed-light treatment " <>
        "there instead of its usual theme color, since the theme color could wash out against the " <>
        "video at any given moment"

  attr :hero_fixed_dark?, :boolean,
    default: false,
    doc:
      "true when the hero slot is a fixed dark/navy background regardless of the light/dark " <>
        "toggle (e.g. .glamorous-bg, see SupportLive) - --color-primary is navy in light theme " <>
        "too, so the icon's usual text-primary would wash out against a navy hero specifically " <>
        "in light theme. Forces the same literal gold used on the 404 page instead."

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <ul class={[
      "menu menu-horizontal w-full relative z-10 flex items-center gap-4 px-4 sm:px-6 lg:px-8 justify-end",
      @hero != [] && "text-white"
    ]}>
      <%= if @current_scope do %>
        <li class="flex flex-row items-center gap-2">
          <.link navigate={~p"/badges"} class="flex">
            <.player_badge active_days_count={@current_scope.user.active_days_count} />
          </.link>
          {@current_scope.user.display_name || @current_scope.user.email}
        </li>
        <li>
          <.link href={~p"/users/settings"}>Settings</.link>
        </li>
        <li>
          <.link href={~p"/users/log-out"} method="delete">Log out</.link>
        </li>
      <% else %>
        <li>
          <.link href={~p"/users/register"}>Register</.link>
        </li>
        <li>
          <.link href={~p"/users/log-in"}>Log in</.link>
        </li>
      <% end %>
    </ul>

    <header class={[
      "navbar relative z-10 px-4 sm:px-6 lg:px-8",
      @hero != [] && "text-white"
    ]}>
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <.icon
            name="hero-rectangle-stack-solid"
            class={[
              "size-7",
              cond do
                @hero_video? -> "bg-gradient-to-r from-zinc-100 via-slate-200 to-zinc-300"
                @hero_fixed_dark? -> "text-[#957c3d]"
                true -> "text-primary [[data-theme=dark]_&]:text-secondary"
              end
            ]}
          />
          <span class="text-lg font-bold tracking-tight">High Society</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <.theme_toggle hero?={@hero != []} />
          </li>
        </ul>
      </div>
    </header>

    {render_slot(@hero)}

    <main class="relative z-10 bg-base-100 px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.footer />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the site footer with social placeholder links and a support link.
  """
  def footer(assigns) do
    ~H"""
    <footer class="relative z-10 border-t border-base-300 bg-base-100 px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto flex max-w-3xl flex-col items-center gap-6 text-center sm:flex-row sm:justify-between sm:text-left">
        <a href="/" class="flex items-center gap-2">
          <.icon
            name="hero-rectangle-stack-solid"
            class="size-5 text-primary [[data-theme=dark]_&]:text-secondary"
          />
          <span class="font-semibold tracking-tight">High Society</span>
        </a>

        <div class="flex items-center gap-4">
          <a
            href="#"
            aria-label="X (Twitter)"
            class="text-base-content/50 transition-colors hover:text-base-content"
          >
            <.social_icon name="x" />
          </a>
          <a
            href="#"
            aria-label="Instagram"
            class="text-base-content/50 transition-colors hover:text-base-content"
          >
            <.social_icon name="instagram" />
          </a>
          <a
            href="#"
            aria-label="Discord"
            class="text-base-content/50 transition-colors hover:text-base-content"
          >
            <.social_icon name="discord" />
          </a>
          <a
            href="#"
            aria-label="GitHub"
            class="text-base-content/50 transition-colors hover:text-base-content"
          >
            <.social_icon name="github" />
          </a>
        </div>

        <div class="flex items-center gap-4 text-sm text-base-content/70">
          <.link navigate={~p"/tokens"} class="link link-hover">
            Tokens
          </.link>
          <.link navigate={~p"/support"} class="link link-hover">
            Support
          </.link>
          <span>&copy; {Date.utc_today().year} High Society</span>
        </div>
      </div>

      <div class="mx-auto mt-8 flex max-w-3xl flex-wrap items-center justify-center gap-x-4 gap-y-2 border-t border-base-300 pt-6 text-xs text-base-content/50">
        <.link navigate={~p"/terms"} class="link link-hover">
          Terms and Conditions
        </.link>
        <.link navigate={~p"/privacy"} class="link link-hover">
          Privacy Policy
        </.link>
        <.link navigate={~p"/cookies"} class="link link-hover">
          Cookies Policy
        </.link>
        <.link navigate={~p"/responsible-gaming"} class="link link-hover">
          Responsible Gaming
        </.link>
        <.link navigate={~p"/age-restriction"} class="link link-hover">
          18+
        </.link>
        <.link navigate={~p"/tournament/rules"} class="link link-hover">
          Tournament Rules
        </.link>
      </div>
    </footer>
    """
  end

  @doc """
  The GA4 measurement ID (e.g. `"G-XXXXXXXXXX"`) to load Google Analytics
  for, or `nil` to skip it - see `root.html.heex` and the
  `:google_analytics_id` config in `config/config.exs`/`config/runtime.exs`.
  """
  def google_analytics_id, do: Application.get_env(:high_society, :google_analytics_id)

  attr :name, :string, required: true

  defp social_icon(%{name: "x"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class="size-5" aria-hidden="true">
      <path d="M18.24 2.25h3.31l-7.23 8.26 8.5 11.24h-6.66l-5.22-6.83-5.97 6.83H1.66l7.73-8.84L1.25 2.25h6.83l4.72 6.24 5.44-6.24Zm-1.16 17.52h1.83L7.02 4.13H5.06l11.99 15.64Z" />
    </svg>
    """
  end

  defp social_icon(%{name: "instagram"} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      class="size-5"
      aria-hidden="true"
    >
      <rect x="3" y="3" width="18" height="18" rx="5" />
      <circle cx="12" cy="12" r="4.2" />
      <circle cx="17.3" cy="6.7" r="1.1" fill="currentColor" stroke="none" />
    </svg>
    """
  end

  defp social_icon(%{name: "discord"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class="size-5" aria-hidden="true">
      <path d="M20.32 5.37a17.9 17.9 0 0 0-4.43-1.37c-.19.34-.41.79-.56 1.15a16.6 16.6 0 0 0-4.95 0 9.5 9.5 0 0 0-.57-1.15 17.86 17.86 0 0 0-4.43 1.37C2.87 8.8 2.15 12.14 2.49 15.42a18 18 0 0 0 5.48 2.77c.44-.6.84-1.24 1.18-1.92-.65-.24-1.27-.54-1.85-.89.16-.11.31-.23.46-.35a12.8 12.8 0 0 0 10.48 0c.15.12.3.24.46.35-.58.35-1.2.65-1.85.89.34.68.74 1.32 1.18 1.92a17.98 17.98 0 0 0 5.48-2.77c.4-3.8-.6-7.11-2.59-10.05ZM9.68 13.86c-.86 0-1.56-.79-1.56-1.76 0-.97.68-1.76 1.56-1.76.89 0 1.58.8 1.56 1.76 0 .97-.68 1.76-1.56 1.76Zm4.65 0c-.86 0-1.56-.79-1.56-1.76 0-.97.68-1.76 1.56-1.76.89 0 1.58.8 1.56 1.76 0 .97-.67 1.76-1.56 1.76Z" />
    </svg>
    """
  end

  defp social_icon(%{name: "github"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class="size-5" aria-hidden="true">
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M12 2C6.48 2 2 6.58 2 12.21c0 4.5 2.87 8.31 6.84 9.66.5.1.68-.22.68-.5v-1.94c-2.78.62-3.37-1.37-3.37-1.37-.46-1.2-1.11-1.52-1.11-1.52-.91-.64.07-.63.07-.63 1 .07 1.53 1.05 1.53 1.05.9 1.57 2.34 1.12 2.91.86.09-.67.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.31.1-2.72 0 0 .84-.28 2.75 1.05a9.3 9.3 0 0 1 5 0c1.9-1.33 2.74-1.05 2.74-1.05.55 1.41.2 2.46.1 2.72.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.94.68 1.9v2.82c0 .28.18.61.69.5A10.02 10.02 0 0 0 22 12.21C22 6.58 17.52 2 12 2Z"
      />
    </svg>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :hero?, :boolean,
    default: false,
    doc:
      "true when floating over the dashboard's hero video, for a translucent look that suits a dark background regardless of the site theme"

  def theme_toggle(assigns) do
    ~H"""
    <div class={[
      "card relative flex flex-row items-center rounded-full border-2",
      if(@hero?,
        do: "border-white/25 bg-white/10 backdrop-blur-sm",
        else: "border-base-300 bg-base-300"
      )
    ]}>
      <div class={[
        "absolute left-0 h-full w-1/3 rounded-full border-1 transition-[left] [[data-theme-source=system]_&]:!left-0 [[data-theme=dark]_&]:left-2/3 [[data-theme=light]_&]:left-1/3",
        if(@hero?,
          do: "border-white/20 bg-white/30",
          else: "border-base-200 bg-base-100 brightness-200"
        )
      ]} />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
