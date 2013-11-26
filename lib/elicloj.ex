defmodule Elicloj do

  @moduledoc """
  very simple Clojure sess connector -> Clojure and lein must be in PATH
  goals: start nsess  (with lein trampoline sess :headless) and execute commands
  USE CASE:
     sess = sess.start()
     sess.stat(sess)
     response = sess.cmd(sess, "(+ 5 3)")
  """
  # :erlang.port_info(p)  -> :undefined when killed
	# :erlang.port_close(p)  ne kill pas le process .. ferme juste le port
	# :erlang.exit(p, :kill)
	# :erlang.port_command(p,String.to_char_list!("(quit)"))
  @receivetimeout  2000

  # use GenServer.Behaviour
  defrecord Session, host: '127.0.0.1', port: 59258, socket: nil, session: nil

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
        IO.puts("Start the GenServer")
       proclist  = start_createrepl()
       {:ok,_pid} = start_link([proclist])
       IO.puts("Start create session")
       {:sessy,  sess } = newsession(:new_session, sess)
       IO.puts("answer is #{sess}")
       IO.puts("Start update sess ")
       sess = sess.update(process: process, host: host, port: port, pid: self(), socket: socket)
       IO.puts("Start new sess is  #{sess}")
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
      IO.puts("Start :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary,{:packet, :line},{:active, false}]) do
               {:ok, socket}  ->  {process, socket}        
                 _ -> raise "Error connecting on process #{exe} nsess"
    end
  end

  def newsession(sess),  do:  :gen_server.call(__MODULE__, {:newsession, sess})
  def session(sess),         do:   :gen_server.call(__MODULE__, {:ls-sessions, sess})
  def status(sess),           do:   :gen_server.call(__MODULE__, {:stat, sess})
  def exe(clojcmd, sess),  do:  :gen_server.call(__MODULE__, {:cmd, clojcmd, sess})

  defp sockresp(sess) do
    case :gen_tcp.recv(sess.socket, 0, @receivetimeout) do
      {:ok, res}              -> {:ok, Bencode.decode(res)}
      {:error, :timeout}  -> {:fail ,"TIMEOUT"}
      {:error, :closed}    -> :ok = :gen_tcp.close(sess.socket)
                                        {:fail, "RECEIVE closed session"}
    end
  end

  defp write_read_sock(sess, ecmd) do
    case :gen_tcp.send(sess.socket(), ecmd) do
     :ok -> res =  sockresp(sess.socket())
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

  def init(proclist) do     
    {:ok , proclist}
  end

  def handle_call({:newrepl,  sess}, _from,  proclist) do
      {:reply, {res, sess}, proclist}
  end

  def handle_call({:cmd, clojmd, sess}, _from,  proclist) do
      ecmd =  Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: sess.session()]))
      res = write_read_sock(sess, ecmd)
      {:reply, {res, sess}, proclist }
  end

  def handle_call({:newsession, sess}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op: :clone]))
     res = write_read_sock(sess, ecmd)
     sess =  sess.update(session: res.session())
     {:reply, {:ok, res.session()}, proclist}
  end

  def handle_call({:lssession, sess}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op:  :ls-sessions]))
     res = write_read_sock(sess, ecmd)
     {:reply, {:ok, res}, proclist }
  end

  def handle_call({:interrupt, sess}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     res = write_read_sock(sess, ecmd)
     {:reply, {:ok}, proclist }
  end

  def handle_call({:stat, sess}, _from, proclist) do
    ecmd = Bencode.encode(HashDict.new([op: "ls-sessions"]))
    res = write_read_sock(sess, ecmd)
    {:reply, {:ok}, proclist}
  end

  def handle_info({:close, sess}, proclist) do
      # sed stop to nsess
      ecmd =  Bencode.encode(HashDict.new([op: "eval", code: "(exit)", session: sess.session()]))
      res = write_read_sock(sess,  ecmd)
      # try close socket
      :ok = :gen_tcp.close(sess.socket)
      # try kill process
      {:noreply, proclist}
  end

  def terminate(proclist) do
      # sed stop to nsess
      # for each open socket in proclist ... close
      {:noreply, proclist}
  end

end