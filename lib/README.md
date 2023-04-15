# FAF.PTR16.1 -- Project 1
> **Performed by:** Mocanu Liviu, group FAF-203
> **Verified by:** asist. univ. Alexandru Osadcenco

## P1W1

**Task 1** -- Write an actor that would read SSE streams.

```elixir
defmodule Read do
  use GenServer

  def start_link(url) do
    GenServer.start_link(__MODULE__, url)
  end

  def init(url) do
    IO.puts "Connecting to stream..."
    HTTPoison.get!(url, [], [recv_timeout: :infinity, stream_to: self()])
    {:ok, nil}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, _state) do
    process_event(chunk)
    {:noreply, nil}
  end

  defp process_event("event: \"message\"\n\ndata: " <> message) do
    {success, data} = Jason.decode(String.trim(message))

    if success == :ok do
      send_to_worker_pool(data["message"]["tweet"])
    end
  end

  defp process_event(_corrupted_event) do
    IO.puts("## Corrupted event discarded ##")
    LoadBalancer.process(:PrintLB, ":kill")
  end

  defp send_to_worker_pool(tweet) do
    text = tweet["text"]
    favorites = tweet["favorite_count"]
    retweets = tweet["retweet_count"]
    followers = tweet["user"]["followers_count"]
    name = tweet["user"]["name"]
    hashtags = Enum.map(tweet["entities"]["hashtags"], fn h -> h["text"] end)

    info = {text, {favorites, retweets, followers, name}}

    # Dispatcher.dispatch(info)
    send(printer_pid, text)

    if Map.get(tweet, "retweeted_status", nil) != nil do
      send_to_worker_pool(tweet["retweeted_status"])
    end
  end

  def handle_info(%HTTPoison.AsyncStatus{} = status, _state) do
    # IO.puts "Connection status: #{inspect status}"
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncHeaders{} = headers, _state) do
    # IO.puts "Connection headers: #{inspect headers}"
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncEnd{} = connection_end, _state) do
    IO.puts "Connection end: #{inspect connection_end}"
    {:noreply, nil}
  end
end
```

The module Reader that is responsible for the get request as well as proccessing the chunk, or discarding corrupted events. It extracts the `data["message"]["tweet"]` which is exactly the tweet that contains all information we need about it.

Send the get request to the docker that is started using:

```bash
$ docker run -p 4000:4000 alexburlacu/rtp-server:faf18x
```

**Task 2** -- Create an actor that would print on the screen the tweets it receives from the SSE Reader.

```elixir
defmodule Print do
  use GenServer

  @min_sleep_time 5
  @max_sleep_time 50

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
    # sleep()

    # censored_text = LoadBalancer.process(:CensorLB, text)

    # Aggregator.store_tweet(censored_text, id)
    IO.puts("-> Tweet: #{inspect censored_text}")

    {:noreply, state}
  end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
  end

end
```
The Print module receives the text of the tweet and prints it to IO.

**Task 3** -- Create a second Reader actor that will consume the second stream provided.

```elixir
defmodule ReadSupervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
    |> elem(1)
  end

  def init([]) do
    children = [
      %{
        id: :reader1,
        start: {Read, :start_link, ["http://localhost:4000/tweets/1"]}
      },
      %{
        id: :reader2,
        start: {Read, :start_link, ["http://localhost:4000/tweets/2"]}
      },
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```
Most easily achieved by creating a supervisor and passing two different endpoints as url for each Reader.

**Task 4** -- Simulate some load on the Printer by sleeping every
time a tweet is received.

```elixir
defmodule Print do
  use GenServer

  @min_sleep_time 5
  @max_sleep_time 50

  # ...

  def handle_cast({text, id}, state) do
    sleep()

    # censored_text = LoadBalancer.process(:CensorLB, text)

    # Aggregator.store_tweet(censored_text, id)
    IO.puts("-> Tweet: #{inspect censored_text}")

    {:noreply, state}
  end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
  end

end
```

As we could see from Task 2 `min_sleep_time` and `max_sleep_time` are parametrizable and function `sleep()` is responsible for the functionality of blocking the Print.

**Task 5** -- Create an actor that would print out every 5 seconds the most popular hashtag in the last 5 seconds.

```elixir 
defmodule Analyzer do
  use GenServer

  @time 5

  def start_link do
    IO.puts "Starting analyzer..."
    GenServer.start_link(__MODULE__, {:os.timestamp(), %{}})
  end

  def init(state) do
    {:ok, state}
  end

  def analyze_hashtag(pid, hashtag) do
    GenServer.cast(pid, hashtag)
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
```

The Analyzer is being sent all the hashtags from the Reader and it's just a matter of computing the number of occurences found of them by storing them all in a map. After `@time` passes, the map is emptied.

## P1W2

**Task 1** -- Create a Worker Pool to substitute the Printer actor from previous week.

```elixir
defmodule GenericSupervisor do
  use Supervisor

  def start_link(worker_module, num_workers) do
    supervisor_name = generate_supervisor_name(worker_module)
    IO.puts "Starting #{supervisor_name}..."
    Supervisor.start_link(__MODULE__, %{worker_module: worker_module, num_workers: num_workers, name: String.to_atom(supervisor_name)}, name: String.to_atom(supervisor_name))
  end

  def init(state) do
    children =
      Enum.map(1..state.num_workers, fn id ->
        %{
          id: id,
          start: {state.worker_module, :start_link, [id]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end


  def get_message_count(pid) do
    GenServer.call(pid, :message_count)
  end

  def count(sup_pid) do
    Supervisor.count_children(sup_pid)
    |> Map.fetch!(:active)
  end

  def get_worker_pid(sup_pid, id) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {i, _, _, _} -> i == id end)
    |> elem(1)
  end

  def get_worker_id(sup_pid, pid) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {_, i, _, _} -> i == pid end)
    |> elem(0)
  end

  def get_all_pids(sup_pid) do
    Enum.map(1..count(sup_pid), fn i -> get_worker_pid(sup_pid, i) end)
  end

  def generate_supervisor_name(worker_module) do
    module_name = inspect(worker_module)
    String.replace_suffix(module_name, "", "Supervisor")
  end
end
```

