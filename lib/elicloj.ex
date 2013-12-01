defmodule Elicloj do

  @moduledoc """
  very simple Clojure REPL connector -> Clojure and lein must be in PATH
  nRepl must be installed
  goals: start  a repl then use session on it
  session Record keep info of REPL, Session and socket and is needed on API call

 HOW TO DO 
  * start iex -S mix       start iex in dev mode  
  l Elixir.Elicloj       # load elicloj module  
  sess = Elicloj.start   # start server with repl

  the sess keep info on working socket. sess is needed when calling next api  

  API call  for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions
  (look at https://github.com/clojure/tools.nrepl/blob/master/doc/ops.md)
  {:ok,newsess,resp}=Elicloj.clone(sess)       # create new session on same repl/socket
  {:ok,sess,resp}=Elicloj.lssession(sess)      # get current session list
  {:ok,sess,resp}=Elicloj.describe(sess)       # get hash of repl  status 
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
   repl = Elicloj.Repl.new()
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
        {process,port} = start_repl()
        socket  = start_createsocket(host, port)
        repl = repl.update(process: process, host: host, port: port, socket: socket)
        {:ok,pid} = start_link(repl)
        sess.update(pid: pid, socket: socket)
   end

  #  start a  REPL external process ==> process
  defp start_repl() do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      # IO.puts("Start try start #{exe}")
      process = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["repl", ":headless"]}])
      receive do
         {process, {:data, datas}} ->
               # d should be nsess server started on port 55439 on host 127.0.0.1
                {:eol , resp} = datas
                # resp = iolist_to_binary(resp)
                [_ , p] = Regex.run(%r/port ([0-9]+)/, resp)
                {port , _ } = Integer.parse(p)
                {process,port}
        _ ->  raise "can't start REPL external process"
      end
  end

  #  start a new sess ==> socket
  def  start_createsocket(host, port) do
      # IO.puts("Start try :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary, {:packet, 0},{:active, false}]) do
               {:ok, socket}  ->  socket
                _ -> :failed
    end
  end

  def clone(sess),         do:  :gen_server.call(sess.pid(), {:clone ,sess})
  def lssession(sess),     do:  :gen_server.call(sess.pid(), {:lssession, sess})
  def describe(sess),      do:  :gen_server.call(sess.pid(), {:describe, sess})
  def exec(sess, clojcmd), do:  :gen_server.call(sess.pid(), {:cmd, sess, clojcmd})
  def close(sess),         do:  :gen_server.call(sess.pid(), {:close, sess})
  def interrupt(sess),     do:  :gen_server.call(sess.pid(), {:interrupt, sess})
  # def loadfile( filename, filepath, sess), do:  :gen_server.call(sess.pid, {:loadfile, sess , filename, filepath})


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
    # workaround for incomprehensible behaviour (idem on python nrepl)
    # if we go to fast we get a cached answer
    :timer.sleep(200)
    case :gen_tcp.recv(sock, 0, @receivetimeout ) do
      {:ok, nil}          -> {:failed, "RECV closed session nil"}
      {:ok, ""}           -> {:failed, "RECV closed session empty string"}
      {:ok, bin}          -> decoderesp(bin)
      {:error, :timeout}  -> {:failed ,"TIMEOUT"}
      {:error, :closed}   -> :ok = :gen_tcp.close(sock)
                             {:failed, "RECV closed session"}
      {:error, raison}   ->  {:failed, "RECV"<>raison}                     
    end
  end
  # send a cmd and wait answer
  def write_read_sock(sess,ecmd) do
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

  defp build_answer(sess,ecmd, repl) do
    case write_read_sock(sess, ecmd) do 
     {:ok, resp} -> {:reply, {:ok, sess, resp}, repl} 
     {_,raison}  -> {:reply, {:failed, raison , ""}, repl}
     _ -> {:reply,  {:failed, "unkown answser socket error?"}, repl}
    end
  end

  # SPAWN
  def start_link(repl) do
    :gen_server.start_link({:local,__MODULE__},__MODULE__,[repl],@srvdebug)
  end

  ### GEN SERVER PART###

  def init(repl) do
    {:ok , repl}
  end

  @doc """
     eval code for a specific repl/session
     """
  def handle_call({:cmd, sess, clojmd}, _from,  repl) do
     ecmd = if sess.session() == nil do
        Bencode.encode(HashDict.new([op: :eval, code: clojmd]))
     else
        Bencode.encode(HashDict.new([op: :eval, code: clojmd, session: sess.session()]))
     end         
     case Elicloj.write_read_sock(sess, ecmd) do 
     {:ok, resp} ->   
          if Dict.has_key?(resp,:"new-session")do
             session  = Dict.fetch!(resp, :"new-session")   
             sess =  sess.session(session)
          end 
            {:reply, {:ok, sess, resp }, repl} 
     {_,raison}  ->  {:reply, {:failed, raison}, repl}          
      _ ->  {:reply, {:failed, "cmd call failed no return"}, repl}         
     end
  end

  @doc """
     clone create new socket with new session
     """
  def handle_call({:clone, sess}, _from, repl) do
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
            {:reply, {:ok, sess , resp}, repl}
      _ ->  {:reply, {:failed, "no return"}, repl}  
     end
  end

  def handle_call({:loadfile, sess , filename, filepath}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :"load-file" , "file-name": filename, "file-path": filepath]))
     build_answer(sess, ecmd, repl)
  end

  def handle_call({:lssession, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :"ls-sessions"]))
     build_answer(sess, ecmd, repl)
  end

  def handle_call({:interrupt, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     build_answer(sess, ecmd, repl)
  end

  def handle_call({:describe, sess}, _from, repl) do
    ecmd = Bencode.encode(HashDict.new([op: :describe]))
    build_answer(sess, ecmd, repl)
  end

  def handle_call({:close, sess}, _from, repl) do
      # send stop to nsess
      if sess.session != nil do
        ecmd =  Bencode.encode(HashDict.new([op: :close, session: sess.session()]))
        case Elicloj.write_read_sock(sess, ecmd) do 
           {:ok, resp} -> sess = sess.session(nil)
                          {:reply, {:ok, sess, resp}, repl} 
           {_,raison}  -> {:reply, {:failed, raison }, repl}
           _ -> {:reply,  {:failed, "unkown answser .. socket error?"}, repl}
        end
      else
          {:reply,  {:failed, "can't close nil session"}, repl}
      end 
  end

  # def terminate(repl) do
  #     #  stop to nsess
  #     ecmd =  Bencode.encode(HashDict.new([op: :eval, code: "(exit)", session: sess.session()]))
  #     write_read_sock(repl.socket, ecmd)
  #     :ok = :gen_tcp.close(repl.socket)
  #     {:noreply, repl}
  # end

end