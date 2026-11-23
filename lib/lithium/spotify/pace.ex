defmodule Lithium.Spotify.Pace do
  @moduledoc false

  # Spotify counts requests in a rolling 30 second window. One request a
  # second stays inside a small development-mode budget.
  @default_ms 1_000
  @key :lithium_spotify_pace_at

  def wait do
    interval = Application.get_env(:lithium, :spotify_pace_ms, @default_ms)

    if is_integer(interval) and interval > 0 do
      now = System.monotonic_time(:millisecond)

      case Process.get(@key) do
        last when is_integer(last) ->
          delay = interval - (now - last)
          if delay > 0, do: Process.sleep(delay)

        _ ->
          :ok
      end

      Process.put(@key, System.monotonic_time(:millisecond))
    end

    :ok
  end
end