The following is a Generic Supervisor that starts by sending it the amount of children it's supposed to have and the worker module it needs to supervise. It will generate it's name as `worker_module`'s name that was passed + `"Supervisor"` for example:

```elixir
GenericSupervisor.start_link(Print, 3)
```

will start a supervisor called `PrintSupervisor` and have 3 Print workers.

**Task 2** -- Create an actor that would mediate the tasks being sent to the Worker Pool.

```elixir
defmodule LoadBalancer do
  use GenServer

  @load_threshold 10
  @idle_threshold 1
  @check_idle_interval 5000

  def start_link(supervisor_name, wpm_pid) do
    lb_name = generate_name(supervisor_name)
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting LoadBalancer for #{inspect supervisor_name}..."
    pid = GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, sup_pid: GenServer.whereis(supervisor_name), wpm_pid: wpm_pid, lb_name: lb_name})
    |> elem(1)
    Process.register(pid, lb_name)
  end

  def init(state) do
    if state.wpm_pid != nil do
      schedule_check_idle()
    end

    {:ok, state}
  end

  def handle_cast({info, id}, state) do
    worker_pid = least_connected_worker(state)
    GenServer.cast(worker_pid, {info, id})
    {:noreply, state}
  end

  def handle_call(info, _from, state) do
    worker_pid = least_connected_worker(state)
    # IO.puts "Least connected worker: #{inspect find_id(worker_pid, state)} with #{inspect Process.info(worker_pid)[:message_queue_len]} messages"
    response = GenServer.call(worker_pid, {find_id(worker_pid, state), info})
    {:reply, response, state}
  end

  def handle_info(:check_idle, state) do
    worker_pid = least_connected_worker(state)
    check_idle(worker_pid, state)
    schedule_check_idle()
    {:noreply, state}
  end

  def process(lb_name, info) do
    GenServer.call(GenServer.whereis(lb_name), info)
  end

  def cast(lb_name, {info, id}) do
    GenServer.cast(GenServer.whereis(lb_name), {info, id})
  end

  def schedule_check_idle do
    Process.send_after(self(), :check_idle, @check_idle_interval)
  end

  defp check_idle(pid, state) do
    if Process.info(pid)[:message_queue_len] > @load_threshold do
      IO.puts "\n\n====>>>#{state.lb_name}: Workers are overloaded."
      WorkerPoolManager.increase_workers(state.wpm_pid, 1)
    else
      if Process.info(pid)[:message_queue_len] < @idle_threshold and Process.info(pid)[:message_queue_len] > 1 do
        IO.puts "\n\n====>>>#{state.lb_name}: Workers are idle."
        WorkerPoolManager.decrease_workers(state.wpm_pid, 1)
      end
    end
  end

  defp least_connected_worker(state) do
    worker_pids = get_all_pids(state)
    counts = all_workers_queue_len(worker_pids)
    Enum.min_by(counts, fn {_, count} -> count end)
    |> elem(0)
  end

  defp all_workers_queue_len(worker_pids) do
    Enum.map(worker_pids, fn pid ->
      {pid, Process.info(pid)[:message_queue_len]}
    end)
  end

  defp find_id(worker_pid, state) do
    GenericSupervisor.get_worker_id(state.sup_pid, worker_pid)
  end

  defp get_all_pids(state) do
    GenericSupervisor.get_all_pids(state.sup_pid)
  end

  defp generate_name(supervisor_name) do
    String.to_atom(String.replace(supervisor_name, "Supervisor", "LB"))
  end
end

```
Similar to GenericSupervisor, LoadBalancer is generic as well. In a similar manner it generates it's name depending on the supervisor it balances, that is, it gets the name of the supervisor and replaces the `"Supervisor"` part with `"LB"` short for Load Balancer.

The Load Balancer finds the most fitting worker by requesting all the Workers' pids and at this stage we can just say it sends the information received to the Worker with that pid using a cast.

**Task 3** -- Occasionally, the SSE events will contain a “kill
message”. Change the actor to crash when such a message is received.

```elixir
defmodule Print do
  #...

  def handle_cast({id, :kill}, state) do
    IO.puts("=====> Killing Printer #{id} ##")
    {:stop, :normal, state}
  end

  #...
end
```

This is more of a matching nuance, since this is the same info being sent by the Reader, it just turns out that instead of a string, we get an atom `:kill`.

```elixir
defmodule Reader do
  #...

  defp process_event(_corrupted_event) do
    IO.puts("## Corrupted event discarded ##")
    Task.start(fn -> LoadBalancer.cast(:PrintLB, {":kill", 0}) end)
  end

  #...
end
```

**Task 4** -- Modify the LoadBalancer to implement the “Least connected” algorithm for load balancing.

```elixir
defmodule LoadBalancer do
  #...

  defp least_connected_worker(state) do
    worker_pids = get_all_pids(state)
    counts = all_workers_queue_len(worker_pids)
    Enum.min_by(counts, fn {_, count} -> count end)
    |> elem(0)
  end

  defp all_workers_queue_len(worker_pids) do
    Enum.map(worker_pids, fn pid ->
      {pid, Process.info(pid)[:message_queue_len]}
    end)
  end

  #...
end
```
In this way we check which Worker is the most fitting by finding the one with the least messages in the queue.

## P1W3

