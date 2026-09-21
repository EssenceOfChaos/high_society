defmodule HighSociety.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias HighSociety.Repo

  alias HighSociety.Accounts.{User, UserToken, UserNotifier, TokenTransaction}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  The name to show for a user wherever a player-facing name is needed
  (the poker table, leaderboards, ...) - their own `display_name` if
  they've set one (see `HighSociety.Accounts.User.display_name_changeset/3`),
  otherwise the part of their email before the `@`.

  ## Examples

      iex> display_name(%User{display_name: "Freddy"})
      "Freddy"

      iex> display_name(%User{display_name: nil, email: "freddy@example.com"})
      "freddy"

  """
  @spec display_name(User.t()) :: String.t()
  def display_name(%User{display_name: display_name}) when is_binary(display_name),
    do: display_name

  def display_name(%User{email: email}), do: email |> String.split("@") |> hd()

  ## Tokens

  # `tokens_balance` and other money fields store integer amounts, carried
  # over unscaled from when they were cents ($1.00 = 100) - see
  # `HighSociety.Tokens`.
  @blackjack_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Blackjack."
  @spec blackjack_starting_token_amount() :: pos_integer()
  def blackjack_starting_token_amount, do: @blackjack_starting_token_amount

  @doc """
  Grants the user's one-time starting balance of
  `#{@blackjack_starting_token_amount}` Tokens for Blackjack. Atomic and
  idempotent: the update only matches a row that hasn't claimed yet, so two
  concurrent requests for the same user can't both succeed. Also writes a
  `TokenTransaction` ledger row in the same transaction as the grant.

  ## Examples

      iex> claim_blackjack_tokens(user)
      {:ok, %User{tokens_balance: 2_500_000}}

      iex> claim_blackjack_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_blackjack_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_blackjack_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_blackjack_tokens_at,
      @blackjack_starting_token_amount,
      "starting_grant_blackjack"
    )
  end

  @battleship_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Battleship."
  @spec battleship_starting_token_amount() :: pos_integer()
  def battleship_starting_token_amount, do: @battleship_starting_token_amount

  @doc """
  Grants the user's one-time Battleship starting balance of
  `#{@battleship_starting_token_amount}` Tokens. Atomic and idempotent, and
  tracked separately from `claim_blackjack_tokens/1` and
  `claim_poker_tokens/1` since each game offers its own one-time grant. Also
  writes a `TokenTransaction` ledger row in the same transaction as the
  grant.

  ## Examples

      iex> claim_battleship_tokens(user)
      {:ok, %User{tokens_balance: 500_000}}

      iex> claim_battleship_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_battleship_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_battleship_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_battleship_tokens_at,
      @battleship_starting_token_amount,
      "starting_grant_battleship"
    )
  end

  @doc """
  Atomically adjusts `user`'s `tokens_balance` by `delta` (negative to
  debit, positive to credit), guarded at the database level so the balance
  can never go negative even under concurrent requests for the same user.
  Also writes a `TokenTransaction` audit row in the same transaction as the
  balance update - `source` (a short, stable string like `"blackjack_bet"`)
  identifies what caused the change, and `metadata` can carry arbitrary
  extra context for analytics. There is no way to adjust `tokens_balance`
  through this module without that ledger row being written alongside it.

  ## Examples

      iex> adjust_tokens_balance(user, -50_000, "blackjack_bet")
      {:ok, %User{tokens_balance: 2_450_000}}

      iex> adjust_tokens_balance(broke_user, -500, "blackjack_bet")
      {:error, :insufficient_funds}

  """
  @spec adjust_tokens_balance(User.t(), integer(), String.t(), map()) ::
          {:ok, User.t()} | {:error, :insufficient_funds}
  def adjust_tokens_balance(%User{} = user, delta, source, metadata \\ %{})
      when is_integer(delta) and is_binary(source) and is_map(metadata) do
    Repo.transact(fn ->
      {count, _} =
        Repo.update_all(
          from(u in User, where: u.id == ^user.id and u.tokens_balance + ^delta >= 0),
          inc: [tokens_balance: delta]
        )

      if count == 1 do
        insert_token_transaction!(user.id, delta, source, metadata)
        {:ok, get_user!(user.id)}
      else
        {:error, :insufficient_funds}
      end
    end)
  end

  @poker_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Poker."
  @spec poker_starting_token_amount() :: pos_integer()
  def poker_starting_token_amount, do: @poker_starting_token_amount

  @doc """
  Grants the user's one-time Poker starting balance of
  `#{@poker_starting_token_amount}` Tokens. Atomic and idempotent, and
  tracked separately from `claim_blackjack_tokens/1` since each game offers
  its own one-time grant. Also writes a `TokenTransaction` ledger row in the
  same transaction as the grant.

  ## Examples

      iex> claim_poker_tokens(user)
      {:ok, %User{tokens_balance: 500_000}}

      iex> claim_poker_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_poker_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_poker_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_poker_tokens_at,
      @poker_starting_token_amount,
      "starting_grant_poker"
    )
  end

  @slots_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Slots."
  @spec slots_starting_token_amount() :: pos_integer()
  def slots_starting_token_amount, do: @slots_starting_token_amount

  @doc """
  Grants the user's one-time Slots starting balance of
  `#{@slots_starting_token_amount}` Tokens. Atomic and idempotent, and
  tracked separately from the other games' claims since each offers its own
  one-time grant. Also writes a `TokenTransaction` ledger row in the same
  transaction as the grant.

  ## Examples

      iex> claim_slots_tokens(user)
      {:ok, %User{tokens_balance: 500_000}}

      iex> claim_slots_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_slots_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_slots_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_slots_tokens_at,
      @slots_starting_token_amount,
      "starting_grant_slots"
    )
  end

  @roulette_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Roulette."
  @spec roulette_starting_token_amount() :: pos_integer()
  def roulette_starting_token_amount, do: @roulette_starting_token_amount

  @doc """
  Grants the user's one-time Roulette starting balance of
  `#{@roulette_starting_token_amount}` Tokens. Atomic and idempotent, and
  tracked separately from the other games' claims since each offers its own
  one-time grant. Also writes a `TokenTransaction` ledger row in the same
  transaction as the grant.

  ## Examples

      iex> claim_roulette_tokens(user)
      {:ok, %User{tokens_balance: 500_000}}

      iex> claim_roulette_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_roulette_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_roulette_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_roulette_tokens_at,
      @roulette_starting_token_amount,
      "starting_grant_roulette"
    )
  end

  @zombie_attack_starting_token_amount 5_000 * 100

  @doc "The one-time starting Token grant amount for Zombie Attack."
  @spec zombie_attack_starting_token_amount() :: pos_integer()
  def zombie_attack_starting_token_amount, do: @zombie_attack_starting_token_amount

  @doc """
  Grants the user's one-time Zombie Attack starting balance of
  `#{@zombie_attack_starting_token_amount}` Tokens. Atomic and idempotent,
  and tracked separately from the other games' claims since each offers its
  own one-time grant. Also writes a `TokenTransaction` ledger row in the
  same transaction as the grant.

  ## Examples

      iex> claim_zombie_attack_tokens(user)
      {:ok, %User{tokens_balance: 500_000}}

      iex> claim_zombie_attack_tokens(already_claimed_user)
      {:error, :already_claimed}

  """
  @spec claim_zombie_attack_tokens(User.t()) :: {:ok, User.t()} | {:error, :already_claimed}
  def claim_zombie_attack_tokens(%User{} = user) do
    claim_starting_grant(
      user,
      :claimed_zombie_attack_tokens_at,
      @zombie_attack_starting_token_amount,
      "starting_grant_zombie_attack"
    )
  end

  # Shared by every `claim_*_tokens/1` above: an atomic, idempotent grant
  # guarded by `claimed_at_field` being unset, plus its matching ledger row,
  # all in one transaction.
  defp claim_starting_grant(%User{} = user, claimed_at_field, amount, source) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      {count, _} =
        Repo.update_all(
          from(u in User, where: u.id == ^user.id and is_nil(field(u, ^claimed_at_field))),
          inc: [tokens_balance: amount],
          set: [{claimed_at_field, now}]
        )

      if count == 1 do
        insert_token_transaction!(user.id, amount, source, %{})
        {:ok, get_user!(user.id)}
      else
        {:error, :already_claimed}
      end
    end)
  end

  defp insert_token_transaction!(user_id, amount, source, metadata) do
    %TokenTransaction{}
    |> TokenTransaction.changeset(%{
      user_id: user_id,
      amount: amount,
      source: source,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  @doc """
  Lists `user`'s Token ledger, most recent first - the audit trail behind
  `tokens_balance` (see `adjust_tokens_balance/4`). Never used to compute a
  balance, only to explain how one got where it is.

  ## Options

    * `:limit` - max rows to return. Defaults to 50. Pass `nil` for no cap
      (e.g. a full CSV export).
    * `:source` - only rows with this exact `source` (e.g. `"blackjack_bet"`).
    * `:before` - a `{inserted_at, id}` cursor (the last row of a previous
      page, e.g. `{t.inserted_at, t.id}`) - only rows strictly older than
      it are returned. For "load more" pagination over this same
      `desc: inserted_at, desc: id` ordering.

  ## Examples

      iex> list_token_transactions(user)
      [%TokenTransaction{}, ...]

      iex> list_token_transactions(user, source: "poker_cash_out", limit: 10)
      [%TokenTransaction{}, ...]

  """
  @spec list_token_transactions(User.t(), keyword()) :: [TokenTransaction.t()]
  def list_token_transactions(%User{} = user, opts \\ []) do
    TokenTransaction
    |> where([t], t.user_id == ^user.id)
    |> maybe_filter_source(Keyword.get(opts, :source))
    |> maybe_cursor(Keyword.get(opts, :before))
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  defp maybe_filter_source(query, nil), do: query
  defp maybe_filter_source(query, source), do: where(query, [t], t.source == ^source)

  defp maybe_cursor(query, nil), do: query

  defp maybe_cursor(query, {%DateTime{} = inserted_at, id}) do
    where(
      query,
      [t],
      t.inserted_at < ^inserted_at or (t.inserted_at == ^inserted_at and t.id < ^id)
    )
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc """
  Records that the user was active today, for badge progression. Atomic and
  idempotent - calling it more than once on the same UTC day is a no-op, so
  it's safe to call on every authenticated page load.

  ## Examples

      iex> record_activity(user)
      %User{active_days_count: 4, last_active_on: ~D[2026-09-03]}

  """
  @spec record_activity(User.t()) :: User.t()
  def record_activity(%User{} = user) do
    today = Date.utc_today()

    {count, _} =
      Repo.update_all(
        from(u in User,
          where: u.id == ^user.id and (is_nil(u.last_active_on) or u.last_active_on != ^today)
        ),
        inc: [active_days_count: 1],
        set: [last_active_on: today]
      )

    # Patch the struct in place rather than reloading from the database:
    # a reload would drop virtual fields like `authenticated_at` that the
    # caller's session-token lookup set, which `sudo_mode?/2` depends on.
    if count == 1 do
      %{user | active_days_count: user.active_days_count + 1, last_active_on: today}
    else
      user
    end
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Whether `user` is allowed into the `/admin` section - membership in the
  `:admin_emails` config list, checked by email since there's no `role`
  field on `User` (see `config/config.exs` and `config/runtime.exs`).
  """
  @spec admin?(User.t() | nil) :: boolean()
  def admin?(%User{email: email}) when is_binary(email) do
    email in Application.get_env(:high_society, :admin_emails, [])
  end

  def admin?(_user), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `HighSociety.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `HighSociety.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user display name.

  See `HighSociety.Accounts.User.display_name_changeset/3` for a list of
  supported options.

  ## Examples

      iex> change_user_display_name(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_display_name(user, attrs \\ %{}, opts \\ []) do
    User.display_name_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user display name. Not a security-sensitive change (unlike
  email/password), so this doesn't require sudo mode or invalidate any
  existing sessions.

  ## Examples

      iex> update_user_display_name(user, %{display_name: "Freddy"})
      {:ok, %User{}}

      iex> update_user_display_name(user, %{display_name: "a"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_display_name(user, attrs) do
    user
    |> User.display_name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's poker table settings (card back, felt color, muck
  preference). See `HighSociety.Accounts.User.poker_settings_changeset/2`.

  ## Examples

      iex> update_poker_settings(user, %{felt_color: "blue"})
      {:ok, %User{}}

      iex> update_poker_settings(user, %{felt_color: "purple"})
      {:error, %Ecto.Changeset{}}

  """
  def update_poker_settings(user, attrs) do
    user
    |> User.poker_settings_changeset(attrs)
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        with {:ok, {confirmed_user, _expired_tokens}} = result <-
               user
               |> User.confirm_changeset()
               |> update_user_and_delete_all_tokens() do
          UserNotifier.deliver_welcome_email(confirmed_user)
          result
        end

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
