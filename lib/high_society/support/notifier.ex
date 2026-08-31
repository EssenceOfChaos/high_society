defmodule HighSociety.Support.Notifier do
  import Swoosh.Email

  alias HighSociety.Mailer
  alias HighSociety.Support.Report

  @doc """
  Delivers a support report to the support inbox, with the reporter set as
  the reply-to address so replying goes straight to them.
  """
  def deliver_report(%Report{} = report) do
    email =
      new()
      |> to(Application.get_env(:high_society, :support_email))
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> reply_to(report.email)
      |> subject("New support request from #{report.name}")
      |> text_body("""
      New support request submitted via highsociety.cc

      Name: #{report.name}
      Email: #{report.email}

      Message:
      #{report.message}
      """)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, report}
    end
  end
end
