defmodule Eclicloj.Demo do
@doc """
  Ckeck simple Elicloj call
  run as   Elicloj.Demo.simpledemo()
"""
@clojcmd """
(let [after (int (rand 5000))]
  (Thread/sleep after)
    (str  " clojure return after " after " ms"))
"""
    def simpledemo() do
        # start new repl server
        sess = Elicloj.start()
        {:ok,newsess,resp}=Elicloj.clone(sess)
        IO.puts("create clone in newsession #{inspect resp}") 

        {:ok,sess,resp}=Elicloj.lssession(sess) 
        IO.puts("show list of sesion #{inspect resp}") 

        {:ok,sess,resp}=Elicloj.describe(sess) 
        IO.puts("describe repl status #{inspect resp}")

        {:ok,sess,resp}=Elicloj.exec(sess ,"(+ 1 2)") 
        IO.puts("code exec in sess (see value key in dict) #{inspect resp}")

        {:ok,sess,resp}=Elicloj.exec(newsess ,"(+ 2.0 200)") 
        IO.puts("code exec in newsess (see value key in dict) #{inspect resp}") 

        {:ok,sess,resp}=Elicloj.close(newsess)
        IO.puts("close the newsess #{inspect resp}")  

        {:ok,sess,resp}=Elicloj.interrupt(sess) 
        IO.puts("answer is #{inspect  resp}")
    end
  end

@doc """
  Ckeck async execution of clojure on 2 differents sessions
  in repl each session run in it's own thread
  run as   Elicloj.Demo.Asyncdemo.asyncdemo()
"""
######  WARNING CAN'T WORK ... NO MULTIPLE REPL YET
######  WARNING CAN'T WORK ... NO MULTIPLE REPL YET
######  WARNING CAN'T WORK ... NO MULTIPLE REPL YET
######  WARNING CAN'T WORK ... NO MULTIPLE REPL YET

  defmodule Asyncdemo do
    @doc """
    run the async demo
    start 2 repl whith 2 session on each
    process and execute same clojure cmd on it
    """
    def srvrunner() do
        receive do
           {:runncmdrepl, repl, p } ->  runcmd(repl , p)
        end
    end

    def asyncdemo() do
        # start 2 repl server
        repl1sess1 = Elicloj.start()
        repl2sess1 = Elicloj.start()
        # start other session in each repl
        repl1sess2 = Elicloj.session(repl1sess1)
        repl2sess2 = Elicloj.session(repl2sess1)

        # spawn one process per repl/sess
        [repl1sess1,repl1sess2,repl2sess1,repl2sess2]
        |> Enum.map(fn(x) -> p = spawn(__MODULE__,srvrunner,[]);{p,x} end)
        |> Enum.map(fn ({p,r}) -> p <- {:runncmdrepl, r, p} end)
    end



    def runcmd(repl,p) do
        res = Elicloj.exec(repl,Eclicloj.Demo.cljcode())
        IO.puts("answer from process pid #{p} is #{res}")
    end
  end
end


