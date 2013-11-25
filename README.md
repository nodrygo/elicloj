# Elicloj #

## What is this ##

WARNING NOT FINISHED YET ==> do not try to use it now


Elicloj goal is to connect an Erlang/Elixir process to Clojure nRepl

## What do you need ? ##
Clojure and Lein must be present and in your PATH
nRepl must be installed

my simple and stupid Elixir Bencoder [bencodelix](https://github.com/nodrygo/bencodelix)


## Use Case for tests ##

  * start iex with PATH
    iex  -pa "./ebin" -pa "./deps/bencodelix/ebin"
  * load modules
    l Elixir.Bencode
    l Elixir.Elicloj

  * tests Bencode
    dict = HashDict.new()
    dict = Dict.put(dict, :hello, :world)
    Bencode.decode(Bencode.encode dict)

  * tests Elicloj
    repl = Elicloj.start()
    response = Elicloj.cmd(:cmd, repl, "(+ 5 3)")
    repl1 =  Elicloj.cmd(:newsession)
    repl1 =  Elicloj.cmd(:close)
    repl1 =  Elicloj.cmd(:quit)

## Resources ##
* [Elixir website](http://elixir-lang.org/)
* [bencodelix](https://github.com/nodrygo/bencodelix)
