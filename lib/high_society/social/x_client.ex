defmodule HighSociety.Social.XClient do
  @moduledoc """
  Thin client for posting to X (`@High_Societycc`) via API v2's
  `POST /2/tweets` (https://docs.x.com/x-api/posts/creation-of-a-post),
  authenticated as that fixed account with a static OAuth 1.0a user-context
  token (no browser redirect/refresh flow needed - see `X_API_KEY` and
  friends in `config/runtime.exs`).
  """

  @endpoint "https://api.twitter.com/2/tweets"

  @doc """
  Posts `text` as a tweet from `@High_Societycc`. Returns `{:ok, x_post_id}`
  or `{:error, reason}` - never raises, since a failed post here is a
  degraded-but-recoverable state on the `XPost` record, not a crash.
  """
  def post_tweet(text) when is_binary(text) do
    case Req.post(req(),
           url: @endpoint,
           headers: [{"authorization", oauth_header(text)}],
           json: %{text: text}
         ) do
      {:ok, %Req.Response{status: 201, body: %{"data" => %{"id" => id}}}} ->
        {:ok, id}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp req do
    Req.new(Application.get_env(:high_society, __MODULE__, []))
  end

  # OAuth 1.0a signs the request line + "protocol parameters" only (the
  # oauth_* params here - there's no query string), never the JSON body -
  # see https://developer.x.com/en/docs/authentication/oauth-1-0a/creating-a-signature.
  defp oauth_header(_text) do
    oauth_params = %{
      "oauth_consumer_key" => api_key(),
      "oauth_nonce" => nonce(),
      "oauth_signature_method" => "HMAC-SHA1",
      "oauth_timestamp" => Integer.to_string(System.system_time(:second)),
      "oauth_token" => access_token(),
      "oauth_version" => "1.0"
    }

    signature = sign("POST", @endpoint, oauth_params)

    params =
      Map.put(oauth_params, "oauth_signature", signature)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {k, v} -> ~s(#{percent_encode(k)}="#{percent_encode(v)}") end)

    "OAuth " <> params
  end

  defp sign(method, url, oauth_params) do
    param_string =
      oauth_params
      |> Enum.sort()
      |> Enum.map_join("&", fn {k, v} -> "#{percent_encode(k)}=#{percent_encode(v)}" end)

    base_string =
      [method, percent_encode(url), percent_encode(param_string)]
      |> Enum.join("&")

    signing_key = "#{percent_encode(api_key_secret())}&#{percent_encode(access_token_secret())}"

    :crypto.mac(:hmac, :sha, signing_key, base_string)
    |> Base.encode64()
  end

  defp percent_encode(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp nonce, do: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp api_key, do: Application.fetch_env!(:high_society, :x_api_key)
  defp api_key_secret, do: Application.fetch_env!(:high_society, :x_api_key_secret)
  defp access_token, do: Application.fetch_env!(:high_society, :x_access_token)
  defp access_token_secret, do: Application.fetch_env!(:high_society, :x_access_token_secret)
end
