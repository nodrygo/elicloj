defmodule Elicloj do

  @moduledoc """
  very simple Clojure REPL connector -> Clojure and lein must be in PATH
  goals: start nREPL  (with lein trampoline repl :headless) and execute commands
  USE CASE:
     repl = Repl.start()
     Repl.stat(repl)
     response = Repl.cmd(repl, "(+ 5 3)")
  """
  # :erlang.port_info(p)  -> :undefined when killed
	# :erlang.port_close(p)  ne kill pas le process .. ferme juste le port
	# :erlang.exit(p, :kill)
	# :erlang.port_command(p,String.to_char_list!("(quit)"))
  @receivetimeout  2000

  # use GenServer.Behaviour
  defrecord Repl, process: nil, pid: nil, host: '127.0.0.1', port: 59258, socket: nil, session: nil

  ##### API ######
  @doc """
           Start external nRELP through lein
           Connect socket
           return Record Repl
       """
  def start( host // '127.0.0.1', port // 12345) do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      IO.puts("Start try start #{exe}")
      process = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["repl", ":headless"]}])
      receive do
         {process, {:data, datas}} ->
               # d should be nREPL server started on port 55439 on host 127.0.0.1
                {:eol , res} = datas
                # res = iolist_to_binary(res)
                IO.puts("nRepl anwser is:  #{res}")
                [_ , p] = Regex.run(%r/port ([0-9]+)/, res)
                {port , _ } = Integer.parse(p)
      end
      IO.puts("Start :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary,{:packet, :line},{:active, false}]) do
      {:ok, socket} ->
          repl = Repl.new()
          IO.puts("Start GenServer")
          {:ok,_} = start_link(repl)
          IO.puts("Start create repl ")
          repl = repl.update(process: process, host: host, port: port, pid: self(), socket: socket)
          IO.puts("Start repl #{repl}")
          repl
      _ -> raise "Error connecting on process #{exe} nrepl"
    end
  end

  @doc """
       send a cmd to REPL return  answer
       """
  def cmd(:stat, repl) do
      :gen_server.call(repl.pid(), {:stat, cmd },{repl})
  end

  def cmd(:newsession, repl) do

      :gen_server.call(repl.pid(), {:newsession},{repl})
       Bencode.decode(sockresp(repl))
  end

  def cmd(:cmd, repl, cmd) do
       :gen_server.call(repl.pid(), {:cmd, cmd },{repl})
  end

  def cmd(:close, repl, cmd) do
      :gen_server.call(repl.pid(), {:close},{repl})
  end

  defp sockresp(repl) do
    case :gen_tcp.recv(repl.socket, 0, @receivetimeout) do
      {:ok, res} -> Bencode.decode(res)
      {:error, :timeout} -> IO.puts("RECEIVE timeout")
                            res ="TIMEOUT"
      {:error, :closed}  -> :ok = :gen_tcp.close(repl.socket)
                           IO.puts("RECEIVE timeout")
                           res = "KO"
    end
    IO.puts("RECEIVE res #{res}")
    res
  end

  defp write_read_sock(repl,dic) do
    case :gen_tcp.send(repl.socket(), dic) do
     :ok -> res =  sockresp(repl.socket())
      _  -> raise "socket cmd failed"
    end
    IO.puts("write_read_sock res #{res}")
    res = Bencode.decode(sockresp(repl))
    IO.puts("ecoded answer is #{res}")
  end

  # SPAWN
  def start_link(repl) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[repl],[])
  end

  ### GEN SERVER PART###
 # :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions

  def init(repl) do
     ecmd = Bencode.encode(HashDict.new([op: "clone"]))
     res = write_read_sock(repl, ecmd, repl)
    IO.puts("answer is #{res}")
    {:ok , repl}
  end

  def handle_call({:cmd, cmd}, _from,  repl) do
      ecmd =  Bencode.encode(HashDict.new([op: "eval", code: cmd, session: repl.session()]))
      res = write_read_sock(repl, ecmd)
      {:reply, res, repl }
  end

  def handle_info(:newsession, repl) do
     ecmd = Bencode.encode(HashDict.new([op: "clone"]))
     res = write_read_sock(repl, ecmd, repl)
     {:reply, res, repl }
  end

  def handle_info(:interrupt, repl) do
     ecmd = Bencode.encode(HashDict.new([op: "interrupt"]))
     res = write_read_sock(repl, ecmd, repl)
     {:reply, res, repl }
  end

  def handle_info(:stat, repl) do
    ecmd = Bencode.encode(HashDict.new([op: "ls-sessions"]))
    res = write_read_sock(repl, ecmd, repl)
    {:reply, res, repl }
  end

  def handle_info(:close, repl) do
      # sed stop to nRepl
      res = write_read_sock(repl,  createCmd("(exit)",repl))
      # try close socket
      :ok = :gen_tcp.close(repl.socket)
      # try kill process
      {:reply, res, repl }
  end

end