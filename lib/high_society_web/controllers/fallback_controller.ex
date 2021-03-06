defmodule HighSocietyWeb.FallbackController do
  use HighSocietyWeb, :controller


    def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
      conn
      |> put_status(:unprocessable_entity)
      |> render(HighSocietyWeb.ChangesetView, "error.json", changeset: changeset)
    end

    def call(conn, {:error, :not_found}) do
      conn
      |> put_status(:not_found)
      |> render(HighSocietyWeb.ErrorView, :"404")
    end



end