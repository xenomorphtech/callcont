defmodule CallContTest.Helpers do
  def add(a, b), do: a + b
  def mul(a, b), do: a * b
end

defmodule CallContTest do
  use ExUnit.Case, async: true

  ## ------------------------------------------------------------------
  ##  Programs that exercise CallCont
  ## ------------------------------------------------------------------
  defmodule IOPrograms do
    use CallCont
    import CallCont
    require CallCont

    # Glue the small interpreter in
    runIO_pre()
    runIO_pos()

    ## 0.  Pure function (no “<-” at all)
    def_io inc(x) do
      x + 1
    end

    ## 1.  Single continuation
    def_io twice_sum(a, b) do
      s <- CallContTest.Helpers.add(a, b)
      s * 2
    end

    ## 2.  Two chained continuations
    def_io chain(x) do
      y <- CallContTest.Helpers.add(x, 3)
      z <- CallContTest.Helpers.mul(y, 2)
      y + z
    end

    ## 3.  Using CallCont.lift/1 to bring a pure value into the IO world
    def_io lift42() do
      v <- CallCont.lift(42)
      v * 2
    end

    ## 4.  Re-binding the same variable name across continuations
    def_io rebinding(n) do
      n <- CallContTest.Helpers.add(n, 1)
      n <- CallContTest.Helpers.mul(n, 2)
      n
    end
  end

  ## ------------------------------------------------------------------
  ##  Specifications
  ## ------------------------------------------------------------------

  # 0.  Plain function – should work with or without runIO/1
  test "inc/1 – plain execution" do
    assert IOPrograms.inc(4) == 5
  end

  test "inc/1 – through runIO/1 wrapper" do
    assert IOPrograms.runIO(IOPrograms.inc(4)) == 5
  end

  # 1.  One continuation
  test "twice_sum/2 – single <- chain" do
    # (3 + 7) = 10 → *2 = 20
    assert IOPrograms.runIO(IOPrograms.twice_sum(3, 7)) == 20
  end

  # 2.  Two continuations
  test "chain/1 – two-step continuation" do
    # x = 1
    # y = add(1, 3)       = 4
    # z = mul(4, 2)       = 8
    # result = y + z      = 12
    assert IOPrograms.runIO(IOPrograms.chain(1)) == 12
  end

  # 3.  Lifting a pure value
  test "lift42/0 – lift → continuation" do
    assert IOPrograms.runIO(IOPrograms.lift42()) == 84
  end

  # 4.  Re-binding a variable across continuations
  test "rebinding/1 – variable shadowing works" do
    #   n0 = 3
    #   n1 = n0 + 1        = 4
    #   n2 = n1 * 2        = 8
    assert IOPrograms.runIO(IOPrograms.rebinding(3)) == 8
  end

  # 5.  Ensure continuation helper functions are generated
  test "generated _cont_N helpers exist" do
    assert function_exported?(IOPrograms, :chain_cont_1, 2)
    assert function_exported?(IOPrograms, :chain_cont_2, 3)
  end
end
