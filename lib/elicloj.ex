defmodule Elicloj do

  @moduledoc """
  very simple Clojure REPL connector -> Clojure and lein must be in PATH
  nRepl must be installed
  goals: start  a repl then use session on it
  session Record keep info of REPL, Session and socket and is needed on API call

   l Elixir.Elicloj 
  sess = Elicloj.start
  API call  for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions
  (look at https://github.com/clojure/tools.nrepl/blob/master/doc/ops.md)
  {:ok,sess}=Elicloj.start()             create new repl
  {:ok,sess1}=Elicloj.clone(sess)         create new session on same repl
  {:ok,resp}=Elicloj.lssession(sess)       get current session list
  {:ok,resp}=Elicloj.describe(sess)
  {:ok,sess,value}=Elicloj.exec(sess ,"(+ 1 2)") eval clojure command (in a string)
  Elicloj.close(sess)         close current session
  sess=Elicloj.interrupt(sess)     interrupt current eval

 HOW TO DO manual test 
 start ise -S mix
 l Elixir.Elicloj 
 sess = Elicloj.start
 Elicloj.exec("(+ 5 3)", sess)
 ecmd = Bencode.encode(HashDict.new([op: "clone"])) 
 ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(+ 3 5)"])) 
 ecmd = Bencode.encode(HashDict.new([op: :eval, code: "(+ 3 5)", session: sess.session()]))

{:ok,res} = Elicloj.write_read_sock(sess,ecmd)

   INTERNAL SOCKET TESTS
  host='127.0.0.1';port= 42696.....
  {:ok,sock} = :gen_tcp.connect(host, port, [:binary, {:packet, 2},{:active, false}])
  sock=sess.socket()
  :gen_tcp.send(sock, ecmd)
  :gen_tcp.recv(sock, 0)

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
        {process,port} = start_createrepl()
        socket  = start_createsocket(host, port)
        repl = repl.update(process: process, host: host, port: port, socket: socket)
        {:ok,pid} = start_link(repl)
        sess.update(pid: pid, socket: socket)
   end



  @doc """
       start a new REPL external process ==> process
       """
  def  start_createrepl() do
      # run external here
      exe = :os.find_executable(String.to_char_list!("lein"))
      # IO.puts("Start try start #{exe}")
      process = :erlang.open_port({:spawn_executable, exe},[:binary,{:line, 255}, {:args, ["repl", ":headless"]}])
      receive do
         {process, {:data, datas}} ->
               # d should be nsess server started on port 55439 on host 127.0.0.1
                {:eol , res} = datas
                # res = iolist_to_binary(res)
                [_ , p] = Regex.run(%r/port ([0-9]+)/, res)
                {port , _ } = Integer.parse(p)
                {process,port}
        _ ->  raise "can't start REPL external process"
      end
  end
  @doc """
       start a new sess ==> socket
       """
  def  start_createsocket(host, port) do
      IO.puts("Start try :gen_tcp.connect on port #{port}")
      case :gen_tcp.connect(host, port, [:binary, {:packet, 0},{:active, false}]) do
               {:ok, socket}  ->  socket
                _ -> :failed
    end
  end

  def clone(sess),         do:  :gen_server.call(sess.pid(), {:clone ,sess})
  def lssession(sess),     do:  :gen_server.call(sess.pid(), {:lssessions})
  def describe(sess),      do:  :gen_server.call(sess.pid(), {:describe, sess})
  def exec(sess, clojcmd), do:  :gen_server.call(sess.pid(), {:cmd, sess, clojcmd})
  def close(sess),         do:  :gen_server.call(sess.pid(), {:close, sess})
  def interrupt(sess),     do:  :gen_server.call(sess.pid(), {:interrupt,  sess})
  # def loadfile( filename, filepath, sess), do:  :gen_server.call(sess.pid, {:loadfile, sess , filename, filepath})

@doc """
   decode response and read status
