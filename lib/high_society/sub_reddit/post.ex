defmodule HighSociety.SubReddit.Post do
  use Ecto.Schema
  import Ecto.Changeset
  alias HighSociety.SubReddit.Post


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
    |> cast(attrs, [:content, :title, :likes])
    |> validate_required([:content, :title])
  end
end
