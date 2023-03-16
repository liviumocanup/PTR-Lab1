defmodule Analyzer do
  use GenServer

  @time 10

  def start_link do
    IO.puts "Starting analyzer..."
    GenServer.start_link(__MODULE__, {:os.timestamp(), %{}}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def analyze_hashtag(hashtag) do
    GenServer.cast(__MODULE__, hashtag)
  end

  def handle_cast(hashtag, state) do
    hashtags = state |> elem(1)
    hashtags = Map.update(hashtags, hashtag, 1, fn count -> count + 1 end)

    start_time = state |> elem(0)
    end_time = :os.timestamp()
    elapsed = elapsed_seconds(start_time, end_time)

    if elapsed > @time do
      hashtags = hashtags |> Enum.sort(fn {_, x}, {_, y} -> x >= y end) |> Enum.take(5)
      IO.puts "\n\n=====> Top 5 hashtags in the last #{@time} seconds:"
      hashtags |> Enum.each(fn {hashtag, count} -> IO.puts "#{hashtag}: #{count}" end)
      {:noreply, {:os.timestamp(), %{}}}
    else
      {:noreply,{start_time, hashtags}}
    end
  end

  defp elapsed_seconds(start_time, end_time) do
    {_, sec, micro} = end_time
    {_, sec2, micro2} = start_time

    (sec - sec2) + (micro - micro2) / 1_000_000
  end
end
