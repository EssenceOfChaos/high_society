defmodule HighSocietyWeb.AdminTokenTransactionsController do
  @moduledoc """
  CSV export for `HighSocietyWeb.AdminLive.TokenTransactions` - a plain
  controller (not a LiveView) since a file download needs a real HTTP
  response, not a socket push. Mirrors that LiveView's own admin gate
  (`Accounts.admin?/1`) since there's no plug-based equivalent of the
  `:require_admin` on_mount for controller actions.
  """
  use HighSocietyWeb, :controller

  alias HighSociety.Accounts

  def export(conn, %{"email" => email} = params) do
    if Accounts.admin?(conn.assigns.current_scope.user) do
      email = String.trim(email)
      source = params |> Map.get("source", "") |> String.trim()

      case Accounts.get_user_by_email(email) do
        nil ->
          conn
          |> put_status(:not_found)
          |> text("No player found with email \"#{email}\".")

        user ->
          opts = if source == "", do: [limit: nil], else: [limit: nil, source: source]
          transactions = Accounts.list_token_transactions(user, opts)

          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            ~s(attachment; filename="token-transactions-#{csv_filename_part(email)}.csv")
          )
          |> send_resp(200, to_csv(transactions))
      end
    else
      conn
      |> put_status(:forbidden)
      |> text("You don't have access to that page.")
    end
  end

  defp to_csv(transactions) do
    header = ["Time (UTC)", "Source", "Amount", "Metadata"]

    rows =
      Enum.map(transactions, fn t ->
        [
          DateTime.to_iso8601(t.inserted_at),
          t.source,
          Integer.to_string(t.amount),
          Jason.encode!(t.metadata)
        ]
      end)

    [header | rows]
    |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &csv_escape/1) <> "\r\n" end)
  end

  defp csv_escape(field) do
    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(field, "\"", "\"\"")}")
    else
      field
    end
  end

  defp csv_filename_part(email) do
    email
    |> String.replace(~r/[^a-zA-Z0-9]+/, "-")
    |> String.trim("-")
  end
end
