defmodule HighSociety.Support.InboundEmail do
  @moduledoc """
  An email received at the `mail.highsociety.cc` inbound domain (see
  `HighSociety.Support.receive_inbound_email/1`), held as `"pending"` with
  an AI-suggested category and draft reply (see
  `HighSociety.Support.ClaudeClient`) until an admin edits/approves (which
  sends the reply) or rejects it at `/admin/inbound-emails` - the same
  draft/review/approve shape as `HighSociety.Social.SocialPost`, just
  emailing the sender back instead of posting to a platform.

  `suggested_category` and `draft_reply` are both nullable: a failed or
  unparseable AI call still leaves a normal, reviewable row behind with
  nothing pre-filled, rather than losing the email or blocking on the AI
  call succeeding.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          from_name: String.t(),
          from_email: String.t(),
          subject: String.t() | nil,
          body: String.t(),
          status: String.t(),
          suggested_category: String.t() | nil,
          draft_reply: String.t() | nil,
          reviewed_by_user_id: integer() | nil,
          sent_at: DateTime.t() | nil,
          error: String.t() | nil
        }

  schema "inbound_emails" do
    field :from_name, :string
    field :from_email, :string
    field :subject, :string
    field :body, :string
    field :status, :string, default: "pending"
    field :suggested_category, :string
    field :draft_reply, :string
    field :sent_at, :utc_datetime
    field :error, :string

    belongs_to :reviewed_by, HighSociety.Accounts.User, foreign_key: :reviewed_by_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(inbound_email, attrs) do
    inbound_email
    |> cast(attrs, [:from_name, :from_email, :subject, :body])
    |> validate_required([:from_name, :from_email, :body])
  end

  @doc "Fills in the AI-suggested category/reply after `ClaudeClient.draft_reply/1` succeeds."
  def draft_changeset(inbound_email, attrs) do
    cast(inbound_email, attrs, [:suggested_category, :draft_reply])
  end

  @doc "Lets an admin edit the draft reply before approving it."
  def reply_changeset(inbound_email, attrs) do
    cast(inbound_email, attrs, [:draft_reply])
  end

  @doc false
  def reviewed_changeset(inbound_email, attrs) do
    inbound_email
    |> cast(attrs, [:status, :reviewed_by_user_id])
    |> validate_required([:status, :reviewed_by_user_id])
    |> validate_inclusion(:status, ~w(approved rejected))
  end

  @doc false
  def sent_changeset(inbound_email, attrs) do
    inbound_email
    |> cast(attrs, [:status, :sent_at, :error])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(sent failed))
  end
end
