defmodule Aggregator do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(_) do
    {:ok, %{}}
  end

  def store_tweet(text, id) do
    GenServer.cast(__MODULE__, {:tweet, text, id})
  end

  def store_sentiment(sentiment, id) do
    GenServer.cast(__MODULE__, {:sentiment, sentiment, id})
  end

  def store_engagement(engagement, id) do
    GenServer.cast(__MODULE__, {:engagement, engagement, id})
  end

  def handle_cast({:tweet, text, id}, state) do
    new_state = Map.update(state, id, %{tweet: text}, &Map.put(&1, :tweet, text))
    new_state = maybe_complete_aggregated_info(id, new_state)
    {:noreply, new_state}
  end

  def handle_cast({:sentiment, sentiment, id}, state) do
    new_state = Map.update(state, id, %{sentiment: sentiment}, &Map.put(&1, :sentiment, sentiment))
    new_state = maybe_complete_aggregated_info(id, new_state)
    {:noreply, new_state}
  end

  def handle_cast({:engagement, engagement, id}, state) do
    new_state = Map.update(state, id, %{engagement: engagement}, &Map.put(&1, :engagement, engagement))
    new_state = maybe_complete_aggregated_info(id, new_state)
    {:noreply, new_state}
  end

  def handle_call(batch, _from, state) do
    completed_tweets = state
      |> Map.to_list()
      |> Enum.filter(fn {_id, tweet} -> tweet[:completed] == true end)

    {selected_tweets, _remaining_completed} = Enum.split(completed_tweets, batch)

    new_state = Enum.reduce(selected_tweets, state, fn {id, _}, acc ->
      Map.delete(acc, id)
    end)

    tweets = Enum.map(selected_tweets, fn {_id, tweet} -> %{tweet: tweet.tweet, sentiment: tweet.sentiment, engagement: tweet.engagement} end)

    {:reply, tweets, new_state}
  end

  defp maybe_complete_aggregated_info(id, state) do
    case state[id] do
      %{tweet: tweet, sentiment: sentiment, engagement: engagement} ->
        Map.update(state, id, %{completed: true}, &Map.put(&1, :completed, true))
      _ ->
        state
    end
  end

  def send_batch(value) do
    GenServer.call(GenServer.whereis(__MODULE__), value)
  end
end
