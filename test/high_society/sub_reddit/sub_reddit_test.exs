defmodule HighSociety.SubRedditTest do
  use HighSociety.DataCase

  alias HighSociety.SubReddit

  describe "posts" do
    alias HighSociety.SubReddit.Post

    @valid_attrs %{content: "some content", name: "some name", votes: 42}
    @update_attrs %{content: "some updated content", name: "some updated name", votes: 43}
    @invalid_attrs %{content: nil, name: nil, votes: nil}

    def post_fixture(attrs \\ %{}) do
      {:ok, post} =
        attrs
        |> Enum.into(@valid_attrs)
        |> SubReddit.create_post()

      post
    end

    test "list_posts/0 returns all posts" do
      post = post_fixture()
      assert SubReddit.list_posts() == [post]
    end

    test "get_post!/1 returns the post with given id" do
      post = post_fixture()
      assert SubReddit.get_post!(post.id) == post
    end

    test "create_post/1 with valid data creates a post" do
      assert {:ok, %Post{} = post} = SubReddit.create_post(@valid_attrs)
      assert post.content == "some content"
      assert post.name == "some name"
      assert post.votes == 42
    end

    test "create_post/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = SubReddit.create_post(@invalid_attrs)
    end

    test "update_post/2 with valid data updates the post" do
      post = post_fixture()
      assert {:ok, post} = SubReddit.update_post(post, @update_attrs)
      assert %Post{} = post
      assert post.content == "some updated content"
      assert post.name == "some updated name"
      assert post.votes == 43
    end

    test "update_post/2 with invalid data returns error changeset" do
      post = post_fixture()
      assert {:error, %Ecto.Changeset{}} = SubReddit.update_post(post, @invalid_attrs)
      assert post == SubReddit.get_post!(post.id)
    end

    test "delete_post/1 deletes the post" do
      post = post_fixture()
      assert {:ok, %Post{}} = SubReddit.delete_post(post)
      assert_raise Ecto.NoResultsError, fn -> SubReddit.get_post!(post.id) end
    end

    test "change_post/1 returns a post changeset" do
      post = post_fixture()
      assert %Ecto.Changeset{} = SubReddit.change_post(post)
    end
    test "upvote_post/1 add 1 to post.votes" do
      post = post_fixture()
      initial_vote_count = post.votes
      assert {:ok, post} = SubReddit.upvote_post(post)
      assert %Post{} = post
      assert post.votes == initial_vote_count + 1
    end

    test "downvote_post/1 remove 1 from post.votes" do
      post = post_fixture()
      initial_vote_count = post.votes
      assert {:ok, post} = SubReddit.downvote_post(post)
      assert %Post{} = post
      assert post.votes == initial_vote_count - 1
end

  end
end