**Task 1** -- Any bad words that a tweet might contain mustn’t be printed. Instead, a set of stars should appear, the number of which corresponds to the bad word’s length.

```elixir
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
    bad_words = ["
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
    "]
    censored = Enum.reduce(bad_words, msg, fn bad_word, censored_msg ->
      lc_bad_word = String.downcase(bad_word)
      String.replace(censored_msg, ~r/(?i)#{lc_bad_word}/, String.duplicate("*", String.length(bad_word)))
    end)

    {:reply, censored, state}
  end
end
```
In order to correctly identify the work I am iterating over a list of bad words, lowercasing them, and using a regular expression to replace all occurrences of the bad word in the message with asterisks.

**Task 2** -- Create an actor that would manage the number of Worker actors in the Worker Pool.

```elixir
defmodule WorkerPoolManager do
  use GenServer

  @max_num_workers 100
  @min_num_workers 1

  @spec_num_workers 3
  @spec_timeout 5000

  def start_link(supervisor_name, worker) do
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting WorkerPoolManager for...#{inspect supervisor_name}"
    GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, worker: worker, sup_pid: GenServer.whereis(supervisor_name)}, name: String.to_atom("WPM" <> inspect(worker)))
    |> elem(1)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:increase_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers + num

    new_num_workers = min(new_num_workers, @max_num_workers)

    if new_num_workers > current_num_workers do
      start_workers(new_num_workers - current_num_workers, state)
    end

    {:noreply, state}
  end

  def handle_cast({:decrease_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers - num

    new_num_workers = max(new_num_workers, @min_num_workers)

    if new_num_workers < current_num_workers do
      stop_workers(current_num_workers - new_num_workers, state)
    end

    {:noreply, state}
  end

  def increase_workers(pid, num) do
    GenServer.cast(pid, {:increase_workers, num})
  end

  def decrease_workers(pid, num) do
    GenServer.cast(pid, {:decrease_workers, num})
  end

  defp start_workers(num, state) do
    children_to_add = Enum.map(count_workers(state)+1..count_workers(state)+num, fn id ->
      %{
        id: id,
        start: {state.worker, :start_link, [id]}
      }
    end)

    Enum.each(children_to_add, fn child ->
      if Enum.any?(Supervisor.which_children(state.sup_pid), fn {id, _, _, _} -> id == child.id end) do
        Supervisor.restart_child(state.sup_pid, child.id)
      else
        Supervisor.start_child(state.sup_pid, child)
      end
    end)

    {:ok, state}
  end

  defp stop_workers(num, state) do
    Enum.map(count_workers(state)-num+1..count_workers(state), fn id ->
      IO.puts("Stopping worker #{id}")
      Supervisor.terminate_child(state.sup_pid, id)
    end)

    {:ok, state}
  end

  defp count_workers(state) do
    GenericSupervisor.count(state.sup_pid)
  end

  def execute_speculatively(message) do
    worker_pids = get_worker_pids(@spec_num_workers)

    tasks = Enum.map(worker_pids, fn worker_pid ->
      Task.async(fn ->
        ref = make_ref()
        send(worker_pid, {PrintSupervisor.get_worker_id(worker_pid), message, self(), ref})
        receive do
          {^ref, :result, result} -> result
        after
          @spec_timeout -> nil
        end
      end)
    end)

    await_first_task(tasks)
  end

  defp get_worker_pids(num_workers) do
    PrintSupervisor |> Supervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.take(num_workers)
  end

  defp await_first_task(tasks) do
    tasks
    |> Enum.map(fn task ->
      try do
        Task.await(task, @spec_timeout) # Add the timeout value here
      rescue
        Task.TimeoutError ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

end
```
The Worker Pool Manager is also generic, working based on the supervisor's name that is passed in.

It has a max and min number of workers in creates and gives the newly created workers the id of `Supervisor.count` + 1. In case it needs to decrease the number, it terminates the last worker `Supervisor.count`. In case it needs to start an already terminate worker, it `restarts` it.

In order to understand when to increase/decrease the number of workers, the `Worker Pool Manager` has to be paired with a LoadBalancer that would call the `increase/decrease` functions accordingly.

```elixir
defmodule LoadBalancer do
  #...

  def init(state) do
    if state.wpm_pid != nil do
      schedule_check_idle()
    end

    {:ok, state}
  end

  def handle_info(:check_idle, state) do
    worker_pid = least_connected_worker(state)
    check_idle(worker_pid, state)
    schedule_check_idle()
    {:noreply, state}
  end

  def schedule_check_idle do
    Process.send_after(self(), :check_idle, @check_idle_interval)
  end

  defp check_idle(pid, state) do
    if Process.info(pid)[:message_queue_len] > @load_threshold do
      IO.puts "\n\n====>>>#{state.lb_name}: Workers are overloaded."
      WorkerPoolManager.increase_workers(state.wpm_pid, 1)
    else
      if Process.info(pid)[:message_queue_len] < @idle_threshold and Process.info(pid)[:message_queue_len] > 1 do
        IO.puts "\n\n====>>>#{state.lb_name}: Workers are idle."
        WorkerPoolManager.decrease_workers(state.wpm_pid, 1)
      end
    end
  end

  #...
end
```

**Task 3** -- Enhance your Worker Pool to also implement speculative execution of tasks

