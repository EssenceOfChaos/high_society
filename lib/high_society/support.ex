defmodule HighSociety.Support do
  @moduledoc """
  Handles support reports submitted from the site and emails them to the
  support inbox.
  """

  alias HighSociety.Support.Report
  alias HighSociety.Support.Notifier

  @doc """
  Returns a changeset for tracking report changes.
  """
  def change_report(%Report{} = report, attrs \\ %{}) do
    Report.changeset(report, attrs)
  end

  @doc """
  Validates and delivers a support report to the support inbox.
  """
  def send_report(attrs) do
    with {:ok, report} <- Report.changeset(%Report{}, attrs) |> Ecto.Changeset.apply_action(:save) do
      Notifier.deliver_report(report)
    end
  end
end
