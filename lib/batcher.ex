defmodule Batcher do
  use GenServer

  @batch 5
  @timeout 5000

  def start_link do
    pid = GenServer.start_link(__MODULE__, [])
    |> elem(1)
    Process.register(pid, __MODULE__)
    IO.puts("Batcher pid #{inspect pid}")
  end

  def init(state) do
    pid = self()
    IO.puts("Batcher trying #{inspect pid}")
    send(self(), {:process_batch, []})
    {:ok, state}
  end

  def handle_info({:process_batch, acc}, state) do
    tweets = Aggregator.send_batch(@batch)
    acc = acc ++ tweets
    if length(acc) < @batch do
      # IO.puts()
      send(self(), {:process_batch, acc})
    else
      if length(acc) == @batch do
        IO.puts("============Batch of #{length(acc)} tweets is ready.=================")

        Enum.each(acc, fn %{tweet: text, sentiment: sentiment, engagement: engagement} ->
          IO.puts("-> Tweet: #{text}\n\rSentiment: #{sentiment}\n\rEngagement per user: #{engagement}")
        end)

        send(self(), {:process_batch, []})
      end
    end
    # if length of tweets is smaller than @batch, add all the tweets in state
    # if length of tweets is @batch delete

    {:noreply, state}
  end

  # def handle_info(:print_and_reset, state) do
  #   new_state = print_and_reset(state)
  #   send(self(), :process_batch)
  #   {:noreply, new_state}
  # end

  # defp request_and_append_tweets(state, tweets_needed) when tweets_needed > 0 do
  #   aggregated_tweets = Aggregator.send_batch(tweets_needed)
  #   received_number = length(aggregated_tweets)
  #   new_state = Map.put(state, :tweets, state.tweets ++ aggregated_tweets)

  #   new_state = if received_number < tweets_needed do
  #     request_and_append_tweets(new_state, tweets_needed - received_number)
  #   else
  #     new_state
  #   end
  #   new_state
  # end

  # defp request_and_append_tweets(state, _), do: print_and_reset(state)

  # defp print_and_reset(state) do
  #   if length(state.tweets) > 0 do
  #     IO.puts("============Batch of #{length(state.tweets)} tweets is ready.=================")

  #     IO.puts("Batcher #{inspect state}")

  #     # Enum.each(state.tweets, fn %{tweet: text, sentiment: sentiment, engagement: engagement} ->
  #     #   IO.puts("-> Tweet: #{text}\n\rSentiment: #{sentiment}\n\rEngagement per user: #{engagement}")
  #     # end)

  #     state = Map.update!(state, :tweets, &(&1 -- state.tweets))
  #     IO.puts("AFTER #{inspect state}")
  #     state
  #   else
  #     state
  #   end
  # end
end
