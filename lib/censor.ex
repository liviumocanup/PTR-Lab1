defmodule Censor do
  use GenServer

  def start_link(id) do
    IO.puts "Starting Censor #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(args) do
    {:ok, args}
  end

  def censor(pid, msg) do
    GenServer.call(pid, msg)
  end

  def handle_call({_, msg}, _from, state) do
    bad_words = [
      "arse", "arsehole", "ass", "asshole",
      "bastard", "bitch", "bollocks", "booty", "bugger", "bullshit",
      "cock", "crap", "cunt", "cum",
      "dick", "dickhead",
      "fuck",
      "minge", "minger",
      "nigga", "nigger",
      "piss", "prick", "punani", "pussy",
      "hoe",
      "shit", "slut", "sod-off",
      "tits", "twat",
      "wanker", "whore"
    ]
    censored = Enum.reduce(bad_words, msg, fn bad_word, censored_msg ->
      lc_bad_word = String.downcase(bad_word)
      String.replace(censored_msg, ~r/(?i)#{lc_bad_word}/, String.duplicate("*", String.length(bad_word)))
    end)

    {:reply, censored, state}
  end
end
