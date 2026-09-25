defmodule HighSocietyWeb.UserLive.Login do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <%!-- Hidden by default, server-side, since the server has no way to
        know a request came from a standalone home-screen app - `mounted()`
        below reveals it only when `window.navigator.standalone` (iOS) or
        `(display-mode: standalone)` (everywhere else) says so. Solves a
        real dead end: iOS gives a home-screen "Add to Home Screen" web app
        its own storage jar, entirely separate from Safari's, and every
        emailed link opens in Safari regardless - so a login link tapped
        from Mail signs you in there, not in the app. Pasting the link here
        instead navigates *this* page (already running inside the app's own
        isolated context) straight to it, landing the session in the right
        jar. Safe to build on `Accounts.get_user_by_magic_link_token/1`
        never consuming the token on its own - only the confirm button's
        POST does (see `Accounts.login_user_by_magic_link/1`) - so copying
        the link instead of tapping it leaves it completely untouched. --%>
        <div
          id="standalone-magic-link-paste"
          phx-hook=".StandaloneMagicLinkPaste"
          phx-update="ignore"
          class="hidden space-y-2 rounded-box border border-base-300 bg-base-200 p-4 text-sm"
        >
          <p class="font-semibold">Using the app from your Home Screen?</p>
          <p class="text-base-content/70">
            Login links always open in Safari, not this app - so instead of tapping the link
            in your email, press and hold it, tap <strong>Copy Link</strong>, then paste it
            below.
          </p>
          <form id="standalone-magic-link-paste-form">
            <input
              type="text"
              id="standalone-magic-link-paste-input"
              placeholder="Paste your login link here"
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
              class="input input-bordered w-full"
            />
            <button type="submit" class="btn btn-primary btn-sm mt-2 w-full">Continue</button>
          </form>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".StandaloneMagicLinkPaste">
          export default {
            mounted() {
              const standalone =
                window.navigator.standalone === true ||
                window.matchMedia("(display-mode: standalone)").matches

              if (!standalone) return

              this.el.classList.remove("hidden")

              const form = this.el.querySelector("form")
              const input = this.el.querySelector("input")

              form.addEventListener("submit", (e) => {
                e.preventDefault()
                const match = input.value.match(/\/users\/log-in\/([^/?#\s]+)/)

                if (match) {
                  window.location.href = `${window.location.origin}/users/log-in/${match[1]}`
                } else {
                  input.setCustomValidity(
                    "That doesn't look like a login link - copy the whole link from your email."
                  )
                  input.reportValidity()
                }
              })

              input.addEventListener("input", () => input.setCustomValidity(""))
            }
          }
        </script>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, page_title: "Log In", form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:high_society, HighSociety.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
