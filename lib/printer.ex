defmodule Print do
  use GenServer

  @min_sleep_time 1000
  @max_sleep_time 3000

  def start_link(id) do
    IO.puts "Starting printer #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(_) do
    # {:ok, censor_pid} = Censor.start_link()
    # {:ok, engagement_pid} = Engagement.start_link()
    # {:ok, sentiment_pid} = Sentiment.start_link()
    state = {}
    {:ok, state}
  end

  def handle_call({id, :kill}, state) do
    IO.puts("=====> Killing Printer #{id} ##")

    {:stop, :normal, state}
  end

  def handle_cast({id, msg}, state) do
    # {censor_pid, engagement_pid, sentiment_pid} = state
    {text, stats} = msg
    {_, _, _, username} = stats

    slept = sleep()

    sentiment_score = LoadBalancer.process(:SentimentLB, text)
    engagement_score = LoadBalancer.process(:EngagementLB, stats)
    censored_msg = LoadBalancer.process(:CensorLB, text)

    EngagementTracker.store(username, engagement_score)

    IO.puts "\nPrinter #{id} #{slept} -> \n\t- Sentiment: #{sentiment_score}\n\t- Engagement: #{engagement_score}\n\t #{inspect censored_msg}\n\t- Eng for User: #{username} = #{EngagementTracker.get_ratio(username)}"
    {:noreply, state}
  end

  def handle_call({id, msg}, _from, state) do
    # {censor_pid, engagement_pid, sentiment_pid} = state
    {text, stats} = msg

    slept = sleep()

    censored_msg = LoadBalancer.process(:CensorLB, text)
    sentiment_score = LoadBalancer.process(:SentimentLB, text)
    engagement_score = LoadBalancer.process(:EngagementLB, stats)

    IO.puts "\nPrinter #{id} #{slept} -> \n\t- Sentiment: #{sentiment_score}\n\t- Engagement: #{engagement_score}\n\t #{inspect censored_msg}"
    # IO.puts("#####OK#####:#{inspect msg}")
    # IO.puts("#####NOYOK#####:#{inspect censored_msg}")
    {:reply, :ok, state}
  end

  # def handle_info({id, msg, caller, ref}, state) do
  #   slept = sleep()
  #   censored_msg = censor(msg)
  #   IO.puts "\nPrinter #{id} #{slept} -> #{inspect censored_msg}"
  #   new_state = Map.update!(state, :message_count, fn count -> count + 1 end)

  #   send(caller, {ref, :result, censored_msg})

  #   {:noreply, new_state}
  # end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
    "slept for #{sleep_time} ms"
  end

end
