defmodule HighSociety.Accounts.TokenTransaction do
  @moduledoc """
  A write-only ledger row recording one change to a user's
  `tokens_balance`. Always inserted in the same database transaction as
  the balance update itself (see `HighSociety.Accounts.adjust_tokens_balance/4`
  and the `claim_*_tokens/1` starting grants), so it's structurally
  impossible to move a balance without a matching audit row. Never read
  back to compute a balance - `tokens_balance` stays the fast, race-safe
  source of truth for that.
  """
  @type t :: %__MODULE__{
          user_id: pos_integer(),
          amount: integer(),
          source: String.t(),
          metadata: map(),
          inserted_at: DateTime.t()
        }

  use Ecto.Schema
  import Ecto.Changeset

  schema "token_transactions" do
    field :amount, :integer
    field :source, :string
    field :metadata, :map, default: %{}
    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(token_transaction, attrs) do
    token_transaction
    |> cast(attrs, [:user_id, :amount, :source, :metadata])
    |> validate_required([:user_id, :amount, :source])
    |> validate_length(:source, max: 50)
    |> foreign_key_constraint(:user_id)
  end
end
