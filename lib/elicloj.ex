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


  # use GenServer.Behaviour
  defrecord Repl, process: nil, pid: nil, host: "localhost", port: 5989, socket: nil, session: nil

  ##### API ######
  @doc """ Start external nRELP through lein
           Connect socket
           return Record Repl
       """

  def start( host // "localhost" , port // 59888,) do
      # start
      # run external here  
      exec = :os.find_executable(String.to_char_list!("lein"))
      process = :erlang.open_port({:spawn_executable , exec},[{:args, ["repl",]}])

      pid = "start_link()"
      {:ok, socket} = :gen_tcp.connect(:erlang.binary_to_list(host), 80, [:binary, {:active, false}])
      repl = Repl.new()
      repl = repl.update(process: process, host: host, port: port, pid: pid)
  end

  @doc """send a cmd to REPL return  answer """
  def stat(Repl[pid: pid] = repl) do
      IO.puts("Stat for #{pid}")
      :gen_server.call(pid, :stat)
  end

  @doc """send a cmd to REPL return  answer """
  def cmd(Repl[pid: pid, socket: sock] = repl, cmd) do
      :gen_server.call(pid, :cmd,  {sock, cmd}
  end

    @doc """send a cmd to REPL return  answer """
  def close((Relp[process: process, pid: pid]) do
      :gen_server.call(pid, :close,  {process,sock}
  end

  # SPAWN
  def start_link(repl) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[repl],[])

  ### GEN SERVER ###
  def init(repl) do
    # :erlang.send_after(1000,self(),:send_gossip)
    {:ok , repl }
    end
  end

  def handle_cast(:cmd, {sock, cmd}=params) do
      :ok = :gen_tcp.send(sock, encode(cmd))
      data = sockresp(socket, "")
      receive
         {ok ,datas} -> decode(datas)
      end
  end

  def handle_info(:stat) do
  end

  def handle_info(:close, {process,sock}=params) do
      # try close socket
      :ok = :gen_tcp.close(socket)
      # try kill process

  end

  defp sockresp(socket, bin) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, packet} -> sockresp(socket, [bin, packet])
      {:error, :closed} -> :ok = :gen_tcp.close(socket)
      bin
    end

end

