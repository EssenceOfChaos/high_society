defmodule HighSociety.Tournaments.Zippopotamus do
  @moduledoc """
  Thin client for the Zippopotam.us postal code API
  (https://zippopotam.us, https://github.com/zippopotamus/zippopotamus) -
  looks up a postal code's city and state/province so the tournament
  registration form (`HighSocietyWeb.TournamentLive`) can autofill them
  once a player tabs off the ZIP field. Only ever called for the three
  countries the form has a State dropdown for (see
  `HighSociety.Tournaments.Regions`) - no attempt to support arbitrary
  countries. Unauthenticated and free, with no API key to configure.

  Best-effort only: any failure (bad postal code, network error, timeout,
  unexpected response shape) just means the player fills the fields in by
  hand, same as before this existed - callers should never surface an
  error from this to the player.
  """

  alias HighSociety.Tournaments.Regions

  @doc """
  Looks up `postal_code` for `country_code` ("US", "CA", or "MX").
  Returns `{:ok, %{city: city_or_nil, state: state_code_or_nil}}` - either
  may be `nil` if the API didn't return it, or (for `state`) returned a
  value that doesn't match one of `Regions`' known codes for that country
  - or `:error` for anything else.
  """
  @spec lookup(String.t(), String.t()) ::
          {:ok, %{city: String.t() | nil, state: String.t() | nil}} | :error
  def lookup(country_code, postal_code) when country_code in ~w(US CA MX) do
    case Req.get(req(),
           url: "/:country/:postal_code",
           path_params: [country: String.downcase(country_code), postal_code: postal_code]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"places" => [place | _]}}} ->
        {:ok,
         %{
           city: place["place name"],
           state: known_state(country_code, place["state abbreviation"])
         }}

      _ ->
        :error
    end
  end

  def lookup(_country_code, _postal_code), do: :error

  defp known_state(country_code, state_code) do
    if Enum.any?(Regions.state_options_for(country_code), fn {code, _label} ->
         code == state_code
       end) do
      state_code
    else
      nil
    end
  end

  defp req do
    Req.new(
      [base_url: "https://api.zippopotam.us", receive_timeout: 2_000, retry: false] ++
        Application.get_env(:high_society, __MODULE__, [])
    )
  end
end
