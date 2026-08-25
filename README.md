![Build Status](https://github.com/EssenceOfChaos/high_society/actions/workflows/elixir.yml/badge.svg)

# HighSociety

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://phoenix.hexdocs.pm/overview.html
- Docs: https://phoenix.hexdocs.pm
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix

## Manual Setup

To start your Phoenix server you will need _Erlang_, _Elixir_, and _Postgres_.

Install Erlang with Homebrew: `brew install erlang`
Install Elixir `brew install elixir`

Install Hex package manager: `mix local.hex`
Install Phoenix `mix archive.install hex phx_new`
Install Postgres `brew install postgresql`

Install dependencies with `mix deps.get`

Create and migrate your database with `mix ecto.setup`

Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
