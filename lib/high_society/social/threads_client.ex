defmodule HighSociety.Social.ThreadsClient do
  @moduledoc """
  Thin client for the Threads API (https://developers.facebook.com/docs/threads),
  authenticated as `@High_Societycc` via the long-lived user token stored in
  `HighSociety.Social.ThreadsConnection`. Unlike `HighSociety.Social.XClient`,
  this is a real three-legged OAuth 2.0 flow (see
  `HighSocietyWeb.AdminThreadsController`) with a token that expires and
  must be refreshed (see `HighSociety.Social.ThreadsTokenRefresher`) - there's
  no portal shortcut to a permanent token the way X's OAuth 1.0a offered.
  """

  # Must exactly match the Redirect Callback URL registered in the Meta
  # developer portal for the Threads API use case - Meta rejects the token
  # exchange otherwise. Fixed to the production domain regardless of which
  # host the admin flow is started from, since that's the only URI Meta has
  # on file.
  @redirect_uri "https://highsociety.cc/admin/threads/callback"

  @doc "The URL to send an admin to in order to authorize `@High_Societycc`."
  def authorize_url do
    query =
      URI.encode_query(%{
        "client_id" => app_id(),
        "redirect_uri" => @redirect_uri,
        "scope" => "threads_basic,threads_content_publish",
        "response_type" => "code"
      })

    "https://threads.net/oauth/authorize?" <> query
  end

  @doc "Exchanges the callback's `code` for a short-lived token + the connected account's Threads user id."
  def exchange_code(code) do
    case Req.post(req(),
           url: "/oauth/access_token",
           form: %{
             "client_id" => app_id(),
             "client_secret" => app_secret(),
             "grant_type" => "authorization_code",
             "redirect_uri" => @redirect_uri,
             "code" => code
           }
         ) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token, "user_id" => user_id}}} ->
        {:ok, %{access_token: token, threads_user_id: to_string(user_id)}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc "Exchanges a short-lived token for a long-lived one (valid ~60 days)."
  def exchange_long_lived_token(short_lived_token) do
    get_token_response("/access_token",
      grant_type: "th_exchange_token",
      client_secret: app_secret(),
      access_token: short_lived_token
    )
  end

  @doc "Refreshes a still-valid long-lived token, extending it another ~60 days."
  def refresh_long_lived_token(access_token) do
    get_token_response("/refresh_access_token",
      grant_type: "th_refresh_token",
      access_token: access_token
    )
  end

  @doc "The connected account's `@handle`, for display on the admin page."
  def fetch_username(threads_user_id, access_token) do
    case Req.get(req(),
           url: "/v1.0/#{threads_user_id}",
           params: [fields: "username", access_token: access_token]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"username" => username}}} -> {:ok, username}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  @doc "Posts `text` as a thread from `threads_user_id`, via the create-container-then-publish flow Threads requires."
  def post_thread(threads_user_id, access_token, text) do
    with {:ok, creation_id} <- create_container(threads_user_id, access_token, text) do
      publish_container(threads_user_id, access_token, creation_id)
    end
  end

  defp create_container(threads_user_id, access_token, text) do
    case Req.post(req(),
           url: "/v1.0/#{threads_user_id}/threads",
           form: %{"media_type" => "TEXT", "text" => text, "access_token" => access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} -> {:ok, id}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp publish_container(threads_user_id, access_token, creation_id) do
    case Req.post(req(),
           url: "/v1.0/#{threads_user_id}/threads_publish",
           form: %{"creation_id" => creation_id, "access_token" => access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} -> {:ok, id}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp get_token_response(path, params) do
    case Req.get(req(), url: path, params: params) do
      {:ok,
       %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}} ->
        {:ok, %{access_token: token, expires_in: expires_in}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp req,
    do:
      Req.new(
        [base_url: "https://graph.threads.net"] ++
          Application.get_env(:high_society, __MODULE__, [])
      )

  defp app_id, do: Application.fetch_env!(:high_society, :threads_app_id)
  defp app_secret, do: Application.fetch_env!(:high_society, :threads_app_secret)
end