```elixir
defmodule WorkerPoolManager do
  #...
  
  @spec_num_workers 3
  @spec_timeout 5000

  def execute_speculatively(message) do
    worker_pids = get_worker_pids(@spec_num_workers)

    tasks = Enum.map(worker_pids, fn worker_pid ->
      Task.async(fn ->
        ref = make_ref()
        send(worker_pid, {PrintSupervisor.get_worker_id(worker_pid), message, self(), ref})
        receive do
          {^ref, :result, result} -> result
        after
          @spec_timeout -> nil
        end
      end)
    end)

    await_first_task(tasks)
  end

  defp get_worker_pids(num_workers) do
    PrintSupervisor |> Supervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.take(num_workers)
  end

  defp await_first_task(tasks) do
    tasks
    |> Enum.map(fn task ->
      try do
        Task.await(task, @spec_timeout) # Add the timeout value here
      rescue
        Task.TimeoutError ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

  #...
end
```
The `execute_speculatively` function executes a given message by sending it to each of the worker processes in the pool and waiting for the first successful response, while `get_worker_pids` gets a specified number of worker process IDs from the supervisor. The `await_first_task` function waits for a specified timeout value for the first successful task to complete, and returns its result.

**Diagrams for week 3**
## Supervisor Tree Diagram

![SuperTree3](/diagrams/Supervisor-Tree-Diagram.png)

## Message Flow Diagram

![MessFlow3](/diagrams/Message-Flow-Diagram.png)

## P1W4
**Task 1** -- Besides printing out the redacted tweet text, the Printer actor must also calculate two values: the Sentiment Score and the Engagement Ratio of the tweet. 

```elixir
defmodule Read do
  #...

  defp send_to_worker_pool(tweet) do
    text = tweet["text"]
    favorites = tweet["favorite_count"]
    retweets = tweet["retweet_count"]
    followers = tweet["user"]["followers_count"]
    name = tweet["user"]["name"]
    # hashtags = Enum.map(tweet["entities"]["hashtags"], fn h -> h["text"] end)

    info = {text, {favorites, retweets, followers, name}}

    # Dispatcher.dispatch(info)
    send(printer_pid, info)

    if Map.get(tweet, "retweeted_status", nil) != nil do
      send_to_worker_pool(tweet["retweeted_status"])
    end
  end

  #...
end
```
First we find the needed values to compute the emotion and after sending it to Print we can compute sentiment and engagement as:

```elixir
  defp compute_engagement(favorites, retweets, followers) do
    engagement_ratio =
      if followers != 0 do
        (favorites + retweets) / followers
      else
        0
      end

    engagement_ratio
  end

  defp compute_sentiment(text, state) do
    map = HTTPoison.get!("http://localhost:4000/emotion_values")
    |> Map.get(:body)

    state = parse(map)

    words = String.downcase(text) |> String.trim() |> String.split(~r/\s+/)

    mean_score = Enum.reduce(words, 0, fn word, acc ->
      case Map.get(state, word) do
        nil -> acc
        score -> acc + score
      end
    end) / Enum.count(words)
  end
```

To compute the Sentiment Score per tweet I calculate the mean of emotional scores of each word in the tweet text. A map that links words with their scores is provided as an endpoint. If a word cannot be found in the map, it’s emotional score is equal to 0. The Engagement Ratio is calculated according to the provided formula.

**Task 2** -- Break up the logic of your current Worker into 3 separate actors: one which redacts the tweet text, another that calculates the Sentiment Score and lastly, one that computes the Engagement Ratio.

```elixir
defmodule Print do
  use GenServer

  @min_sleep_time 5
  @max_sleep_time 50

  def start_link(id) do
    IO.puts "Starting printer #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(_) do
    {:ok, {}}
  end

  def handle_cast({id, :kill}, state) do
    IO.puts("=====> Killing Printer #{id} ##")

    {:stop, :normal, state}
  end

  def handle_cast({text, id}, state) do
    sleep()

    censored_text = LoadBalancer.process(:CensorLB, text)

    #Aggregator.store_tweet(censored_text, id)
    IO.puts("#{inspect censored_text}")

    {:noreply, state}
  end

  defp sleep do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    :timer.sleep(sleep_time)
  end

end
```

```elixir
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
```

```elixir
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

    #Aggregator.store_sentiment(mean_score, id)
    IO.puts("#{mean_score}")
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
```

```elixir
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

    #EngagementTracker.store(name, engagement_ratio)

    #Aggregator.store_engagement(EngagementTracker.get_ratio(name), name, id)
    IO.puts("#{inspect engagement_ratio}")

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
```
Everything works the same way it's just that it was separated in different modules. In order to call them correctly I do:
```elixir
{text, stats} = info

{id, new_state} = generate_id(state)

Task.start(fn -> LoadBalancer.cast(:PrintLB, {text, id}) end)
Task.start(fn -> LoadBalancer.cast(:SentimentLB, {text, id}) end)
Task.start(fn -> LoadBalancer.cast(:EngagementLB, {stats, id}) end)
```
in the Reader. As I am not waiting for any response, it is a cast.

**Task 3** -- Modify your current implementation of the Worker Pool to make it generic

```elixir
defmodule GenericSupervisor do
  use Supervisor

  def start_link(worker_module, num_workers) do
    supervisor_name = generate_supervisor_name(worker_module)
    IO.puts "Starting #{supervisor_name}..."
    Supervisor.start_link(__MODULE__, %{worker_module: worker_module, num_workers: num_workers, name: String.to_atom(supervisor_name)}, name: String.to_atom(supervisor_name))
  end

  def init(state) do
    children =
      Enum.map(1..state.num_workers, fn id ->
        %{
          id: id,
          start: {state.worker_module, :start_link, [id]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end


  def get_message_count(pid) do
    GenServer.call(pid, :message_count)
  end

  def count(sup_pid) do
    Supervisor.count_children(sup_pid)
    |> Map.fetch!(:active)
  end

  def get_worker_pid(sup_pid, id) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {i, _, _, _} -> i == id end)
    |> elem(1)
  end

  def get_worker_id(sup_pid, pid) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {_, i, _, _} -> i == pid end)
    |> elem(0)
  end

  def get_all_pids(sup_pid) do
    Enum.map(1..count(sup_pid), fn i -> get_worker_pid(sup_pid, i) end)
  end

  def generate_supervisor_name(worker_module) do
    module_name = inspect(worker_module)
    String.replace_suffix(module_name, "", "Supervisor")
  end
end
```
The following is a Generic Supervisor that starts by sending it the amount of children it's supposed to have and the worker module it needs to supervise. It will generate it's name as `worker_module`'s name that was passed + `"Supervisor"` for example:

