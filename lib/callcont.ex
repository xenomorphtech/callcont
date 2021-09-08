defmodule CallCont do
  def lift(s) do
    s
  end

  defmacro make_cc(module, function, args) do
    quote do
      make_cc_args = unquote(args)
      Macro.escape({:call, unquote(module), unquote(function), make_cc_args})
    end
  end

  defmacro def_io(what, what2) do
    IO.inspect(what)
    {name, location, args} = what
    IO.inspect(what2)

    # find any do
    [
      do: exprs
    ] = what2

    case exprs do
      {:__block__, _, _} ->
        blocks = IO.inspect(split_block_0(exprs, [], []))
        def_io_1(blocks, {name, location, args}, __CALLER__)

      _ ->
        {:def, [context: CallCont, import: Kernel],
         [
           {name, location, args},
           [do: exprs]
           # [line: 69], [{:a, [line: 69], nil}]
         ]}
    end
  end

  defp def_io_1(blocks, {name, location, args}, caller) do
    context = %{
      vars: vars2(args, %{}),
      args: args,
      fname: name,
      flocation: location,
      newfuns: [],
      last_bound: nil,
      module: caller.module
    }

    context =
      Enum.reduce(Enum.with_index(blocks), context, fn {block, index}, context ->
        {context, res} = produce_continuation(block, index, context)
        context = Map.put(context, :newfuns, [res | context.newfuns])
        context
      end)

    context.newfuns
  end

  def produce_continuation({bentry, b1}, index, context) do
    #    IO.inspect({:context, context})

    args =
      if index == 0 do
        context.args
      else
        vars = context.vars |> Map.delete(context.last_bound)
        res = vars |> Map.keys() |> Enum.map(fn a -> {a, [], nil} end)
        [{context.last_bound, [], nil} | res]
      end

    {body, context} =
      if bentry == nil do
        {{:__block__, [], b1}, context}
      else
        {:<-, _,
         [
           {bname, _, nil},
           {fname, _, params}
         ]} = bentry

        {call_module, call_fname} =
          case fname do
            name when is_atom(name) ->
              {context.module, name}

            {:., _which_line, [modulename, fname]} ->
              modulename =
                case modulename do
                  name when is_atom(name) ->
                    name

                  {:__aliases__, _, modulenames} ->
                    :"#{Enum.join(["Elixir" | modulenames], ".")}"

                  {atom, _, n} = var when is_atom(atom) and n in [Elixir, nil] ->
                    var
                end

              {modulename, fname}
          end

        vars_in_block =
          if context.last_bound do
            Map.put(context.vars, context.last_bound, 1)
          else
            context.vars
          end

        vars_in_block = vars(b1, vars_in_block) |> Map.delete(bname)
        vars_to_pass = vars_in_block |> Map.keys() |> Enum.map(fn a -> {a, [], nil} end)

        IO.inspect({:b1, b1})

        body =
          {:__block__, [],
           b1 ++
             quote do
               [
                 [
                   {:call, unquote(call_module), unquote(call_fname), unquote(params)},
                   {:continue, unquote(context.module),
                    unquote(:"#{context.fname}_cont_#{index + 1}"), unquote(vars_to_pass)}
                 ]
               ]
             end}

        IO.inspect(body)

        IO.inspect(vars(b1, %{}))

        vars_in_block =
          if context.last_bound do
            Map.put(vars_in_block, context.last_bound, 1)
          else
            vars_in_block
          end

        context = Map.put(context, :vars, vars_in_block)
        context = Map.put(context, :last_bound, bname)

        {body, context}
      end

    fun_name =
      if index != 0 do
        :"#{context.fname}_cont_#{index}"
      else
        :"#{context.fname}"
      end

    res =
      {:def, [context: CallCont, import: Kernel],
       [
         {fun_name, context.flocation, args},
         [do: body]
         # [line: 69], [{:a, [line: 69], nil}]
       ]}

    IO.inspect(res)

    {context, res}
  end

  def vars([], acc) do
    acc
  end

  def vars([{:=, _, [side_a, _side_b]} | rest], acc) do
    acc = vars2(side_a, acc)
    vars(rest, acc)
  end

  def vars([_ | rest], acc) do
    vars(rest, acc)
  end

  def vars2([], acc) do
    acc
  end

  def vars2({name, [line: _], nil}, acc) do
    acc = Map.put(acc, name, 1)
  end

  def vars2({:=, _, [side_a, side_b]}, acc) do
    vars2(side_a, vars2(side_b, acc))
  end

  def vars2({:%{}, _, key_val}, acc) do
    vals = Enum.map(key_val, fn {a, b} -> b end)
    IO.inspect({:map_vals, vals})
    vars2(vals, acc)
  end

  def vars2([e | rest], acc) do
    vars2(rest, vars2(e, acc))
  end

  def vars2(e, acc) when is_tuple(e) do
    IO.inspect({:discarding_tupple, e})

    elements =
      Enum.map(1..10, fn i ->
        try do
          eleme = :erlang.element(i, e)
          vars2(eleme, %{}) |> Map.to_list()
        catch
          _, _ -> []
        end
      end)

    elements = List.flatten(elements)
    IO.inspect({:elements, elements})

    Enum.reduce(Enum.filter(elements, &(&1 != [])), acc, fn {k, v}, acc ->
      Map.put(acc, k, v)
    end)
  end

  def vars2(e, acc) do
    IO.inspect({:discarding, e})
    acc
  end

  def split_block_0({:__block__, _, exprs}, [], []) do
    split_block(exprs, [], [])
  end

  def split_block_0(exprs, [], []) do
    split_block([exprs], [], [])
  end

  def split_block([], things, blocks) do
    :lists.reverse([{nil, :lists.reverse(things)} | blocks])
  end

  def split_block(
        [
          {:<-, _metadata,
           [
             _val,
             _another
           ]} = entry
          | rest
        ],
        things,
        blocks
      ) do
    # metadata = [line: 24]
    newblock = {entry, :lists.reverse(things)}
    split_block(rest, [], [newblock | blocks])
  end

  def split_block(
        [entry | rest],
        things,
        blocks
      ) do
    split_block(rest, [entry | things], blocks)
  end

  def runIO(res) do
    runIO([], res)
  end

  def runIO(
        callstack,
        {:call, call_m, call_f, call_p}
      ) do
    callstack = [
      {:call, call_m, call_f, call_p} | callstack
    ]

    runIO(callstack, nil)
  end

  def runIO(callstack, [
        {:call, call_m, call_f, call_p},
        {:continue, cont_m, cont_f, cont_p}
      ]) do
    callstack = [
      {:call, call_m, call_f, call_p},
      {:continue, cont_m, cont_f, cont_p} | callstack
    ]

    runIO(callstack, nil)
  end

  def runIO([], res) do
    res
  end

  def runIO([io | callstack], res) do
    case io do
      {:call, module, fname, params} ->
        IO.inspect({:calling, module, fname, params})
        res = Kernel.apply(module, fname, params)
        runIO(callstack, res)

      {:continue, module, fname, params} ->
        IO.inspect({:calling, module, fname, [res | params]})
        res = Kernel.apply(module, fname, [res | params])
        runIO(callstack, res)

      pure_res ->
        runIO(callstack, pure_res)
    end
  end

  def lift([io | callstack], res) do
  end
end

