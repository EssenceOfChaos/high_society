defmodule HighSocietyWeb.EmailControllerTest do
  use HighSocietyWeb.ConnCase
  import HighSociety.Factory
  import Bamboo.Email

  test "creating an email" do
    email = new_email(
      to: "fjschiller@gmail.com",
      from: "example@aol.com",
      subject: "Testing Emails",
      html_body: "<h1>Hello, there!</h1> <p> Here is a bamboo email. </p>",
      text_body: "Hello, there!\n\nHere is a bamboo email."
    )

    assert email.to == "fjschiller@gmail.com"
    assert email.from == "example@aol.com"
    assert email.subject == "Testing Emails"
    assert email.html_body =~ ~r/bamboo/
    assert email.text_body =~ ~r/bamboo/
  end


end