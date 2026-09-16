defmodule HighSociety.Accounts.ProfanityFilterTest do
  use ExUnit.Case, async: true

  alias HighSociety.Accounts.ProfanityFilter

  describe "blocked?/1" do
    test "flags a blocked word on its own" do
      assert ProfanityFilter.blocked?("shit")
    end

    test "flags a blocked word as one token among several" do
      assert ProfanityFilter.blocked?("big ass fan")
    end

    test "is case-insensitive" do
      assert ProfanityFilter.blocked?("ShIt")
    end

    test "does not flag an innocent word containing a blocked word as a substring" do
      refute ProfanityFilter.blocked?("assassin")
      refute ProfanityFilter.blocked?("classy")
    end

    test "does not flag clean text" do
      refute ProfanityFilter.blocked?("Freddy the Great")
    end
  end
end
