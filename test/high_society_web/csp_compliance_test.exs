defmodule HighSocietyWeb.CspComplianceTest do
  @moduledoc """
  Guards against silently re-breaking the Content-Security-Policy set in
  `HighSocietyWeb.Router` (`default-src 'self'; script-src 'self'
  'nonce-...'; style-src 'self'; img-src 'self' data:;`). It has no
  'unsafe-inline', so an inline `style=""` attribute or an un-nonced inline
  `<script>` doesn't raise anywhere in dev or in the test suite - it just
  renders invisibly broken in production (the browser drops it and logs a
  console warning nobody watches). This is a static source scan rather than
  a browser-level check, so it's fast and needs no headless browser, at the
  cost of only catching these two known-fragile patterns rather than every
  possible CSP violation.
  """

  use ExUnit.Case, async: true

  @web_files Path.wildcard(Path.join(File.cwd!(), "lib/high_society_web/**/*.{ex,heex}"))

  test "no template sets an inline style=\"\" attribute" do
    offenders = grep(@web_files, ~r/\sstyle=[{"]/)

    assert offenders == [],
           """
           Found inline style="" attribute(s). The CSP's `style-src 'self'` has no \
           'unsafe-inline' and no nonce support for style *attributes* (only for <style> \
           elements), so these silently stop applying in production.

           Move the dynamic value to a data-* attribute and apply it via a phx-hook that \
           sets `el.style` in JS instead - CSP does not govern CSSOM mutations. See the \
           `.InlineStyle` hook in war.ex / poker_table.ex for the pattern.

           #{Enum.join(offenders, "\n")}
           """
  end

  test "every inline <script> tag is external, a colocated hook, or nonce'd" do
    offenders =
      grep(@web_files, ~r/<script/,
        unless_also_matches: ~r/src=|ColocatedHook|nonce=/
      )

    assert offenders == [],
           """
           Found a raw inline <script> tag with no `src=`, no \
           `:type={Phoenix.LiveView.ColocatedHook}`, and no `nonce=` attribute. The CSP's \
           `script-src 'self' 'nonce-...'` has no 'unsafe-inline', so this script silently \
           fails to run in production.

           #{Enum.join(offenders, "\n")}
           """
  end

  defp grep(files, pattern, opts \\ []) do
    exclude = Keyword.get(opts, :unless_also_matches)

    for file <- files,
        {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        Regex.match?(pattern, line),
        is_nil(exclude) or not Regex.match?(exclude, line) do
      "#{Path.relative_to_cwd(file)}:#{number}"
    end
  end
end
