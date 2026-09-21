defmodule HighSocietyWeb.SupportLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  test "renders the support form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/support")

    assert html =~ "Contact support"
  end

  test "submitting a valid report sends an email and redirects home", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/support")

    {:ok, _view, html} =
      view
      |> form("#support_form", %{
        "report" => %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "category" => "legal",
          "message" => "Requesting a copy of our data processing agreement."
        }
      })
      |> render_submit()
      |> follow_redirect(conn, ~p"/")

    assert html =~ "Thanks! Your message has been sent"

    support_email = Application.get_env(:high_society, :support_email)
    assert_email_sent(to: support_email, reply_to: "ada@example.com")
  end

  test "submitting an invalid report re-renders errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/support")

    html =
      view
      |> form("#support_form", %{
        "report" => %{"name" => "", "email" => "bad", "message" => "short"}
      })
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    refute_email_sent()
  end

  test "picking the Gaming category reveals a game select, required to submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/support")

    refute has_element?(view, "#report_game")

    html =
      view
      |> form("#support_form", %{"report" => %{"category" => "gaming"}})
      |> render_change()

    assert html =~ "Which game?"
    assert has_element?(view, "#report_game")

    html =
      view
      |> form("#support_form", %{
        "report" => %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "category" => "gaming",
          "message" => "The poker table won't let me fold."
        }
      })
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    refute_email_sent()
  end
end
