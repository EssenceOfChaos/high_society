defmodule HighSociety.Accounts.Users do
  @moduledoc """
  The boundry for the Users system
  """
  alias HighSociety.Repo
  alias HighSociety.Accounts.User


  def update_user(user, attrs) do
  user
  |> User.changeset(attrs)
  |> Repo.update
  end


end
