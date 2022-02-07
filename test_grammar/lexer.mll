{

  open Parser
  
  exception Error of string 
}

rule token = parse
| [ ' ' '\t' '\n'] { token lexbuf }
| '(' { LP }
| ')' { RP }
| eof { EOF }
| _   { raise (Error "Lexer error") }
