# Elicloj  

## What is this  

!!!!! WARNING NOT FINISHED YET ==> do not try to use it now  !!!!!    


Elicloj goal is to connect an Erlang/Elixir process to Clojure nRepl  

## What do you need ?   
Clojure and Lein must be present and in your PATH  
nRepl must be installed  on Lein 

need my simple and stupid Elixir Bencoder [bencodelix](https://github.com/nodrygo/bencodelix)  


## Use Case for tests  

  * start iex with PATH  
    with ELIXIR version < 0.11.2
       - iex  -pa "./ebin" -pa "./deps/bencodelix/ebin"  
    with ELIXIR version >= 0.11.2
       - iex -pa "_build/shared/lib/*/ebin"
  * load modules  
    `l Elixir.Bencode`   
    `l Elixir.Elicloj`

            
    or better 
       -  `iex -S mix`    

  * load modules  
    `l Elixir.Bencode`   
    `l Elixir.Elicloj`   

  * tests Bencode  
    `dict = HashDict.new()`  
    `dict = Dict.put(dict, :hello, :world)`  
    `Bencode.decode(Bencode.encode dict)`  

  * tests Elicloj   
    API call  for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions  
    all sessions paramaters are keept on a Sess Record and must be passed 
    (look at https://github.com/clojure/tools.nrepl/blob/master/doc/ops.md)  
     `sess = Elicloj.start()`                  create new repl  
     `sessnew = Elicloj.clone(sess)`    create new session on same repl  
     `Elicloj.session(sess)`                   get current session list  
     `Elicloj.describe(sess)`  
     `Elicloj.exec(clojcmd, sess)`         eval clojure command (in a string)  
     `Elicloj.close(sess)`                       close current session  
     `Elicloj.interrupt(sess)`                 interrupt current eval  


* [Elixir website](http://elixir-lang.org/)  
* [bencodelix](https://github.com/nodrygo/bencodelix)  
