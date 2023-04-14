defmodule Batcher do
  use GenServer

  @batch 5
  @timeout 5000

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(state) do
    schedule_timeout()
    send(self(), {:process_batch, []})
    {:ok, state}
  end

  def handle_info({:process_batch, acc}, state) do
    tweets = Aggregator.send_batch(@batch)
    acc = acc ++ tweets
    if length(acc) < @batch do
      send(self(), {:process_batch, acc})
    else
      if length(acc) == @batch do
        store(acc)
        schedule_timeout()
        send(self(), {:process_batch, []})
      end
    end

    {:noreply, %{acc: acc}}
  end

  def handle_info(:timeout, state) do
    acc = state.acc

    if length(acc) > 0 do
      store(acc)
      schedule_timeout()
      send(self(), {:process_batch, []})
    else
      schedule_timeout()
    end

    {:noreply, %{acc: []}}
  end

  defp schedule_timeout() do
    Process.send_after(self(), :timeout, @timeout)
  end

  def print(acc) do
    IO.puts("============Batch of #{length(acc)} tweets is ready.=================")

    Enum.each(acc, fn %{tweet: text, sentiment: sentiment, engagement: engagement, username: username} ->
      IO.puts("-> Tweet: #{text}\n\rSentiment: #{sentiment}\n\rEngagement for user: #{username} is #{engagement}")
    end)
  end

  def store(acc) do
    Enum.each(acc, &DatabaseProxy.add_item/1)
    # IO.puts("#{inspect DatabaseProxy.get_tweets()}")
  end
end
