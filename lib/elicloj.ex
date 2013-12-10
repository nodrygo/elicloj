defmodule Elicloj do

  @moduledoc """
  very simple Clojure proclist connector -> Clojure and lein must be in PATH
  nproclist must be installed
  goals: start  a proclist then use session on it
  session Record keep info of proclist, Session and socket and is needed on API call

  not sure there is a real need for intermediate genserver .. direct call as single client should be enought
  limit one socket per proclist because seem better


 HOW TO DO
  * start iex -S mix       start iex in dev mode
  l Elixir.Elicloj       # load elicloj module
  sess = Elicloj.start   # start server with proclist

  the sess keep info on working socket. sess is needed when calling next api

  API call  for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions
  (look at https://github.com/clojure/tools.nproclist/blob/master/doc/ops.md)
  {:ok,newsess,resp}=Elicloj.clone(sess)       # create new session on same proclist/socket
  {:ok,sess,resp}=Elicloj.lssession(sess)      # get current session list
  {:ok,sess,resp}=Elicloj.describe(sess)       # get hash of proclist  status
  {:ok,sess,resp}=Elicloj.exec(sess ,"(+ 1 2)") # eval clojure command (cmd is in a string)
  {:ok,sess,resp}=Elicloj.close(sess)         # close current session
  {:ok,sess,resp}=Elicloj.interrupt(sess)     # interrupt current eval

 HOW TO DO manual test
 start ise -S mix
 l Elixir.Elicloj
 sess = Elicloj.start
 ... cmd exemple ...
 ecmd = Bencode.encode(HashDict.new([op: "clone"]))
 ecmd = Bencode.encode(HashDict.new([op:  :'ls-sessions']))
 ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(+ 3 5)"]))
 ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(+ 3 5)", session: sess.session()]))
 ... direct call to socket ....
{:ok,resp} = Elicloj.write_read_sock(sess,ecmd)

   INTERNAL SOCKET and others TESTS
   proclist = Elicloj.proclist.new()
  host='127.0.0.1';port= 42696.....
  {:ok,sock} = :gen_tcp.connect(host, port, [:binary, {:packet, 2},{:active, false}])
  sock=sess.socket()
  :gen_tcp.send(sock, ecmd)
  :gen_tcp.recv(sock, 0, 1000)

  Elicloj.start_createsocket('127.0.0.1', sess.port())
  """

  @receivetimeout  2000
  @srvdebug []
  # @srvdebug [debug: [:trace]]

  use GenServer.Behaviour

  defrecord Procid, extprocid: nil, port: nil, socket: nil
  defrecord Sess, pid: nil, socket: nil, session: nil


  ###################################
  # Process handle
  ###################################
  @doc """
       create new proclist on localhost, start gen server
       return a sess handle
       """
   def start() do
        sess = Sess.new()
        {proclist,sess} = newpREPL([],sess)
        {:ok, pid}  = start_link(proclist)
        sess.update(pid: pid)
   end

   defp newpREPL(proclist,sess) do
        proc = Procid.new()
        {extprocid,port} = start_proclist()
        socket     = start_createsocket('127.0.0.1', port)
        proc       = proc.update(extprocid: extprocid, port: port, socket: socket)
        {[proc|proclist], sess.update(socket: socket)}
   end

  #  start a  proclist external extprocid ==> extprocid
  defp start_proclist() do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      # IO.puts("Start try start #{exe}")
      extprocid = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["repl", ":headless"]}])
      receive do
         {extprocid, {:data, datas}} ->
               # d should be nsess server started on port 55439 on host 127.0.0.1
                {:eol , resp} = datas
                # resp = iolist_to_binary(resp)
                [_ , p] = Regex.run(%r/port ([0-9]+)/, resp)
                {port , _ } = Integer.parse(p)
                {extprocid,port}
        _ ->  raise "can't start proclist external extprocid"
      end
  end

  #  start a new sess ==> socket
  defp  start_createsocket(host, port) do
      # IO.puts("Start try :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary, {:packet, 0},{:active, false}]) do
               {:ok, socket}  ->  socket
                _ -> :failed
    end
  end


  ###################################
  # API part
  ###################################
  @doc " clone create new session clone => {:ok, newsess, resp } or {:failed, raison , other}"
  def clone(sess),         do:  :gen_server.call(sess.pid(), {:clone ,sess})
  @doc "lssession return session list in resp dic => {:ok,sess,resp} or {:failed...}"
  def lssession(sess),     do:  :gen_server.call(sess.pid(), {:lssession, sess})
  @doc "describe return REPL description in resp Dic => {:ok,sess,resp} or {:failed...}"
  def describe(sess),      do:  :gen_server.call(sess.pid(), {:describe, sess})
  @doc "run repl command value in resp Dic => {:ok,sess,resp} or {:failed...}"
  def exec(sess, clojcmd), do:  :gen_server.call(sess.pid(), {:cmd, sess, clojcmd})
  @doc "close the session => {:ok,sess,resp} or {:failed...}"
  def close(sess),         do:  :gen_server.call(sess.pid(), {:close, sess})
  @doc "interrupt running command in a session => {:ok,sess,resp} or {:failed...}"
  def interrupt(sess),     do:  :gen_server.call(sess.pid(), {:interrupt, sess})
  @doc "kill session REPL  => {:ok,sess,resp} or {:failed...}"
  def kill(sess),          do:  :gen_server.call(sess.pid(), {:quit, sess})
  @doc "newproclist create a new REPL and session  => {:ok,sess,resp} or {:failed...}"
  def newproclist(sess),   do:  :gen_server.call(sess.pid(), {:newrepl, sess})  # create new proclist
  # def loadfile( filename, filepath, sess), do:  :gen_server.call(sess.pid, {:loadfile, sess , filename, filepath})
  # def exec!(sess,clojcmd) do:      # return direct result of eval or raise an error
  #     case exec(sess, clojcmd) do
  #         {:ok, resp} ->
  #         _ -> raise "Command exec failed"
  #     end
  # end

  ###################################
  # HANDLE SOCKET COM & PRIVATE FUNCTIONS
  ###################################

  # decode response and read status
  defp decoderesp(bin) do
    IO.puts("decoderesp bin #{bin} ")
    if is_bitstring(bin) do
      decoderesp1(bin)
    else
      {:failed, "decode nil content"}
    end
  end

  defp decoderesp1(bin)  do
    resp = Bencode.decode(bin)
    case is_list(resp) do
      true -> [resp|_]=:lists.reverse(resp);resp
       _ -> resp
    end
    if Dict.has_key?(resp,:status) do
      case Dict.fetch!(resp, :status)|> Enum.filter &(&1 == "done")  do
        ["done"]  -> {:ok, resp}
        _-> {:failed, "decode fail with status #{Dict.fetch!(resp, :status)}" }
      end
    else
      {:ok, resp}
    end
  end

  # wait socket answer and Bencode.decode it
  defp sockresp(sock) do
    # workaround for incomprehensible behaviour (idem on python nproclist)
    # if we go to fast we got a cached answer
    :timer.sleep(200)
    case :gen_tcp.recv(sock, 0, @receivetimeout ) do
      {:ok, bin}          -> decoderesp(bin)
      {:error, :timeout}  -> {:failed ,"TIMEOUT"}
      {:error, :closed}   -> :ok = :gen_tcp.close(sock)
                             {:failed, "RECV closed session"}
      {:error, raison}   ->  {:failed, "RECV"<>raison}
    end
  end
  # send a cmd and wait answer
  defp write_read_sock(sess,ecmd) do
    # IO.puts "try send cmd is #{ecmd}"
    try do
     resp = case :gen_tcp.send(sess.socket(), ecmd) do
         :ok -> case sockresp(sess.socket()) do
                  {:ok,  bin}   -> {:ok,  bin}
                  {retcode, raison} -> {:failed,"ERROR socket read #{retcode} with raison #{raison}"}
                end
          _  ->  {:failed, "socket write cmd failed"}
            end
    catch
         message ->  {:failed,"ERROR socket exception with msg #{message}"}
    end
  end

  # build generic anwser for simple call
  defp build_answer(sess,ecmd, proclist) do
    case write_read_sock(sess, ecmd) do
     {:ok, resp} -> {:reply, {:ok, sess, resp}, proclist}
     {_,raison}  -> {:reply, {:failed, raison , ""}, proclist}
     _ -> {:reply,  {:failed, "unkown answser socket error?"}, proclist}
    end
  end

  # stop repl and kill process
  defp killproc(proc) do
    # send QUIT
    ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(quit)"]))
    sess=Sess.new()
    write_read_sock(sess.socket(proc.socket()), ecmd)
    # kill launcher extprocid
    {:os_pid, p} = :erlang.port_info(proc.extprocid(),:os_pid)
    :os.cmd(String.to_char_list! "kill #{p}")
  end

  ###################################
  # SPAWN GEN SERVER
  ###################################
  def start_link(proclist) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[proclist],@srvdebug)
  end

  ###################################
  ######### GEN SERVER PART #########
  ###################################
  def init(proclist) do
    {:ok , proclist}
  end

  # eval code for a specific proclist/session
  def handle_call({:cmd, sess, clojmd}, _from,  proclist) do
     ecmd = if sess.session() == nil do
        Bencode.encode(HashDict.new([op: :eval, code: clojmd]))
     else
        Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: sess.session()]))
     end
     case write_read_sock(sess, ecmd) do
     {:ok, resp} ->
          if Dict.has_key?(resp,:"new-session")do
             session  = Dict.fetch!(resp, :"new-session")
             sess =  sess.session(session)
          end
            {:reply, {:ok, sess, resp }, proclist}
     {_,raison}  ->  {:reply, {:failed, raison}, proclist}
      _ ->  {:reply, {:failed, "cmd call failed no return"}, proclist}
     end
  end

  # clone create new socket with new session
  def handle_call({:clone, sess}, _from, proclist) do
     ecmd = if sess.session() == nil do
         Bencode.encode(HashDict.new([op: :clone]))
     else
         Bencode.encode(HashDict.new([op: :clone , session: sess.session()]))
     end
     case write_read_sock(sess, ecmd) do
     {:ok, resp} ->
            if Dict.has_key?(resp,:"new-session")do
                session  = Dict.fetch!(resp, :"new-session")
            else
                session  = Dict.fetch!(resp, :session)
            end
            sess =  sess.session(session)
            {:reply, {:ok, sess , resp}, proclist}
      _ ->  {:reply, {:failed, "no return"}, proclist}
     end
  end

  def handle_call({:loadfile, sess , filename, filepath}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op: :"load-file" , "file-name": filename, "file-path": filepath]))
     build_answer(sess, ecmd, proclist)
  end

  def handle_call({:lssession, sess}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op: :"ls-sessions"]))
     build_answer(sess, ecmd, proclist)
  end

  def handle_call({:interrupt, sess}, _from, proclist) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     build_answer(sess, ecmd, proclist)
  end

  def handle_call({:describe, sess}, _from, proclist) do
    ecmd = Bencode.encode(HashDict.new([op: :describe]))
    build_answer(sess, ecmd, proclist)
  end

  def handle_call({:close, sess}, _from, proclist) do
      # send stop to nsess
      if sess.session != nil do
        ecmd =  Bencode.encode(HashDict.new([op: :close, session: sess.session()]))
        case write_read_sock(sess, ecmd) do
           {:ok, resp} -> sess = sess.session(nil)
                          {:reply, {:ok, sess, resp}, proclist}
           {_,raison}  -> {:reply, {:failed, raison }, proclist}
           _ -> {:reply,  {:failed, "unkown answser .. socket error?"}, proclist}
        end
      else
          {:reply,  {:failed, "can't close nil session"}, proclist}
      end
  end

  # create new proclist
  def handle_call({:newrepl, sess}, _from, proclist) do
    {newproclist, newsess} = newpREPL(proclist,sess)
    {:reply, {:ok, newsess}, newproclist}
  end

  # send close to terminate proclist
  def handle_call({:kill, sess}, _from, proclist) do
    ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(quit)"]))
    write_read_sock(sess, ecmd)
    build_answer(sess, ecmd, proclist)
  end

  # send close to terminate proclist
  def handle_info(_cmd, _proclist) do
      {:ok, "Command not implemented" }
  end

  def terminate(_raison, proclist) do
    proclist |> Enum.each &(killproc(&1))
    {:reply, "gen server terminated"}
  end

end