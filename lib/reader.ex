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
      Process.sleep(1000)
      tweet = data["message"]["tweet"]
      text = tweet["text"]
      hashtags = tweet["entities"]["hashtags"]

      LoadBalancer.print(text)
      Enum.each(hashtags, fn hashtag -> Analyzer.analyze_hashtag(hashtag["text"]) end)
    end
  end

  defp process_event(_corrupted_event) do
    IO.puts("## Killing Printer ##")
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