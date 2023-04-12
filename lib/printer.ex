defmodule Print do
  use GenServer

  @min_sleep_time 1000
  @max_sleep_time 3000

  def start_link(id) do
    IO.puts "Starting printer #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(_) do
    {:ok, {}}
  end

  def handle_call({id, :kill}, state) do
    IO.puts("=====> Killing Printer #{id} ##")

    {:stop, :normal, state}
  end

  def handle_cast({text, id}, state) do
    sleep()

    censored_text = LoadBalancer.process(:CensorLB, text)

    Aggregator.store_tweet(censored_text, id)

    # IO.puts "\nPrinter #{id} #{slept} -> \n\t- Sentiment: #{sentiment_score}\n\t- Engagement: #{engagement_score}\n\t #{inspect censored_msg}\n\t- Eng for User: #{username} = #{EngagementTracker.get_ratio(username)}"
    {:noreply, state}
  end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
    # "slept for #{sleep_time} ms"
  end

end
