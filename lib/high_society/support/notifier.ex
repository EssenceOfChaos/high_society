defmodule HighSociety.Support.Notifier do
  import Swoosh.Email
  require Logger

  alias HighSociety.Mailer
  alias HighSociety.Support.Report

  @doc """
  Delivers a support report to the support inbox, with the reporter set as
  the reply-to address so replying goes straight to them.
  """
  def deliver_report(%Report{} = report) do
    category_label = Report.category_label(report.category)

    email =
      new()
      |> to(Application.get_env(:high_society, :support_email))
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> reply_to(report.email)
      |> subject("[#{category_label}#{game_suffix(report.game)}] #{report.name}")
      |> text_body("""
      New support request submitted via highsociety.cc

      Category: #{category_label}#{game_line(report.game)}
      Name: #{report.name}
      Email: #{report.email}

      Message:
      #{report.message}
      """)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, report}

      {:error, reason} = error ->
        Logger.error("Failed to deliver support report from #{report.email}: #{inspect(reason)}")
        error
    end
  end

  defp game_suffix(nil), do: ""
  defp game_suffix(game), do: " / #{Report.game_label(game)}"

  defp game_line(nil), do: ""
  defp game_line(game), do: "\nGame: #{Report.game_label(game)}"
end
