defmodule Elicloj do

  @moduledoc """
  very simple Clojure REPL connector -> Clojure and lein must be in PATH
  nRepl must be installed
  goals: start  a repl then use session on it
  session Record keep info of REPL, Session and socket and is needed on API call

  API call  for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions
  (look at https://github.com/clojure/tools.nrepl/blob/master/doc/ops.md)
  Elicloj.start()             create new repl
  Elicloj.clone(sess)         create new session on same repl
  Elicloj.session(sess)       get current session list
  Elicloj.describe(sess)
  Elicloj.exec(clojcmd, sess) eval cloje command (in a string)
  Elicloj.close(sess)         close current session
  Elicloj.interrupt(sess)     interrupt current eval
  """

  @receivetimeout  2000
  # @srvdebug []
  @srvdebug [debug: [:trace]]

  use GenServer.Behaviour

  defrecord Repl, process: nil, host: '127.0.0.1', port: 59258, socket: nil
  defrecord Sess, pid: nil, socket: nil, session: nil

  ##### API ######
  @doc """
       create new REPL
       return a sess handle
       """
   def start( host // '127.0.0.1') do
        repl = Repl.new()
        sess = Sess.new()
        IO.puts("Start the REPL")
        {process,port} = start_createrepl()
        socket  = start_createsocket(host, port)
        repl = repl.update(process: process, host: host, port: port, socket: socket)
        {:ok,pid} = start_link(repl)
        sess = sess.update(pid: pid, socket: socket)
        IO.puts("Start try create session")
        currentsession  = session(sess)
        IO.puts("Start currentsess #{currentsession}")
        sess = sess.update(session: currentsession)
        IO.puts("Start sess with sess=#{sess}")
        sess
   end

  @doc """
       start a new REPL external process ==> process
       """
  def  start_createrepl() do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      IO.puts("Start try start #{exe}")
      process = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["repl", ":headless"]}])
      receive do
         {process, {:data, datas}} ->
               # d should be nsess server started on port 55439 on host 127.0.0.1
                {:eol , res} = datas
                # res = iolist_to_binary(res)
                IO.puts("nsess anwser is:  #{res}")
                [_ , p] = Regex.run(%r/port ([0-9]+)/, res)
                {port , _ } = Integer.parse(p)
                {process,port}
        _ ->  raise "can't start REPL externale process"
      end
  end
  @doc """
       start a new sess ==> socket
       """
  def  start_createsocket(host, port) do
      IO.puts("Start try :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary,{:packet, :line},{:active, false}]) do
               {:ok, socket}  ->  socket
                _ -> :failed
    end
  end

  def clone(sess),         do:  :gen_server.call(sess.pid, {:clone ,sess})
  def session(sess),       do:  :gen_server.call(sess.pid, {:lssessions})
  def describe(sess),      do:  :gen_server.call(sess.pid, {:describe, sess})
  def exec(clojcmd, sess), do:  :gen_server.call(sess.pid, {:cmd, clojcmd, sess})
  def close(sess),         do:  :gen_server.call(sess.pid, {:close, sess})
  def interrupt(sess),     do:  :gen_server.call(sess.pid, {:interrupt,  sess})
  # def loadfile( filename, filepath, sess), do:  :gen_server.call(sess.pid, {:loadfile, sess , filename, filepath})


  # wait socket answer and Bencode.decode it
  defp sockresp(sess) do
    case :gen_tcp.recv(sess.socket, 0, @receivetimeout) do
      {:ok, res}          -> {:ok, Bencode.decode(res)}
      {:error, :timeout}  -> {:failed ,"TIMEOUT"}
      {:error, :closed}   -> :ok = :gen_tcp.close(sess.socket)
                             {:failed, "RECEIVE closed session"}
    end
  end

  # send a Bencode request on a REPL socket
  # wait answer and decode it
  defp write_read_sock(sess,ecmd) do
    case :gen_tcp.send(sess.socket(), ecmd) do
     :ok -> res = sockresp(sess.socket())
      _  ->  raise "socket write cmd failed"
    end
    sockresp(res)
  end

  # SPAWN
  def start_link(sess) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[sess],@srvdebug)
  end

  ### GEN SERVER PART###

  def init(repl) do
    {:ok , repl}
  end

  @doc """
     eval code for a specific repl/session
     """
  def handle_call({:cmd, clojmd, sess}, _from,  repl) do
      ecmd =  Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: sess.session()]))
      res = write_read_sock(repl.socket, ecmd)
      {:reply, {:ok, res}, repl}
  end

  @doc """
     clone create new socket with new session
     """
  def handle_call({:clone, sess}, _from, repl) do
     if sess.session() == nil do
         ecmd = Bencode.encode(HashDict.new([op: :clone]))
     else
         ecmd = Bencode.encode(HashDict.new([op: :clone , session: sess.session()]))
     end
     res = write_read_sock(repl.socket, ecmd)
     sess =  sess.update(session: res.session())
     {:reply, {:ok, sess}, repl}
  end

  # def handle_call(pid, {:loadfile, sess , filename, filepath}, _from, repl) do
  #    ecmd = Bencode.encode(HashDict.new([op: :load-file , file-name: filename, file-path: filepath]))
  #    res = write_read_sock(repl.socket, ecmd)
  #    sess =  sess.update(session: res.session())
  #    {:reply, {:ok, res}, repl}
  # end

  def handle_call({:lssession, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op:  :'ls-sessions']))
     IO.puts("send ls-session #{ecm} to socket")
     res = write_read_sock(sess, ecmd)
     IO.puts("get socket resp #{res}" )     
     {:reply, {:ok, res}, repl }
  end

  def handle_call({:interrupt, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     res = write_read_sock(sess, ecmd)
     {:reply, {:ok, res}, repl }
  end

  def handle_call({:describe, sess}, _from, repl) do
    ecmd = Bencode.encode(HashDict.new([op: :describe]))
    res = write_read_sock(sess, ecmd)
    {:reply, {:ok, res}, repl}
  end

  def handle_info({:close, sess}, repl) do
      # send stop to nsess
      ecmd =  Bencode.encode(HashDict.new([op: :close, session: sess.session()]))
      write_read_sock(sess, ecmd)
      # need to close socket here and putoff
      :ok = :gen_tcp.close(sess.socket)
      {:noreply, repl}
  end

  def terminate(repl) do
      #  stop to nsess
      # res = write_read_sock(repl.sess,  ecmd)
      # try close socket
      # :ok = :gen_tcp.close(repl.socket)
      # try kill process
      {:noreply, repl}
  end

end