```elixir
GenericSupervisor.start_link(Print, 3)
```

will start a supervisor called `PrintSupervisor` and have 3 Print workers.

```elixir
defmodule LoadBalancer do
  use GenServer

  @load_threshold 10
  @idle_threshold 1
  @check_idle_interval 5000

  def start_link(supervisor_name, wpm_pid) do
    lb_name = generate_name(supervisor_name)
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting LoadBalancer for #{inspect supervisor_name}..."
    pid = GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, sup_pid: GenServer.whereis(supervisor_name), wpm_pid: wpm_pid, lb_name: lb_name})
    |> elem(1)
    Process.register(pid, lb_name)
  end

  def init(state) do
    if state.wpm_pid != nil do
      schedule_check_idle()
    end

    {:ok, state}
  end

  def handle_cast({info, id}, state) do
    worker_pid = least_connected_worker(state)
    GenServer.cast(worker_pid, {info, id})
    {:noreply, state}
  end

  def handle_call(info, _from, state) do
    worker_pid = least_connected_worker(state)
    # IO.puts "Least connected worker: #{inspect find_id(worker_pid, state)} with #{inspect Process.info(worker_pid)[:message_queue_len]} messages"
    response = GenServer.call(worker_pid, {find_id(worker_pid, state), info})
    {:reply, response, state}
  end

  def handle_info(:check_idle, state) do
    worker_pid = least_connected_worker(state)
    check_idle(worker_pid, state)
    schedule_check_idle()
    {:noreply, state}
  end

  def process(lb_name, info) do
    GenServer.call(GenServer.whereis(lb_name), info)
  end

  def cast(lb_name, {info, id}) do
    GenServer.cast(GenServer.whereis(lb_name), {info, id})
  end

  def schedule_check_idle do
    Process.send_after(self(), :check_idle, @check_idle_interval)
  end

  defp check_idle(pid, state) do
    if Process.info(pid)[:message_queue_len] > @load_threshold do
      IO.puts "\n\n====>>>#{state.lb_name}: Workers are overloaded."
      WorkerPoolManager.increase_workers(state.wpm_pid, 1)
    else
      if Process.info(pid)[:message_queue_len] < @idle_threshold and Process.info(pid)[:message_queue_len] > 1 do
        IO.puts "\n\n====>>>#{state.lb_name}: Workers are idle."
        WorkerPoolManager.decrease_workers(state.wpm_pid, 1)
      end
    end
  end

  defp least_connected_worker(state) do
    worker_pids = get_all_pids(state)
    counts = all_workers_queue_len(worker_pids)
    Enum.min_by(counts, fn {_, count} -> count end)
    |> elem(0)
  end

  defp all_workers_queue_len(worker_pids) do
    Enum.map(worker_pids, fn pid ->
      {pid, Process.info(pid)[:message_queue_len]}
    end)
  end

  defp find_id(worker_pid, state) do
    GenericSupervisor.get_worker_id(state.sup_pid, worker_pid)
  end

  defp get_all_pids(state) do
    GenericSupervisor.get_all_pids(state.sup_pid)
  end

  defp generate_name(supervisor_name) do
    String.to_atom(String.replace(supervisor_name, "Supervisor", "LB"))
  end
end

```
Similar to GenericSupervisor, LoadBalancer is generic as well. In a similar manner it generates it's name depending on the supervisor it balances, that is, it gets the name of the supervisor and replaces the `"Supervisor"` part with `"LB"` short for Load Balancer.

```elixir
defmodule WorkerPoolManager do
  use GenServer

  @max_num_workers 100
  @min_num_workers 1

  @spec_num_workers 3
  @spec_timeout 5000

  def start_link(supervisor_name, worker) do
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting WorkerPoolManager for...#{inspect supervisor_name}"
    GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, worker: worker, sup_pid: GenServer.whereis(supervisor_name)}, name: String.to_atom("WPM" <> inspect(worker)))
    |> elem(1)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:increase_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers + num

    new_num_workers = min(new_num_workers, @max_num_workers)

    if new_num_workers > current_num_workers do
      start_workers(new_num_workers - current_num_workers, state)
    end

    {:noreply, state}
  end

  def handle_cast({:decrease_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers - num

    new_num_workers = max(new_num_workers, @min_num_workers)

    if new_num_workers < current_num_workers do
      stop_workers(current_num_workers - new_num_workers, state)
    end

    {:noreply, state}
  end

  def increase_workers(pid, num) do
    GenServer.cast(pid, {:increase_workers, num})
  end

  def decrease_workers(pid, num) do
    GenServer.cast(pid, {:decrease_workers, num})
  end

  defp start_workers(num, state) do
    children_to_add = Enum.map(count_workers(state)+1..count_workers(state)+num, fn id ->
      %{
        id: id,
        start: {state.worker, :start_link, [id]}
      }
    end)

    Enum.each(children_to_add, fn child ->
      if Enum.any?(Supervisor.which_children(state.sup_pid), fn {id, _, _, _} -> id == child.id end) do
        Supervisor.restart_child(state.sup_pid, child.id)
      else
        Supervisor.start_child(state.sup_pid, child)
      end
    end)

    {:ok, state}
  end

  defp stop_workers(num, state) do
    Enum.map(count_workers(state)-num+1..count_workers(state), fn id ->
      IO.puts("Stopping worker #{id}")
      Supervisor.terminate_child(state.sup_pid, id)
    end)

    {:ok, state}
  end

  defp count_workers(state) do
    GenericSupervisor.count(state.sup_pid)
  end

  def execute_speculatively(message) do
    worker_pids = get_worker_pids(@spec_num_workers)

    tasks = Enum.map(worker_pids, fn worker_pid ->
      Task.async(fn ->
        ref = make_ref()
        send(worker_pid, {PrintSupervisor.get_worker_id(worker_pid), message, self(), ref})
        receive do
          {^ref, :result, result} -> result
        after
          @spec_timeout -> nil
        end
      end)
    end)

    await_first_task(tasks)
  end

  defp get_worker_pids(num_workers) do
    PrintSupervisor |> Supervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.take(num_workers)
  end

  defp await_first_task(tasks) do
    tasks
    |> Enum.map(fn task ->
      try do
        Task.await(task, @spec_timeout) # Add the timeout value here
      rescue
        Task.TimeoutError ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

end
```
The Worker Pool Manager is also generic, working based on the supervisor's name that is passed in.

