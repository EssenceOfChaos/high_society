defmodule HighSociety.Factory do
  use ExMachina.Ecto, repo: HighSociety.Repo

  def user_factory(:user, _attrs) do
    %HighSociety.Accounts.User{
      email: "batman@example.com",
      username: "batman",
      password_hash: "argon2-abc123"
    }
  end


  def post_factory(:post, _attrs) do
    %HighSociety.SubReddit.Post{
      title: "Use ExMachina.",
      content: "Oh, yeah!",
      likes: 1,
      user_id: build(:user),
    }
  end
end