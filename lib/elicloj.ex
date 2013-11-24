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
  defrecord Repl, process: nil, pid: nil, host: "localhost", port: 7889, socket: nil, session: nil

  ##### API ######
  @doc """ 
           Start external nRELP through lein
           Connect socket
           return Record Repl
       """
  def start(host // "localhost" , port // 7889) do
      # run external here  
      exec = :os.find_executable(String.to_char_list!("lein"))
      process = :erlang.open_port({:spawn_executable , exec},[{:args, ["repl"]}])
      pid = "start_link()"
      {:ok, socket} = :gen_tcp.connect(:erlang.binary_to_list(host), port, [:binary, {:active, false}])
      repl = Repl.new()
      repl = repl.update(process: process, host: host, port: port, pid: pid, socket: socket)
      repl
  end

  @doc """
       send a cmd to REPL return  answer 
       """
  def stat(Repl[pid: pid] = repl) do
      IO.puts("Stat for #{pid}")
      :gen_server.call(repl.pid, :stat)
  end

  @doc """
       send a cmd to REPL return  answer 
       """
  def cmd(repl, cmd) do
      :gen_server.call(repl.pid(), {:cmd, cmd },{repl})
  end

  @doc """
      send a cmd to REPL return  answer 
       """
  def close(repl) do
      :gen_server.call(repl.pid, :close,  repl)
  end

  defp createCmd(cmd,repl) do
     Bencode.encode(HashDict.new([op: "eval", code: cmd, session: repl.session()]))
  end

  defp createCmdClone() do
     Bencode.encode(HashDict.new([op: "clone"]))
  end

  # defp do_recv(s, datas) ->
  #   case :gen_tcp.recv(sock, 0, @receivetimeout) do
  #     {:ok, bin} ->
  #       datas = checkendatas(sock, <<datas/binary, bin/binary>>),
  #       do_recv(Sock, datas)
  #     {error, timeout} -> do_recv(sock, datas)
  #     {error, reason} ->  exit(reason)
  #    end
  # end

  defp sockresp(socket) do
    case :gen_tcp.recv(socket, 0, @receivetimeout) do
      {:ok, res} -> Bencode.decode(res)
      {:error, :timeout} -> IO.puts("RECEIVE timeout")
                            res ="TIMEOUT"
      {:error, :closed}  -> :ok = :gen_tcp.close(socket) 
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
    res
  end 

  # SPAWN
  def start_link(repl) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[repl],[])
  end

  ### GEN SERVER PART###
  def init(repl) do
    # "op": "clone"  =>  "status" "done" , "newsession" newsession
    {:ok, sock} = :gen_tcp.connect(repl.host(),repl.port(),[:binary , {:packet , 0}])
    repl = repl.socket(sock)
    res = write_read_sock(repl, createCmdClone())
    IO.puts("answer is #{res}")
    {:ok , repl}
  end

  def handle_call({:cmd, cmd}, _from,  repl) do
      res = write_read_sock(repl, createCmd(cmd,repl))
      IO.puts("answer is #{res}")
      {:reply, res, repl }
  end

  def handle_info(:stat, repl) do
     res = write_read_sock(repl, createCmd("(println *clojure-version*)",repl))
     IO.puts("answer is #{res}")
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