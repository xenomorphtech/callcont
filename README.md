# Callcont

this code is very immature, use at your own risk :)

this was written to mangle execution the flow

```elixir
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
```

the <- operator will split the current function into 2 functions, example:

```elixir
defmodule TestMod do
import CallCont
def_io f(a) do
  b = 0
  x <- something(a)
  x
end
def something(a) do
a + 1
end
end
```
becomes
```
defmodule TestMod do
def f(a) do
  b = 0
  [
  {:call, TestMod, :something, [a]},
  {:continue, TestMod, :f_cont_1, [a, b]}
  ]
end
def f_cont_1(x, a, b) do
  x 
end
end
```

current caveats (dos and do not do)
###
<- only works on the root level of a function, not on nested blocks, which means u have to flatten your control flow
when calling a `def_io` function inside a block, it must be the last statement
```
  action = if a do
       some_io(a)
     end
     
  res <- lift(action)
```

todo:
###
remove unused variables passing to the next block (optimization)
add a `pure` operation to wrap values 
