defmodule HighSociety.Support.Report do
  @moduledoc """
  A support request, whether submitted through `/support`'s form or
  received as an inbound email (see `HighSociety.Support.receive_inbound_email/1`).
  `category` (and, for a gaming-related one, `game`) exists purely for
  triage - sorting an otherwise single, mixed inbox of everything from bug
  reports to legal inquiries into buckets a human (or eventually an
  automated router) can prioritize.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :category, :string
    field :game, :string
    field :message, :string
  end

  # {stored value, display label} - shown as-is in the form's dropdown and
  # reused for the label prefixed onto the notification email's subject.
  @categories [
    {"gaming", "Gaming"},
    {"poker_tournament", "Poker Tournament"},
    {"account", "Account Assistance"},
    {"tokens", "Tokens / Balance"},
    {"kyc", "KYC / Identity Verification"},
    {"responsible_gaming", "Responsible Gaming"},
    {"bug", "Bug Report"},
    {"security", "Security Concern"},
    {"legal", "Legal Inquiry"},
    {"media", "Media & Business Inquiry"},
    {"other", "Other"}
  ]

  # Never offered in the form - only ever set by `receive_inbound_email/1`,
  # so an unsorted raw email is still visibly distinct from a human
  # deliberately picking "Other" through the form.
  @inbound_email_category {"email", "Received by Email (Uncategorized)"}

  @games [
    {"war", "War"},
    {"blackjack", "Blackjack"},
    {"slots", "Slots"},
    {"roulette", "Roulette"},
    {"poker", "Poker"},
    {"battleship", "Battleship"},
    {"zombie_attack", "Zombie Attack"},
    {"other", "Other / not sure"}
  ]

  # Categories specific enough to a game that asking which one is worth the
  # extra field.
  @categories_with_game ~w(gaming bug)

  @doc "The `{value, label}` options for the form's category select."
  def category_options, do: @categories

  @doc "The `{value, label}` options for the form's game select."
  def game_options, do: @games

  @doc "The display label for a stored category value (any value ever persisted, including the inbound-email one)."
  def category_label(value) do
    case Enum.find([@inbound_email_category | @categories], fn {v, _label} -> v == value end) do
      {_value, label} -> label
      nil -> value
    end
  end

  @doc "The display label for a stored game value, or `nil` if there isn't one."
  def game_label(nil), do: nil

  def game_label(value) do
    case Enum.find(@games, fn {v, _label} -> v == value end) do
      {_value, label} -> label
      nil -> value
    end
  end

  @doc "Whether `category` prompts for a specific game."
  def category_with_game?(category), do: category in @categories_with_game

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:name, :email, :category, :game, :message])
    |> validate_required([:name, :email, :category, :message])
    |> validate_inclusion(:category, valid_categories())
    |> validate_game()
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:name, max: 160)
    |> validate_length(:email, max: 160)
    |> validate_length(:message, min: 10, max: 4000)
  end

  defp validate_game(changeset) do
    if category_with_game?(get_field(changeset, :category)) do
      changeset |> validate_required([:game]) |> validate_inclusion(:game, valid_games())
    else
      changeset
    end
  end

  defp valid_categories, do: Enum.map([@inbound_email_category | @categories], &elem(&1, 0))
  defp valid_games, do: Enum.map(@games, &elem(&1, 0))
end
