defmodule CallcontTest do
  use ExUnit.Case
  #doctest Callcont

  import CallCont

  def_io somefunc(a) do
    something = 1
    [b = 3, %{c: d}, [{e, e}]] = [3, %{c: 4}, [{5, 5}]]
    res1 <- __MODULE__.execute(a)
    something2 = 2
    res <- execute(res1)
    res <- :timer.sleep(1000)
    IO.puts("context? #{inspect(res)} #{something} #{something2}")
  end

  def execute(a) do
    res = a + 1
  end

  def test() do
    IO.inspect(__MODULE__.somefunc(1))

    u = CallCont.runIO(__MODULE__.somefunc(1), nil)
    IO.inspect({:last_res, u})
  end
end