A Worker Pool Manager is an optional attribute for Load Balancer, such that in case the pid for it is `nil`, the scheduling functionality simply won't be triggered.

As seen, the LoadBalancer, WorkerPoolManager and Supervisor modules were all made generic.

**Task 4** -- Create 3 Worker Pools that would process the tweet stream in parallel

```elixir
    GenericSupervisor.start_link(Print, 3)
    GenericSupervisor.start_link(Engagement, 3)
    GenericSupervisor.start_link(Sentiment, 3)
    GenericSupervisor.start_link(Censor, 3)

    w1 = WorkerPoolManager.start_link(print_sup_name, Print)

    true = LoadBalancer.start_link(print_sup_name, w1)
    true = LoadBalancer.start_link(eng_sup_name, nil)
    true = LoadBalancer.start_link(sent_sup_name, nil)
    true = LoadBalancer.start_link(censor_sup_name, nil)
```
the sup_names are generated by the Supervisor module as "PrintSupervisor", "SentimentSupervisor" and so on.

We will se the parallel aspect more in detail when reaching the Aggregator task.

**Task 5** -- Add functionality to your system such that it would allow for computing the Engagement Ratio per User.

```elixir
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
```
The only difference is that the Engagement worker after computing the ratio should call the EngagementTracker in order to store it for the username it computed it with.

```elixir
defmodule EngagementTracker do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(_) do
    {:ok, %{user_ratios: %{}}}
  end

  def store(name, engagement_ratio) do
    GenServer.call(__MODULE__, {:store, name, engagement_ratio})
  end

  def get_ratio(name) do
    GenServer.call(__MODULE__, {:get_ratio, name})
  end

  def handle_call({:store, name, engagement_ratio}, _from, state) do
    user_ratios = Map.get(state, :user_ratios)
    updated_user_ratios = update_user_ratios(user_ratios, name, engagement_ratio)

    {:reply, :ok, %{state | user_ratios: updated_user_ratios}}
  end

  def handle_call({:get_ratio, name}, _from, state) do
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

  defp update_user_ratios(user_ratios, name, engagement_ratio) do
    current_ratios = Map.get(user_ratios, name, [])
    updated_ratios = [engagement_ratio | current_ratios]
    Map.put(user_ratios, name, updated_ratios)
  end
end
```
The EngagementTracker has the possibility to both store and get the engagement for a user by storing that in a map, internally.

**Diagrams for week 4**
## Supervisor Tree Diagram

![SuperTree4](/diagrams/Supervisor-Tree4.png)

## Message Flow Diagram

![MessFlow4](/diagrams/Message-Flow4.png)

## P1W5

**Task 1** -- Create an actor that would collect the redacted tweets from Workers and would print them in batches.

```elixir
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
        print(acc)
        schedule_timeout()
        send(self(), {:process_batch, []})
      end
    end

    {:noreply, %{acc: acc}}
  end

  def handle_info(:timeout, state) do
    acc = state.acc

    if length(acc) > 0 do
      print(acc)
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
```
Now with this worker instead of printing the tweets one by one, they will be printed only if there are `@batch` tweets ready, together with all the information computed about it.

**Task 2** -- Create an actor that would collect the redacted tweets, their Sentiment Scores and their Engagement Ratios and would aggregate them together.

```elixir
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

  def store_engagement(engagement, username, id) do
    GenServer.cast(__MODULE__, {:engagement, engagement, username, id})
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

  def handle_cast({:engagement, engagement, username, id}, state) do
    new_state = Map.update(state, id, %{engagement: engagement}, &Map.put(&1, :engagement, engagement))
    new_state = Map.update(new_state, id, %{username: username}, &Map.put(&1, :username, username))
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

    tweets = Enum.map(selected_tweets, fn {_id, tweet} -> %{tweet: tweet.tweet, sentiment: tweet.sentiment, engagement: tweet.engagement, username: tweet.username} end)

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
```
The Aggregator will need to understand what tweet a certain piece of information is related to, thus instead of just sending the info (tweet, sentiment...) I also send the id it is related to.

After storing the info, I check whether the tweet is completed and in case it has all 3 (text, sentiment and engagement) the completed attributed is set to true.

In order to generate the ID I now have a Dispatcher module

