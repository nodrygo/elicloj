defmodule Elicloj do

  @moduledoc """
  very simple Clojure sess connector -> Clojure and lein must be in PATH
  goals: start nsess  (with lein trampoline sess :headless) and execute commands
  """
    # :erlang.port_info(p)  -> :undefined when killed
	# :erlang.port_close(p)  ne kill pas le process .. ferme juste le port
	# :erlang.exit(p, :kill)
	# :erlang.port_command(p,String.to_char_list!("(quit)"))

  @receivetimeout  2000

  # use GenServer.Behaviour
  defrecord Repl, process: nil, host: '127.0.0.1', port: 59258, socket: nil

  ##### API ######
  @doc """
           Start external nRELP through lein
           Connect socket
           return Record sess
       """
  
  @doc """
       send the genserver
       gen server start first sess
       return sess Record  
       """
   def start( host // '127.0.0.1', port // 12345) do
        repl = Repl.new()
        IO.puts("Start the REPL")
        {process, port, socket} = start_createrepl()
        repl = repl.update(process: process, host: host, port: port, socket: socket)
       {:ok,_pid} = start_link(repl)
       IO.puts("Start try create session")
       sess  = session()
       IO.puts("Start sess is  #{sess}")
       sess
   end

  @doc """
       start a new sess ==> socket
       """
  def  start_createrepl() do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      IO.puts("Start try start #{exe}")
      process = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["sess", ":headless"]}])
      receive do
         {process, {:data, datas}} ->
               # d should be nsess server started on port 55439 on host 127.0.0.1
                {:eol , res} = datas
                # res = iolist_to_binary(res)
                IO.puts("nsess anwser is:  #{res}")
                [_ , p] = Regex.run(%r/port ([0-9]+)/, res)
                {port , _ } = Integer.parse(p)
      end
      IO.puts("Start try :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary,{:packet, :line},{:active, false}]) do
               {:ok, socket}  ->  {process, port, socket}        
                 _ -> raise "Error connecting on process #{exe} "
    end
  end

  def newsession(),         do:  :gen_server.call(__MODULE__, {:newsession ,sess})
  def session(),                do:   :gen_server.call(__MODULE__, {:ls-sessions})
  def status(sess),           do:   :gen_server.call(__MODULE__, {:stat, sess})
  def exe(clojcmd, sess), do:  :gen_server.call(__MODULE__, {:cmd, clojcmd, sess})
  def close(sess),             do:  :gen_server.call(__MODULE__, {:close, sess})
  def interrupt(sess),       do:  :gen_server.call(__MODULE__, {:interrupt,  sess})
  def loadfile( filename, filepath, sess), do:  :gen_server.call(__MODULE__, {:loadfile, sess , filename, filepath})


  defp sockresp(socket) do
    case :gen_tcp.recv(socket, 0, @receivetimeout) do
      {:ok, res}              -> {:ok, Bencode.decode(res)}
      {:error, :timeout}  -> {:fail ,"TIMEOUT"}
      {:error, :closed}    -> :ok = :gen_tcp.close(sess.socket)
                                        {:fail, "RECEIVE closed session"}
    end
  end

  defp write_read_sock(ecmd,socket) do
    case :gen_tcp.send(socket(), ecmd) do
     :ok -> res =  sockresp(socket())
      _  ->  raise "socket write cmd failed"
    end
    sockresp(sess)
  end

  # SPAWN
  def start_link(sess) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[sess],[])
  end

  ### GEN SERVER PART###
 # :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions

  def init(repl) do     
    {:ok , repl}
  end

  def handle_call({:cmd, clojmd, sess}, _from,  repl) do
      ecmd =  Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: sess.session()]))
      res = write_read_sock(repl.socket, ecmd)
      {:reply, {res, sess}, proclist }
  end

  def handle_call({:newsession, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :clone]))
     res = write_read_sock(repl.socket, ecmd)
     sess =  sess.update(session: res.session())
     {:reply, {:ok, res.session()}, repl}
  end

  def handle_call({:loadfile, sess , filename, filepath}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :load-file , file-name: filename, file-path: filepath]))
     res = write_read_sock(repl.socket, ecmd)
     sess =  sess.update(session: res.session())
     {:reply, {:ok, res}, repl}
  end

  def handle_call({:lssession, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op:  :ls-sessions]))
     res = write_read_sock(sess, ecmd,repl.socket)
     {:reply, {:ok, res}, repl }
  end

  def handle_call({:interrupt, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     res = write_read_sock(repl.socket, ecmd)
     {:reply, {:ok, res}, repl }
  end

  def handle_call({:stat, sess}, _from, repl) do
    ecmd = Bencode.encode(HashDict.new([op: "ls-sessions"]))
    res = write_read_sock(repl.socket, ecmd)
    {:reply, {:ok,  res}, repl}
  end

  def handle_call({:describe, sess}, _from, repl) do
    ecmd = Bencode.encode(HashDict.new([op: :describe]))
    res = write_read_sock(repl.socket, ecmd)
    {:reply, {:ok, res}, repl}
  end

  def handle_info({:close, sess}, repl) do
      # sed stop to nsess
      ecmd =  Bencode.encode(HashDict.new([op: :close, session: sess]))
      {:noreply, repl}
  end

  def terminate(repl) do
      #  stop to nsess
      res = write_read_sock(repl.socket,  ecmd)
      # try close socket
      :ok = :gen_tcp.close(repl.socket)
      # try kill process
      {:noreply, repl}
  end

end