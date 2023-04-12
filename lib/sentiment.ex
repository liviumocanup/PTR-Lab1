defmodule Sentiment do
  use GenServer

  def start_link(id) do
    IO.puts "Starting Sentiment #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(_state) do

    text = HTTPoison.get!("http://localhost:4000/emotion_values")
    |> Map.get(:body)

    state = parse(text)
    {:ok, state}
  end

  def handle_info({pid, msg}, state) do
    calculate_sentiment(pid, msg)

    {:noreply, state}
  end

  def calculate_sentiment(pid, msg) do
    GenServer.call(pid, msg)
  end

  def handle_cast({text, id}, state) do
    words = String.downcase(text) |> String.trim() |> String.split(~r/\s+/)

    mean_score = Enum.reduce(words, 0, fn word, acc ->
      case Map.get(state, word) do
        nil -> acc
        score -> acc + score
      end
    end) / Enum.count(words)

    Aggregator.store_sentiment(mean_score, id)
    {:noreply, state}
  end

  def handle_call({_, msg}, _from, state) do
    words = String.downcase(msg) |> String.trim() |> String.split(~r/\s+/)
    mean_score = Enum.reduce(words, 0, fn word, acc ->
      case Map.get(state, word) do
        nil -> acc
        score -> acc + score
      end
    end) / Enum.count(words)

    {:reply, mean_score, state}
  end

  defp parse(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      words = String.split(line, ~r/\s+/, trim: true)
      value = String.to_integer(List.last(words))
      key = Enum.join(List.delete_at(words, -1), " ")
      Map.put(acc, key, value)
    end)
  end
end
