defmodule Engagement do

  def start_link(id) do
    IO.puts "Starting Engagement #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(_state) do
    {:ok, %{user_ratios: %{}}}
  end

  def calculate_engagement(pid, info) do
    GenServer.call(pid, {pid, info})
  end

  def handle_call({:average_engagement_ratio, name}, _from, state) do
    user_ratios = Map.get(state, :user_ratios)
    ratios = Map.get(user_ratios, name, [])

    average_ratio =
      if length(ratios) > 0 do
        Enum.sum(ratios) / length(ratios)
      else
        0
      end

    {:reply, average_ratio, state}
  end

  def handle_call({_, info}, _from, state) do
    {favorites, retweets, followers, name} = info

    user_ratios = Map.get(state, :user_ratios)

    engagement_ratio =
      if followers != 0 do
        (favorites + retweets) / followers
      else
        0
      end

    updated_user_ratios = update_user_ratios(user_ratios, name, engagement_ratio)

    {:reply, engagement_ratio, %{state | user_ratios: updated_user_ratios}}
  end

  defp update_user_ratios(user_ratios, name, engagement_ratio) do
    current_ratios = Map.get(user_ratios, name, [])
    updated_ratios = [engagement_ratio | current_ratios]
    Map.put(user_ratios, name, updated_ratios)
  end

  def average_engagement_ratio(pid, name) do
    GenServer.call(pid, {:average_engagement_ratio, name})
  end

end
