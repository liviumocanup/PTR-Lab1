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
