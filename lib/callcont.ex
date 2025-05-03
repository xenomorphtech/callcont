defmodule CallCont do
  @moduledoc false

  ## ────────────────────────────────────────────────────────────────────
  ## Public helpers
  ## ────────────────────────────────────────────────────────────────────
  def lift(x), do: x

  defmacro make_cc(mod, fun, args) do
    quote do
      Macro.escape({:call, unquote(mod), unquote(fun), unquote(args)})
    end
  end

  ## ────────────────────────────────────────────────────────────────────
  ## __using__
  ## ────────────────────────────────────────────────────────────────────
  defmacro __using__(_opts) do
    quote do
      import CallCont
      require CallCont

      @dialyzer {:nowarn_function, runIO: 1}
      @dialyzer {:nowarn_function, runIO: 2}
    end
  end

  ## ────────────────────────────────────────────────────────────────────
  ## def_io
  ## ────────────────────────────────────────────────────────────────────

  # one macro covers both the “<-” and pure cases
  defmacro def_io({name, loc, args} = _head, do: body) do
    if contains_bind?(body) do
      # impure / continuation-style
      blocks = split_blocks(body)
      fun_asts = build_functions(blocks, name, loc, args, __CALLER__)

      quote do
        (unquote_splicing(fun_asts))
      end
    else
      # pure – emit a normal def
      quote do
        def unquote(name)(unquote_splicing(args)), do: unquote(body)
      end
    end
  end

  ## ────────────────────────────────────────────────────────────────────
  ## runIO interpreter helpers
  ## ────────────────────────────────────────────────────────────────────
  defmacro runIO_pre do
    quote do
      def runIO(expr), do: runIO([], expr)

      def runIO(stack, {:call, m, f, p}),
        do: runIO([{:call, m, f, p} | stack], nil)

      def runIO(stack, [{:call, m, f, p}, {:continue, cm, cf, cp}]),
        do: runIO([{:call, m, f, p}, {:continue, cm, cf, cp} | stack], nil)

      def runIO([], res), do: res
    end
  end

  defmacro runIO_pos do
    quote do
      def runIO([frame | rest], res) do
        case frame do
          {:call, CallCont, :lift, [v]} -> runIO(rest, v)
          {:call, m, f, a} -> runIO(rest, apply(m, f, a))
          {:continue, m, f, a} -> runIO(rest, apply(m, f, [res | a]))
        end
      end
    end
  end

  ## ────────────────────────────────────────────────────────────────────
  ##  Implementation (private)
  ## ────────────────────────────────────────────────────────────────────

  # ------- block splitter -------------------------------------------------
  defp split_blocks({:__block__, _, exprs}), do: do_split(exprs, [], [])
  defp split_blocks(expr), do: do_split([expr], [], [])

  defp do_split([], acc_exprs, acc_blocks),
    do: Enum.reverse([{nil, Enum.reverse(acc_exprs)} | acc_blocks])

  defp do_split([{:<-, _, _} = bind | rest], acc_exprs, acc_blocks) do
    do_split(rest, [], [{bind, Enum.reverse(acc_exprs)} | acc_blocks])
  end

  defp do_split([e | rest], acc_exprs, acc_blocks),
    do: do_split(rest, [e | acc_exprs], acc_blocks)

  # ------- function builder ----------------------------------------------
  defp build_functions(blocks, fname, loc, args, caller) do
    ctx0 = %{
      vars: varmap(args),
      args: args,
      name: fname,
      loc: loc,
      mod: caller.module,
      last: nil,
      out: []
    }

    final =
      Enum.with_index(blocks)
      |> Enum.reduce(ctx0, &produce_fun/2)

    Enum.reverse(final.out)
  end

  defp produce_fun({{bind, exprs}, idx}, ctx) do
    case bind do
      nil ->
        body = wrap(exprs)
        %{ctx | out: [mk_def(idx, body, ctx) | ctx.out]}

      {:<-, _, [{bound, _, _}, rhs]} ->
        {mod, fun, params} = normalize_call(rhs, ctx.mod)

        env_vars =
          ctx.vars
          |> Map.keys()
          |> Enum.reject(&(&1 == bound))
          |> Enum.map(&{&1, [], nil})

        call =
          quote do
            [
              {:call, unquote(mod), unquote(fun), unquote(params)},
              {:continue, unquote(ctx.mod), unquote(cont_name(ctx.name, idx + 1)),
               unquote(env_vars)}
            ]
          end

        body = wrap(exprs ++ [call])

        ctx
        |> Map.update!(:out, &[mk_def(idx, body, ctx) | &1])
        |> Map.update!(:vars, &Map.put(&1, bound, true))
        |> Map.put(:last, bound)
    end
  end

  # ------- helpers --------------------------------------------------------
  defp mk_def(idx, body, ctx) do
    fun = if idx == 0, do: ctx.name, else: cont_name(ctx.name, idx)

    args =
      if idx == 0 do
        ctx.args
      else
        env =
          ctx.vars
          |> Map.delete(ctx.last)
          |> Map.keys()
          |> Enum.map(&{&1, [], nil})

        [{ctx.last, [], nil} | env]
      end

    quote do
      def unquote(fun)(unquote_splicing(args)), do: unquote(body)
    end
  end

  defp wrap(exprs), do: {:__block__, [], exprs}

  defp cont_name(base, idx), do: :"#{base}_cont_#{idx}"

  # variable harvest
  defp varmap(list) when is_list(list) do
    list
    |> Enum.flat_map(fn arg ->
      {_, vars} =
        Macro.prewalk(arg, [], fn
          {v, _, ctx} = node, acc when is_atom(v) and ctx in [nil, Elixir] ->
            {node, [v | acc]}

          node, acc ->
            {node, acc}
        end)

      vars
    end)
    |> Map.new(&{&1, true})
  end

  # detect a <- anywhere
  defp contains_bind?({:<-, _, _}), do: true
  defp contains_bind?({:__block__, _, exprs}), do: Enum.any?(exprs, &contains_bind?/1)
  defp contains_bind?(list) when is_list(list), do: Enum.any?(list, &contains_bind?/1)
  defp contains_bind?(_), do: false

  # call normaliser  (local or remote)
  defp normalize_call({{:., _, [m_ast, f]}, _, params}, _caller),
    do: {resolve_mod(m_ast), f, params}

  defp normalize_call({f, _, params}, caller), do: {caller, f, params}

  defp resolve_mod({:__aliases__, _, parts}), do: Module.concat(parts)
  defp resolve_mod(atom) when is_atom(atom), do: atom
  defp resolve_mod({var, _, _}), do: var
end
