defmodule HighSocietyWeb.PostController do
  use HighSocietyWeb, :controller

  alias HighSociety.SubReddit
  alias HighSociety.SubReddit.Post

  def index(conn, _params) do
    posts = SubReddit.list_posts()
    render(conn, "index.html", posts: posts)
  end

  def new(conn, _params) do
    changeset = SubReddit.change_post(%Post{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"post" => post_params}) do
    case SubReddit.create_post(post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post created successfully.")
        |> redirect(to: post_path(conn, :show, post))
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    post = SubReddit.get_post!(id)
    render(conn, "show.html", post: post)
  end

  def edit(conn, %{"id" => id}) do
    post = SubReddit.get_post!(id)
    changeset = SubReddit.change_post(post)
    render(conn, "edit.html", post: post, changeset: changeset)
  end

  def update(conn, %{"id" => id, "post" => post_params}) do
    post = SubReddit.get_post!(id)

    case SubReddit.update_post(post, post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post updated successfully.")
        |> redirect(to: post_path(conn, :show, post))
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", post: post, changeset: changeset)
    end
  end

  def upvote(conn, %{"id" => id}) do
    post = SubReddit.get_post!(id)

    case SubReddit.upvote_post(post) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post upvoted")
        |> redirect(to: post_path(conn, :index))
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "index.html", post: post, changeset: changeset)
    end
  end

  def downvote(conn, %{"id" => id}) do
    post = SubReddit.get_post!(id)

    case SubReddit.downvote_post(post) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post downvoted")
        |> redirect(to: post_path(conn, :index))
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "index.html", post: post, changeset: changeset)
    end
end

  def delete(conn, %{"id" => id}) do
    post = SubReddit.get_post!(id)
    {:ok, _post} = SubReddit.delete_post(post)

    conn
    |> put_flash(:info, "Post deleted successfully.")
    |> redirect(to: post_path(conn, :index))
  end
end