"""

  def decoderesp(bin) do
    if is_bitstring(bin) do 
      decoderesp1(bin)
    else
      {:failed, "decode nil content"}
    end
  end  

  def decoderesp1(bin)  do 
    IO.puts("DECODE RESP IS #{bin}")
    res = Bencode.decode(bin)
    if Dict.has_key?(res,:status)do  
      case Dict.fetch!(res, :status)|> Enum.filter &(&1 == "done")  do
        ["done"]  -> {:ok, res}
        _-> {:failed, "decode fail with status #{Dict.fetch!(res, :status)}" }
      end
    else 
      {:ok, res}
    end
  end


  # wait socket answer and Bencode.decode it
  def sockresp(sock) do
    IO.puts "try listen"
    case :gen_tcp.recv(sock, 0, @receivetimeout ) do
      {:ok, bin}          -> decoderesp(bin)
      {:error, :timeout}  -> {:failed ,"TIMEOUT"}
      {:error, :closed}   -> :ok = :gen_tcp.close(sock)
                             {:failed, "RECV closed session"}
      {:error, raison}   ->  {:failed, "RECV"<>raison}                     
    end
  end

  def write_read_sock(sess,ecmd) do
    IO.puts "try send cmd is #{ecmd}"
    case :gen_tcp.send(sess.socket(), ecmd) do
     :ok -> case sockresp(sess.socket()) do   
              {:ok,  bin}   -> {:ok,  bin} 
              {retcode, raison} -> {:failed,"ERROR socket read #{retcode} with raison #{raison}"}
                end
      _  ->  raise "socket write cmd failed"
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
     {:ok, res} ->   
          if Dict.has_key?(res,:"new-session")do
            session  = Dict.fetch!(res, :"new-session")   
            sess =  sess.session(session)
          end  
          if Dict.has_key?(res,:value)do
            value = Dict.fetch!(res, :value)
            {:reply, {:ok, sess , value}, repl}
          else  
            {:reply, {:failed, "value not found", res}, repl} 
          end 
      _ ->  {:reply, {:failed, "cmd call failed", "no return"}, repl}         
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
     {:ok, res} ->
            if Dict.has_key?(res,:"new-session")do
                session  = Dict.fetch!(res, :"new-session")  
            else
                session  = Dict.fetch!(res, :session)  
            end      
            sess =  sess.session(session) 
            {:reply, {:ok, sess}, repl}
      _ ->  {:reply, {:failed, "no return"}, repl}  
     end
  end

  def handle_call({:loadfile, sess , filename, filepath}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :"load-file" , "file-name": filename, "file-path": filepath]))
     case write_read_sock(sess, ecmd) do 
     {:ok, res}  ->  {:reply, {:ok, res}, repl}
      {_,raison} ->  {:reply, {:failed, raison}, repl}   
     end
  end

  def handle_call({:lssession, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op:  :'ls-sessions']))
     case write_read_sock(sess, ecmd) do 
     {:ok, res}  ->  {:reply, {:ok, res}, repl}
      {_,raison} ->  {:reply, {:failed, raison}, repl}  
     end
  end

  def handle_call({:interrupt, sess}, _from, repl) do
     ecmd = Bencode.encode(HashDict.new([op: :interrupt]))
     case write_read_sock(sess, ecmd) do      
     {:ok, res}  ->  {:reply, {:ok, res}, repl}
      {_,raison} ->  {:reply, {:failed, raison}, repl}
    end
  end

  def handle_call({:describe, sess}, _from, repl) do
    ecmd = Bencode.encode(HashDict.new([op: :describe]))
    case write_read_sock(sess, ecmd) do 
     {:ok, res}  ->  {:reply, {:ok, res}, repl} 
      {_,raison} ->  {:reply, {:failed, raison}, repl}
    end
  end

  def handle_info({:close, sess}, repl) do
      # send stop to nsess
      ecmd =  Bencode.encode(HashDict.new([op: :close, session: sess.session()]))
      write_read_sock(sess, ecmd)
      # need to close socket here and putoff
      :ok = :gen_tcp.close(sess.socket)
      {:noreply, repl}
  end

  # def terminate(repl) do
  #     #  stop to nsess
  #     ecmd =  Bencode.encode(HashDict.new([op: :eval, code: "(exit)", session: sess.session()]))
  #     write_read_sock(repl.socket, ecmd)
  #     :ok = :gen_tcp.close(repl.socket)
  #     {:noreply, repl}
  # end

end