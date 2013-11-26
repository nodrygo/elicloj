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
  
  @doc """
       send the genserver
       gen server start first repl
       return repl Record  
       """
   def start_srv( host // '127.0.0.1', port // 12345) do
       IO.puts("Start the GenServer")
       {:ok,pid} = start_link()
       {:ok, socket} = start_newrepl()
       IO.puts("Start create session")
       {:reply, res, repl } = cmd(:new_session, repl)
       IO.puts("answer is #{res}")
       IO.puts("Start update repl ")
       repl = repl.update(process: process, host: host, port: port, pid: self(), socket: socket)
       IO.puts("Start new repl is  #{repl}")
       repl
   end

  @doc """
       start a new repl ==> socket
       """
  def  start_newrepl(repl) do
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
      {:ok, socket} ->  socket        
      _ -> raise "Error connecting on process #{exe} nrepl"
    end
  end

  def newsession(repl) do
      :gen_server.call(__MODULE__, {:newsession, repl})
  end
  def session(repl) do
      :gen_server.call(__MODULE__, {:newsession, repl})
  end
  def status(repl) do
      :gen_server.call(__MODULE__, {:stat, repl})
  end
  def exe(clojcmd, repl) do
       :gen_server.call(__MODULE__, {:cmd, clojcmd, repl})
  end

  defp sockresp(repl) do
    case :gen_tcp.recv(repl.socket, 0, @receivetimeout) do
      {:ok, res}              -> {:ok, Bencode.decode(res)}
      {:error, :timeout}  -> {:fail ,"TIMEOUT"}
      {:error, :closed}    -> :ok = :gen_tcp.close(repl.socket)
                                        {:fail, "RECEIVE closed session"}
                          
    end
  end

  defp write_read_sock(repl, ecmd) do
    case :gen_tcp.send(repl.socket(), ecmd) do
     :ok -> res =  sockresp(repl.socket())
      _  ->  raise "socket write cmd failed"
    end
    sockresp(repl)
  end

  # SPAWN
  def start_link(repl) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[repl],[])
  end

  ### GEN SERVER PART###
 # :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions

  def init() do     
    {:ok , []}
  end

  def handle_call({:cmd, clojmd, repl}, _from,  _stat) do
      ecmd =  Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: repl.session()]))
      res = write_read_sock(repl, ecmd)
      {:reply, {res, repl}, repl }
  end

  def handle_call({:newsession, repl}, _from, _stat) do
     ecmd = Bencode.encode(HashDict.new([op: :clone]))
     res = write_read_sock(repl, ecmd)
     repl =  repl.update(session: session)
     {:reply, {:ok, repl}, repl}
  end

  def handle_call({:lssession, repl}, _from, _repl) do
     ecmd = Bencode.encode(HashDict.new([op:  :ls-sessions]))
     res = write_read_sock(repl, ecmd)
     {:reply, {:ok, repl}, repl }
  end

  def handle_call({:interrupt, repl}, _from, _repl) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     res = write_read_sock(repl, ecmd)
     {:reply, {:ok, repl}, repl }
  end

  def handle_call({:stat, repl}, _from, _stat) do
    ecmd = Bencode.encode(HashDict.new([op: "ls-sessions"]))
    res = write_read_sock(repl, ecmd)
    {:reply, {:ok, repl}, repl }
  end

  def handle_info({:close,repl}, _stat) do
      # sed stop to nRepl
      ecmd =  Bencode.encode(HashDict.new([op: "eval", code: "(exit)", session: repl.session()]))
      res = write_read_sock(repl,  ecmd)
      # try close socket
      :ok = :gen_tcp.close(repl.socket)
      # try kill process
      {:noreply, repl}
  end

end