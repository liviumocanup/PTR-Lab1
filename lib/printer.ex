defmodule Print do
  use GenServer

  @min_sleep_time 2000
  @max_sleep_time 5000

  def start_link(id) do
    IO.puts "Starting printer #{id}..."
    GenServer.start_link(__MODULE__, [id, %{message_count: 0}])
  end

  def init([_, state]) do
    {:ok, state}
  end

  def handle_call(:message_count, _from, state) do
    {:reply, state.message_count, state}
  end

  def handle_info({id, :kill}, state) do
    IO.puts("=====> Killing Printer #{id} ##")

    {:stop, :normal, state}
  end

  def handle_info({id, msg}, state) do
    slept = sleep()
    censored_msg = censor(msg)
    IO.puts "\nPrinter #{id} #{slept} -> #{inspect censored_msg}"
    new_state = Map.update!(state, :message_count, fn count -> count + 1 end)
    {:noreply, new_state}
  end

  def handle_info({id, msg, caller, ref}, state) do
    slept = sleep()
    censored_msg = censor(msg)
    IO.puts "\nPrinter #{id} #{slept} -> #{inspect censored_msg}"
    new_state = Map.update!(state, :message_count, fn count -> count + 1 end)

    send(caller, {ref, :result, censored_msg})

    {:noreply, new_state}
  end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
    "slept for #{sleep_time} ms"
  end

  defp censor(msg) do
    bad_words = [
      "arse", "arsehole", "ass", "asshole",
      "bastard", "bitch", "bollocks", "booty", "bugger", "bullshit",
      "cock", "crap", "cunt", "cum",
      "dick", "dickhead",
      "fuck",
      "minge", "minger",
      "nigga", "nigger",
      "piss", "prick", "punani", "pussy",
      "shit", "slut", "sod-off",
      "tits", "twat",
      "wanker", "whore"
    ]
    Enum.reduce(bad_words, msg, fn bad_word, censored_msg ->
      lc_bad_word = String.downcase(bad_word)
      String.replace(censored_msg, ~r/(?i)#{lc_bad_word}/, String.duplicate("*", String.length(bad_word)))
    end)
  end
end
