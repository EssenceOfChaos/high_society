defmodule HighSociety.AccountsTest do
  use HighSociety.DataCase

  alias HighSociety.Accounts

  import HighSociety.AccountsFixtures
  alias HighSociety.Accounts.{User, UserToken, TokenTransaction}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "claim_blackjack_tokens/1" do
    test "grants the starting token amount and records when it was claimed" do
      user = user_fixture()
      assert user.tokens_balance == 0
      assert user.claimed_blackjack_tokens_at == nil

      assert {:ok, updated} = Accounts.claim_blackjack_tokens(user)

      assert updated.tokens_balance == Accounts.blackjack_starting_token_amount()
      assert updated.claimed_blackjack_tokens_at != nil
    end

    test "cannot be claimed a second time" do
      user = user_fixture()
      {:ok, updated} = Accounts.claim_blackjack_tokens(user)

      assert {:error, :already_claimed} = Accounts.claim_blackjack_tokens(updated)

      assert Accounts.get_user!(user.id).tokens_balance ==
               Accounts.blackjack_starting_token_amount()
    end

    test "writes exactly one ledger row on first claim, none on a repeat" do
      user = user_fixture()
      {:ok, updated} = Accounts.claim_blackjack_tokens(user)

      assert [transaction] = Repo.all(TokenTransaction)
      assert transaction.user_id == user.id
      assert transaction.amount == Accounts.blackjack_starting_token_amount()
      assert transaction.source == "starting_grant_blackjack"

      assert {:error, :already_claimed} = Accounts.claim_blackjack_tokens(updated)
      assert Repo.aggregate(TokenTransaction, :count) == 1
    end
  end

  describe "adjust_tokens_balance/4" do
    test "credits the user's tokens_balance" do
      user = user_fixture()
      assert {:ok, updated} = Accounts.adjust_tokens_balance(user, 500, "test_funding")
      assert updated.tokens_balance == 500
    end

    test "debits the user's tokens_balance when funds are sufficient" do
      user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 1_000, "test_funding")

      assert {:ok, updated} = Accounts.adjust_tokens_balance(user, -400, "blackjack_bet")
      assert updated.tokens_balance == 600
    end

    test "rejects a debit that would overdraw the balance, leaving it unchanged" do
      user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 100, "test_funding")

      assert {:error, :insufficient_funds} =
               Accounts.adjust_tokens_balance(user, -101, "blackjack_bet")

      assert Accounts.get_user!(user.id).tokens_balance == 100
    end

    test "writes a TokenTransaction ledger row with the given source and metadata on success" do
      user = user_fixture()

      assert {:ok, _updated} =
               Accounts.adjust_tokens_balance(user, 500, "blackjack_payout", %{hand_id: "abc"})

      assert [transaction] = Repo.all(TokenTransaction)
      assert transaction.user_id == user.id
      assert transaction.amount == 500
      assert transaction.source == "blackjack_payout"
      assert transaction.metadata == %{"hand_id" => "abc"}
    end

    test "writes no ledger row when the adjustment is rejected" do
      user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 100, "test_funding")

      assert {:error, :insufficient_funds} =
               Accounts.adjust_tokens_balance(user, -101, "blackjack_bet")

      assert Repo.aggregate(TokenTransaction, :count) == 1
    end
  end

  describe "list_token_transactions/2" do
    test "returns the user's transactions, most recent first" do
      user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 100, "test_funding")
      {:ok, user} = Accounts.adjust_tokens_balance(user, -50, "blackjack_bet")
      {:ok, _user} = Accounts.adjust_tokens_balance(user, 75, "blackjack_payout")

      assert [third, second, first] = Accounts.list_token_transactions(user)
      assert {third.source, third.amount} == {"blackjack_payout", 75}
      assert {second.source, second.amount} == {"blackjack_bet", -50}
      assert {first.source, first.amount} == {"test_funding", 100}
    end

    test "only returns the given user's own transactions" do
      user = user_fixture()
      other_user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 100, "test_funding")
      {:ok, _other_user} = Accounts.adjust_tokens_balance(other_user, 100, "test_funding")

      assert [transaction] = Accounts.list_token_transactions(user)
      assert transaction.user_id == user.id
    end

    test "respects the :limit option" do
      user = user_fixture()

      for _ <- 1..3 do
        {:ok, user} = Accounts.adjust_tokens_balance(user, 10, "test_funding")
        user
      end

      assert length(Accounts.list_token_transactions(user, limit: 2)) == 2
    end

    test ":limit of nil returns every row, uncapped" do
      user = user_fixture()

      for _ <- 1..3 do
        {:ok, user} = Accounts.adjust_tokens_balance(user, 10, "test_funding")
        user
      end

      assert length(Accounts.list_token_transactions(user, limit: nil)) == 3
    end

    test "respects the :before cursor, for paging past a previous page" do
      user = user_fixture()

      for _ <- 1..3 do
        {:ok, user} = Accounts.adjust_tokens_balance(user, 10, "test_funding")
        user
      end

      assert [newest] = Accounts.list_token_transactions(user, limit: 1)

      rest = Accounts.list_token_transactions(user, before: {newest.inserted_at, newest.id})
      assert length(rest) == 2
      refute newest.id in Enum.map(rest, & &1.id)
    end

    test "respects the :source option" do
      user = user_fixture()
      {:ok, user} = Accounts.adjust_tokens_balance(user, 100, "blackjack_bet")
      {:ok, _user} = Accounts.adjust_tokens_balance(user, 50, "blackjack_payout")

      assert [transaction] = Accounts.list_token_transactions(user, source: "blackjack_payout")
      assert transaction.source == "blackjack_payout"
    end

    test "returns an empty list for a user with no transactions" do
      assert Accounts.list_token_transactions(user_fixture()) == []
    end
  end

  describe "admin?/1" do
    setup do
      previous = Application.get_env(:high_society, :admin_emails, [])
      on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
      :ok
    end

    test "is false for a user not on the admin_emails list" do
      refute Accounts.admin?(user_fixture())
    end

    test "is false for nil" do
      refute Accounts.admin?(nil)
    end

    test "is true for a user whose email is on the admin_emails list" do
      user = user_fixture(%{email: "admin@example.com"})
      Application.put_env(:high_society, :admin_emails, ["admin@example.com"])

      assert Accounts.admin?(user)
    end
  end

  describe "record_activity/1" do
    test "starts a brand new user at zero active days" do
      user = user_fixture()
      assert user.active_days_count == 0
      assert user.last_active_on == nil
    end

    test "counts the first active day" do
      user = user_fixture()
      updated = Accounts.record_activity(user)

      assert updated.active_days_count == 1
      assert updated.last_active_on == Date.utc_today()
    end

    test "is idempotent within the same day" do
      user = user_fixture()
      Accounts.record_activity(user)
      Accounts.record_activity(user)

      assert Accounts.get_user!(user.id).active_days_count == 1
    end

    test "counts a new day again once last_active_on has moved on" do
      user = user_fixture()

      user
      |> Ecto.Changeset.change(active_days_count: 1, last_active_on: ~D[2000-01-01])
      |> HighSociety.Repo.update!()

      updated = Accounts.record_activity(Accounts.get_user!(user.id))
      assert updated.active_days_count == 2
      assert updated.last_active_on == Date.utc_today()
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_display_name/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_display_name(%User{})
      assert changeset.required == [:display_name]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_display_name(%User{}, %{"display_name" => "Freddy"},
          validate_unique: false
        )

      assert changeset.valid?
      assert get_change(changeset, :display_name) == "Freddy"
    end
  end

  describe "update_user_display_name/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the display name", %{user: user} do
      assert {:ok, updated} = Accounts.update_user_display_name(user, %{display_name: "Freddy"})
      assert updated.display_name == "Freddy"
      assert Repo.get!(User, user.id).display_name == "Freddy"
    end

    test "trims surrounding whitespace", %{user: user} do
      assert {:ok, updated} =
               Accounts.update_user_display_name(user, %{display_name: "  Freddy  "})

      assert updated.display_name == "Freddy"
    end

    test "rejects a name that's too short", %{user: user} do
      assert {:error, changeset} = Accounts.update_user_display_name(user, %{display_name: "ab"})
      assert "should be at least 3 character(s)" in errors_on(changeset).display_name
    end

    test "rejects a name that's too long", %{user: user} do
      too_long = String.duplicate("a", 21)

      assert {:error, changeset} =
               Accounts.update_user_display_name(user, %{display_name: too_long})

      assert "should be at most 20 character(s)" in errors_on(changeset).display_name
    end

    test "rejects characters outside letters/numbers/spaces/underscores/hyphens", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_display_name(user, %{display_name: "bad@name!"})

      assert changeset.errors[:display_name]
    end

    test "rejects profanity", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_display_name(user, %{display_name: "shit"})

      assert "is not allowed" in errors_on(changeset).display_name
    end

    test "rejects profanity embedded as a whole word but allows innocent substrings", %{
      user: user
    } do
      assert {:error, _changeset} =
               Accounts.update_user_display_name(user, %{display_name: "big ass fan"})

      assert {:ok, _updated} =
               Accounts.update_user_display_name(user, %{display_name: "classy player"})
    end

    test "rejects a display name already taken by another user (case-insensitively)", %{
      user: user
    } do
      other = user_fixture()
      {:ok, _} = Accounts.update_user_display_name(other, %{display_name: "Freddy"})

      assert {:error, changeset} =
               Accounts.update_user_display_name(user, %{display_name: "freddy"})

      assert "has already been taken" in errors_on(changeset).display_name
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
