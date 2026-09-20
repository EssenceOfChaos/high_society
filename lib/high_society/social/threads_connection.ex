defmodule HighSociety.Social.ThreadsConnection do
  @moduledoc """
  The single Threads account (`@High_Societycc`) authorized to post through
  this app - created by the admin-only OAuth handshake at
  `/admin/threads/connect`/`/callback` (see `HighSociety.Social.ThreadsClient`)
  and kept fresh by `HighSociety.Social.ThreadsTokenRefresher`, since the
  long-lived token Meta issues expires roughly every 60 days.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          threads_user_id: String.t(),
          username: String.t() | nil,
          access_token: String.t(),
          expires_at: DateTime.t()
        }

  schema "threads_connections" do
    field :threads_user_id, :string
    field :username, :string
    field :access_token, HighSociety.Encrypted.Binary
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:threads_user_id, :username, :access_token, :expires_at])
    |> validate_required([:threads_user_id, :access_token, :expires_at])
  end
end
