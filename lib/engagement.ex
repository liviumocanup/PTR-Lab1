defmodule Engagement do

  def start_link(id) do
    IO.puts "Starting Engagement #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(args) do
    {:ok, args}
  end

  def calculate_engagement(pid, info) do
    GenServer.call(pid, {pid, info})
  end

  def handle_call({_, info}, _from, state) do
    {favorites, retweets, followers, name} = info

    engagement_ratio = compute_engagement(favorites, retweets, followers)

    EngagementTracker.store(name, engagement_ratio)

    {:reply, engagement_ratio, state}
  end

  def handle_cast({stats, id}, state) do
    {favorites, retweets, followers, name} = stats

    engagement_ratio = compute_engagement(favorites, retweets, followers)

    EngagementTracker.store(name, engagement_ratio)

    Aggregator.store_engagement(EngagementTracker.get_ratio(name), name, id)

    {:noreply, state}
  end

  defp compute_engagement(favorites, retweets, followers) do
    engagement_ratio =
      if followers != 0 do
        (favorites + retweets) / followers
      else
        0
      end

    engagement_ratio
  end

end
