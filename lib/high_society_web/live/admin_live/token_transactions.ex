defmodule HighSocietyWeb.AdminLive.TokenTransactions do
  @moduledoc """
  Admin-only lookup of a single player's Token ledger (see
  `HighSociety.Accounts.list_token_transactions/2`). Gated by the
  `:require_admin` on_mount - see `HighSocietyWeb.UserAuth`.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.TokenTransaction
  alias HighSociety.Tokens

  @page_size 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Token Ledger",
       email_query: "",
       source_query: "",
       searched_user: nil,
       not_found_email: nil,
       transactions: [],
       has_more: false
     )}
  end

  @impl true
  def handle_event("search", %{"email" => email, "source" => source}, socket) do
    email = String.trim(email)
    source = String.trim(source)

    case Accounts.get_user_by_email(email) do
      nil ->
        {:noreply,
         assign(socket,
           email_query: email,
           source_query: source,
           searched_user: nil,
           not_found_email: email,
           transactions: [],
           has_more: false
         )}

      user ->
        transactions = Accounts.list_token_transactions(user, page_opts(source))

        {:noreply,
         assign(socket,
           email_query: email,
           source_query: source,
           searched_user: user,
           not_found_email: nil,
           transactions: transactions,
           has_more: length(transactions) == @page_size
         )}
    end
  end

  def handle_event("load_more", _params, socket) do
    %{searched_user: user, source_query: source, transactions: transactions} = socket.assigns
    opts = [before: cursor(List.last(transactions))] ++ page_opts(source)
    more = Accounts.list_token_transactions(user, opts)

    {:noreply,
     assign(socket,
       transactions: transactions ++ more,
       has_more: length(more) == @page_size
     )}
  end

  defp page_opts(""), do: [limit: @page_size]
  defp page_opts(source), do: [limit: @page_size, source: source]

  defp cursor(%TokenTransaction{inserted_at: inserted_at, id: id}), do: {inserted_at, id}

  defp signed_amount(amount) when amount >= 0, do: "+#{Tokens.format(amount)}"
  defp signed_amount(amount), do: Tokens.format(amount)

  defp amount_class(amount) when amount >= 0, do: "text-success"
  defp amount_class(_amount), do: "text-error"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp format_metadata(metadata) when map_size(metadata) == 0, do: "—"
  defp format_metadata(metadata), do: inspect(metadata)

  defp export_params(email, ""), do: %{email: email}
  defp export_params(email, source), do: %{email: email, source: source}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl">
        <.header>
          Token Ledger
          <:subtitle>
            Look up a player's full Token transaction history by email.
          </:subtitle>
        </.header>

        <form phx-submit="search" class="mt-6 flex flex-wrap items-end gap-3">
          <.input
            type="email"
            name="email"
            id="admin-email-search"
            value={@email_query}
            label="Player email"
            placeholder="player@example.com"
            required
          />
          <.input
            type="text"
            name="source"
            id="admin-source-filter"
            value={@source_query}
            label="Source (optional)"
            placeholder="e.g. blackjack_bet"
          />
          <.button class="btn btn-primary mb-2">Search</.button>
        </form>

        <p :if={@not_found_email} id="admin-not-found" class="mt-4 alert alert-error text-sm">
          No player found with email "{@not_found_email}".
        </p>

        <div :if={@searched_user} class="mt-6">
          <div class="rounded-box border border-base-300 bg-base-100 p-4">
            <div class="text-sm text-base-content/60">{@searched_user.email}</div>
            <div class="text-lg font-bold">
              {Tokens.format(@searched_user.tokens_balance)} Tokens
            </div>
          </div>

          <p :if={@transactions == []} class="mt-4 text-sm text-base-content/60">
            No Token transactions recorded for this player yet.
          </p>

          <div :if={@transactions != []} class="mt-4 flex items-center justify-between">
            <span class="text-sm text-base-content/60">
              Showing {length(@transactions)} transaction{if length(@transactions) == 1,
                do: "",
                else: "s"} (the CSV download always includes the player's full history).
            </span>
            <.link
              href={
                ~p"/admin/token-transactions/export?#{export_params(@email_query, @source_query)}"
              }
              class="btn btn-sm btn-outline"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download CSV
            </.link>
          </div>

          <div :if={@transactions != []} class="mt-2 overflow-x-auto">
            <.table id="admin-token-transactions" rows={@transactions}>
              <:col :let={t} label="Time">{format_time(t.inserted_at)}</:col>
              <:col :let={t} label="Source">{t.source}</:col>
              <:col :let={t} label="Amount">
                <span class={["font-semibold", amount_class(t.amount)]}>
                  {signed_amount(t.amount)} Tokens
                </span>
              </:col>
              <:col :let={t} label="Metadata">{format_metadata(t.metadata)}</:col>
            </.table>
          </div>

          <div :if={@has_more} class="mt-4 flex justify-center">
            <.button phx-click="load_more" class="btn btn-outline btn-sm">Load more</.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
