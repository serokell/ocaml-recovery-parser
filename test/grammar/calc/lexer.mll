{
open Parser

exception SyntaxError of string
}

let int = '-'? ['0'-'9'] ['0'-'9']*
let white = [' ' '\t']+

rule read =
  parse
  | white { read lexbuf }
  | int   { INT (int_of_string (Lexing.lexeme lexbuf)) }
  | '('   { LEFT_BR }
  | ')'   { RIGHT_BR }
  | '+'   { PLUS }
  | '*'   { MUL }
  | _     { raise (SyntaxError ("Unexpected char: " ^ (Lexing.lexeme lexbuf)))}
  | eof   { EOF }
