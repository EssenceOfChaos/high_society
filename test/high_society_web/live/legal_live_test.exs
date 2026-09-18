defmodule HighSocietyWeb.LegalLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "tournament rules" do
    test "is reachable by a guest, no login required" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/tournament/rules")

      assert html =~ "Official Tournament Rules"
    end

    test "covers the no-purchase-necessary, eligibility, prize, and KYC requirements", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/tournament/rules")

      assert html =~ "NO PURCHASE OR PAYMENT OF ANY KIND IS NECESSARY"
      assert html =~ "18 years old"
      assert html =~ "$75 USD worth of Ethereum"
      assert html =~ "$25 USD worth of Ethereum"
      assert html =~ "exclusive High Society NFT"
      assert html =~ "KYC"
      assert html =~ "7 days"
    end
  end

  @other_pages %{
    "/terms" => "Terms and Conditions",
    "/privacy" => "Privacy Policy",
    "/cookies" => "Cookies Policy",
    "/responsible-gaming" => "Responsible Gaming Statement",
    "/age-restriction" => "Age Restriction"
  }

  for {path, title} <- @other_pages do
    test "#{path} still renders its own title unaffected by the new page" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, unquote(path))
      assert html =~ unquote(title)
    end
  end
end
