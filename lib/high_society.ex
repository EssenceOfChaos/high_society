defmodule HighSociety do
  @moduledoc """
  HighSociety keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  require Logger
  @max_concurrency System.schedulers_online()
  def get_application do
    app = Application.get_application(__MODULE__)
    s = app |> to_string |> Macro.camelize()
    c = s |> String.to_atom()
    %{atom: app, string: s, camelized: c}
  end

  def get_compiled_modules do
    get_application()
    |> Map.get(:atom)
    |> :application.get_key(:modules)
    |> elem(1)
  end

  def get_loaded_modules do
    :code.all_loaded() |> Enum.map(&elem(&1, 0))
  end

  def get_own_modules do
    app = get_application()

    get_compiled_modules()
    |> Kernel.++(get_loaded_modules())
    |> Enum.uniq()
    |> List.delete(__MODULE__)
    |> Enum.filter(fn m ->
      Atom.to_string(m) |> String.contains?(app.string)
    end)
  end

  def get_max_concurrency do
    Logger.info("Number of cores determines max concurrency: [#{@max_concurrency} cores online]")
  end
end
