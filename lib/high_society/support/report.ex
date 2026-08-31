defmodule HighSociety.Support.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :message, :string
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:name, :email, :message])
    |> validate_required([:name, :email, :message])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:name, max: 160)
    |> validate_length(:email, max: 160)
    |> validate_length(:message, min: 10, max: 4000)
  end
end
