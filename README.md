# Elicloj  

## What is this  
Elicloj goal is to connect an Erlang/Elixir process to Clojure nRepl  

First working release using simple API   
 - Single REPL multi sessions    
 - Single server     

## TO DO 
 * correct some remaining bugs
 * properly terminate and kill repl at end 
 * create multiple server each one with its own REPL  
 * finish and make running the demo code 

## What do you need ?   
Clojure and Lein2 must be present and in your PATH  
need my simple and stupid Elixir Bencoder (deps in mix)  

## Use Case
 * first get the code 
  `git clone https://github.com/nodrygo/elicloj` 
  `mix deps.get` 
  `mix deps.compile` 
  `mix compile`  
 * then [see doc/howto](https://github.com/nodrygo/elicloj/tree/master/doc/howto.md)  

            
## requirements  
* [Elixir > 0.11.0](http://elixir-lang.org/)   
* [bencodelix](https://github.com/nodrygo/bencodelix)   
