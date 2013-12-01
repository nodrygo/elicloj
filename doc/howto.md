# HOW TO DO 


## first start Elixir  

  * `start iex -S mix`       start iex in dev mode    
  * `l Elixir.Elicloj`       load elicloj module  

  first create a session Record  
  * `sess = Elicloj.start`   start server with repl  
  then it is better to work with a session clone <I>(not required)</I>   
  * `{:ok, sess, resp}=Elicloj.clone(sess)`  
  the sess keep info on working socket. sess is needed when calling next api   

  now we can play with API fct

## API call   
  <i>for  :clone :describe :eval  :interrupt   :load-file(:file)  :ls-sessions</i>   
  [please have a look for nRepl doc commands](https://github.com/clojure/tools.nrepl/blob/master/doc/ops.md)  
  * `{:ok, sess1, resp}=Elicloj.clone(sess)`         create new session on same repl/socke  
  * `{:ok, sess , resp}=Elicloj.lssession(sess)`      get current session list  
  * `{:ok, sess , resp}=Elicloj.describe(sess)`       get hash of repl  status   
  * `{:ok, sess , resp}=Elicloj.exec(sess ,"(+ 1 2)")` eval clojure command (cmd is in a string)  
  * `{:ok, sess , resp}=Elicloj.close(sess)`         close current session  
  * `{:ok, sess , resp}=Elicloj.interrupt(sess)`     interrupt current eval  

  each API answer ether <b>{:ok, sess, resp }</b> OR <b>{:failed, errmsg }</b> 


## You can also start with   
  `iex -pa "_build/shared/lib/*/ebin"` 
                          