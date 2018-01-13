defmodule HighSociety.Factory do
  use ExMachina.Ecto, repo: HighSociety.Repo

  def user_factory do
    %HighSociety.Accounts.User{
      email: "batman@example.com",
      username: "batman",
      password_hash: "argon2-abc123"
    }
  end
end