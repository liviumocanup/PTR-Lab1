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
    # hashtags = Enum.map(tweet["entities"]["hashtags"], fn h -> h["text"] end)

    info = {text, {favorites, retweets, followers, name}}

    Dispatcher.dispatch(info)

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
