# <font color="blue"><b>Elicloj</b></font>  

## <font color="blue">What is this</font>     
Elicloj goal is to connect an Erlang/Elixir process to Clojure nRepl  

First ALPHA RELEASE working using simple API   
 <font color="red"><b><i>WARNING Not production ready</i></b></font>   
 - you can run multiple REPL -  <font color="green"><i>only one socket per REPL</i></font>   
 - you can create many CLONE per REPL  <font color="green"><i>(Clone is a THREAD in the REPL  )</i></font>

## <font color="blue">TO DO</font> 
 * correct remaining bugs
 * better handle of mltiple return from repl 
 * properly terminate and kill repl at end 
 * create multiple server each one with its own REPL  
 * finish and make running the demo code 

## <font color="blue">What do you need ? </font>     
Clojure and Lein2 must be present and in your PATH  
need my simple and stupid Elixir Bencoder (deps in mix)  

## <font color="blue">Use Case</font>   
 * first get the code 
  `git clone https://github.com/nodrygo/elicloj` 
  `mix deps.get` 
  `mix deps.compile` 
  `mix compile`  
 * then [see doc/howto](https://github.com/nodrygo/elicloj/tree/master/doc/howto.md)  

            
## <font color="blue">requirements </font>   
* [Elixir > 0.11.0](http://elixir-lang.org/)   
* [bencodelix](https://github.com/nodrygo/bencodelix)   
