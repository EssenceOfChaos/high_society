defmodule HighSociety.Social.SocialPost do
  @moduledoc """
  A draft or sent post to a connected platform (`"x"` or `"threads"`) -
  created automatically off an in-app event (e.g. a tournament finishing)
  and held as `"pending"` until an admin approves it, unless
  `:social_auto_post?` is enabled (see `HighSociety.Social`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          platform: String.t(),
          status: String.t(),
          source: String.t(),
          body: String.t(),
          tournament_id: integer() | nil,
          reviewed_by_user_id: integer() | nil,
          platform_post_id: String.t() | nil,
          posted_at: DateTime.t() | nil,
          error: String.t() | nil
        }

  schema "social_posts" do
    field :platform, :string
    field :status, :string, default: "pending"
    field :source, :string
    field :body, :string
    field :platform_post_id, :string
    field :posted_at, :utc_datetime
    field :error, :string

    belongs_to :tournament, HighSociety.Tournaments.PokerTournament
    belongs_to :reviewed_by, HighSociety.Accounts.User, foreign_key: :reviewed_by_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(social_post, attrs) do
    social_post
    |> cast(attrs, [:platform, :source, :body, :tournament_id])
    |> validate_required([:platform, :source, :body])
    |> validate_inclusion(:platform, ~w(x threads))
  end

  @doc false
  def body_changeset(social_post, attrs) do
    cast(social_post, attrs, [:body])
    |> validate_required([:body])
  end

  @doc false
  def reviewed_changeset(social_post, attrs) do
    cast(social_post, attrs, [:status, :reviewed_by_user_id])
    |> validate_required([:status, :reviewed_by_user_id])
    |> validate_inclusion(:status, ~w(approved rejected))
  end

  @doc false
  def posted_changeset(social_post, attrs) do
    cast(social_post, attrs, [:status, :platform_post_id, :posted_at, :error])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(posted failed))
  end
end
