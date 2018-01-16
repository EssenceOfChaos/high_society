defmodule HighSociety.SubReddit.Post do
  use Ecto.Schema
  import Ecto.Changeset
  alias HighSociety.SubReddit.Post

  @required_fields ~w(title content user_id)a
  @optional_fields ~w(likes)

  schema "posts" do

    field :title, :string
    field :content
    field :likes, :integer

    belongs_to :user, HighSociety.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:user)
  end
end