```elixir
defmodule Dispatcher do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{id: 0})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(state) do
    EngagementTracker.start_link()

    print_sup_name = GenericSupervisor.generate_supervisor_name(Print)
    eng_sup_name = GenericSupervisor.generate_supervisor_name(Engagement)
    sent_sup_name = GenericSupervisor.generate_supervisor_name(Sentiment)
    censor_sup_name = GenericSupervisor.generate_supervisor_name(Censor)

    GenericSupervisor.start_link(Print, 3)
    GenericSupervisor.start_link(Engagement, 3)
    GenericSupervisor.start_link(Sentiment, 3)
    GenericSupervisor.start_link(Censor, 3)

    w1 = WorkerPoolManager.start_link(print_sup_name, Print)

    true = LoadBalancer.start_link(print_sup_name, w1)
    true = LoadBalancer.start_link(eng_sup_name, nil)
    true = LoadBalancer.start_link(sent_sup_name, nil)
    true = LoadBalancer.start_link(censor_sup_name, nil)
    {:ok, state}
  end

  def dispatch(info) do
    GenServer.cast(__MODULE__, info)
  end

  def handle_cast(info, state) do

    {text, stats} = info

    {id, new_state} = generate_id(state)

    Task.start(fn -> LoadBalancer.cast(:PrintLB, {text, id}) end)
    Task.start(fn -> LoadBalancer.cast(:SentimentLB, {text, id}) end)
    Task.start(fn -> LoadBalancer.cast(:EngagementLB, {stats, id}) end)

    {:noreply, new_state}
  end

  def generate_id(state) do
    id = state.id + 1
    new_state = Map.put(state, :id, id)

    {id, new_state}
  end
end
```

`generate_id()` is simply iterating starting from 1 for the tweet Id, after which it sends the info with the id to the according LoadBalancer.

**Task 3** -- If, in a given time window, the Batcher does not
receive enough data to print a batch, it should still print it.

```elixir
defmodule Batcher do
  use GenServer

  @batch 5
  @timeout 5000

  #...

  def init(state) do
    schedule_timeout()
    send(self(), {:process_batch, []})
    {:ok, state}
  end

  #...

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

  #...
end
```

The Batcher module schedules a timeout message when it starts, and when it processes a batch. The `handle_info` function has been updated to handle the `:timeout` message. If there are any tweets in the accumulator when the timeout occurs, it will print the current batch and schedule the next timeout.

**Task 4** -- Modify your current system to be able to handle retweets.

```elixir
defmodule Read do
  #...

  defp process_event("event: \"message\"\n\ndata: " <> message) do
    {success, data} = Jason.decode(String.trim(message))

    if success == :ok do
      send_to_worker_pool(data["message"]["tweet"])
    end
  end

  defp send_to_worker_pool(tweet) do
    text = tweet["text"]
    favorites = tweet["favorite_count"]
    retweets = tweet["retweet_count"]
    followers = tweet["user"]["followers_count"]
    name = tweet["user"]["name"]
    # hashtags = Enum.map(tweet["entities"]["hashtags"], fn h -> h["text"] end)

    info = {text, {favorites, retweets, followers, name}}

    Dispatcher.dispatch(info)

    if Map.get(tweet, "retweeted_status", nil) != nil do
      send_to_worker_pool(tweet["retweeted_status"])
    end
  end
  
  #...
end
```
Having this functionality in place, in case the `retweet_status` of the tweet is not nil, that tweet will also be sent to be proccesed, until the field becomes nil.

**Task 5** -- Implement the “Reactive Pull” backpressure mechanism between the Batcher and Aggregator.

```elixir
defmodule Aggregator do
  #...

  def handle_call(batch, _from, state) do
    completed_tweets = state
      |> Map.to_list()
      |> Enum.filter(fn {_id, tweet} -> tweet[:completed] == true end)

    {selected_tweets, _remaining_completed} = Enum.split(completed_tweets, batch)

    new_state = Enum.reduce(selected_tweets, state, fn {id, _}, acc ->
      Map.delete(acc, id)
    end)

    tweets = Enum.map(selected_tweets, fn {_id, tweet} -> %{tweet: tweet.tweet, sentiment: tweet.sentiment, engagement: tweet.engagement, username: tweet.username} end)

    {:reply, tweets, new_state}
  end

  def send_batch(value) do
    GenServer.call(GenServer.whereis(__MODULE__), value)
  end
end
```
Instead of the Aggregator sending the completed tweet, the moment it realises it's completed, it instead keeps storing it in the map. When the `send_batch()` function is being called by the Batcher, the Aggregator filters the map to find which tweets are already completed. Out of them it chooses @batch number and the ones chosen are being deleted from the map. These @batch completed tweets are returned as reply.

```elixir
defmodule Batcher do
  use GenServer

  @batch 5
  #...

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

  #...
end
```
The Batcher sends a request for @batch tweets using `Aggregator.send_batch(@batch)`. However it might be that there are no @batch tweets completed yet and maybe just a few. That's why there is an additional check in place and an additional request for `@batch-provided` tweets until the quota is reached or a timeout occurs.

**Diagrams for week 5**
## Supervisor Tree Diagram

![SuperTree5](/diagrams/Supervisor-Tree5.png)

## Message Flow Diagram

![MessFlow5](/diagrams/Message-Flow5.png)

## P1W6

**Task 1** -- Create a database that would store the tweets processed by your system.

```elixir
defmodule Database do
  @table_tweets :tweets

  def start_link() do
    :ets.new(@table_tweets, [:named_table, :set, :public, {:keypos, 1}])
    :ok
  end

  def store_tweet(%{tweet: tweet, sentiment: sentiment, engagement: engagement} = full_tweet) do
    # Store tweet information
    tweet_id = :crypto.strong_rand_bytes(16) |> Base.encode64
    :ets.insert(@table_tweets, {tweet_id, user_id, tweet, sentiment, engagement})
  end

  def get_tweets() do
    :ets.tab2list(@table_tweets)
  end
end
```
This is a module for a simple in-memory database using ETS. Starts a new table at init for tweets. In case a tweet needs to be stored, an id for it is computed using crypto and inserted in the table.

