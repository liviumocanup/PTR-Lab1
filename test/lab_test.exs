defmodule LabTest do
  use ExUnit.Case
  doctest Lab

  test "greets the world" do
    assert Lab.hello() == :world
  end
end