**Task 2** -- Instead of printing the batches of tweets, the
actor should now send them to the database, which will persist them.

```elixir
defmodule Batcher do
  #...

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

  #...

  def store(acc) do
    Enum.each(acc, &Database.store_tweet/1)
    # IO.puts("#{inspect DatabaseProxy.get_tweets()}")
  end
end
```

Instead of calling the print function we simply store each tweet in the Database.

**Task 3** -- Persist Users and Tweets in separate
tables or collections. Make sure not to lose which user posted which tweets.

```elixir
defmodule Database do
  @table_tweets :tweets
  @table_users :users

  def start_link() do
    :ets.new(@table_tweets, [:named_table, :set, :public, {:keypos, 1}])
    :ets.new(@table_users, [:named_table, :set, :public, {:keypos, 1}])
    :ok
  end

  def store_tweet_and_user(%{tweet: tweet, sentiment: sentiment, engagement: engagement, username: username} = full_tweet) do
    # Store user information
    user_id = :crypto.strong_rand_bytes(16) |> Base.encode64
    :ets.insert(@table_users, {user_id, username})

    # Store tweet information
    tweet_id = :crypto.strong_rand_bytes(16) |> Base.encode64
    :ets.insert(@table_tweets, {tweet_id, user_id, tweet, sentiment, engagement})
  end

  def get_tweets() do
    :ets.tab2list(@table_tweets)
  end

  def get_users() do
    :ets.tab2list(@table_users)
  end

  def get_user_tweets(username) do
    # Find the user by username
    user = :ets.match_object(@table_users, {:"$1", username}) |> List.first()

    # If a user is found, retrieve their tweets
    if user do
      user_id = elem(user, 0)
      :ets.match_object(@table_tweets, {:"$1", user_id, :"$2", :"$3", :"$4"})
      |> Enum.map(fn {_, _, tweet, sentiment, engagement} -> %{tweet: tweet, sentiment: sentiment, engagement: engagement} end)
    else
      [] # return an empty list if the user is not found
    end
  end
end
```

Instead of simply storing the tweet we create a new table for the usernames. However despite that, we also store the user_id in the according tweet as well, in order to retreieve the tweets posted by that user.

**Task 4** -- Implement a resumable / pausable transmission
towards the database (e.g. in case of DB unavailability).

```elixir
defmodule DatabaseProxy do
  use GenServer

  def start_link() do
    pid = GenServer.start_link(__MODULE__, [])
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(_) do
    Database.start_link()
    {:ok, %{queue: :queue.new(), paused: false}}
  end

  def add_item(item) do
    GenServer.cast(__MODULE__, {:add_item, item})
  end

  def toggle_pause() do
    GenServer.call(__MODULE__, :toggle_pause)
  end

  def get_tweets() do
    GenServer.call(__MODULE__, :get)
  end

  def handle_cast({:add_item, item}, %{queue: queue, paused: paused} = state) do
    if paused do
      {:noreply, %{state | queue: :queue.in(item, queue)}}
    else
      Database.store_tweet_and_user(item)
      {:noreply, state}
    end
  end

  def handle_call(:toggle_pause, _from, %{paused: paused} = state) do
    new_state = %{state | paused: !paused}
    {:reply, {:ok, !paused}, process_queue(new_state)}
  end

  def handle_call(:get, _from, %{paused: paused} = state) do
    reply = if paused do
      IO.puts("Database currently unavailable.")
    else
      Database.get_tweets()
    end
    {:reply, reply, state}
  end

  defp process_queue(%{queue: queue, paused: false} = state) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        Database.store_tweet_and_user(item)
        process_queue(%{state | queue: new_queue})

      {:empty, _} ->
        state
    end
  end

  defp process_queue(state) do
    state
  end
end
```

For this functionality I created another module which acts as a Proxy. In order to make the unavailability of the DB toggable and simplistic, it's a simple boolean inside the state of the module. In case the DB is toggled off, the tweets will instead be stored in a map inside the state of this Proxy and on get requests, display that DB is unavailable at the moment.

When the DB becomes available again, all the tweets stored in the map will be stored in the DB and the get requests will be available again.

**Diagrams for week 6**
## Supervisor Tree Diagram

![SuperTree6](/diagrams/Supervisor-Tree6.png)

## Message Flow Diagram

![MessFlow6](/diagrams/Message-Flow6.png)

## Conclusion

This laboratory project was highly informative and provided us with important insights into the design of scalable and adaptable software architectures. 

Additionally, we gained experience with a number of advanced techniques and technologies, including stream processing, Reactive Pull, and speculative execution as well as load balancing, with a particular emphasis on round-robin and least-connected techniques. 

Our experimentation with these approaches helped us to better understand their respective strengths and limitations, and to appreciate their importance for achieving optimal performance and reliability in distributed systems. 

Overall, this project provided us with a challenging and rewarding opportunity to apply these concepts in a real-world context, specifically in the context of processing tweets.

## Bibliography

1. [Elixir](https://elixir-lang.org/)
2. [Elixir Documentation](https://elixir-lang.org/docs.html)
3. [Supervisor](https://hexdocs.pm/elixir/Supervisor.html)
4. [GenServer](https://hexdocs.pm/elixir/GenServer.html)
5. [ETS](https://elixir-lang.org/getting-started/mix-otp/ets.html)
6. [Reactive Pull](https://subscription.packtpub.com/book/programming/9781788629775/1/ch01lvl1sec14/pull-versus-push-based-reactive-programming)
7. [Load Balancing Algorithms](https://subscription.packtpub.com/book/programming/9781788629775/1/ch01lvl1sec14/pull-versus-push-based-reactive-programming)
8. [Speculative execution of Tasks](https://en.wikipedia.org/wiki/Speculative_execution)