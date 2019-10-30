(* Lexing *)

let lex_buf lexbuf =
  Raw_lexer.init ();
  let rec loop acc =
    match Raw_lexer.token lexbuf with
    | exception (Raw_lexer.Error _) ->
      (* FIXME: Do something with the error
         (print, remember it, generate special token, whatever :P) *)
      loop acc
    | token ->
      let acc = (token, lexbuf.lex_start_p, lexbuf.lex_curr_p) :: acc in
      match token with
      | Raw_parser.EOF -> List.rev acc
      | _ -> loop acc
  in
  loop []

let lex_file fname =
  let ic = open_in_bin fname in
  let lexbuf = Lexing.from_channel ~with_positions:true ic in
  let tokens = lex_buf lexbuf in
  close_in_noerr ic;
  tokens

let string_of_token tok =
  let p name fmt = Printf.ksprintf (fun s -> name ^ " " ^ s) fmt in
  let s name x = p name "%S" x in
  match tok with
  | Raw_parser.AMPERAMPER             -> "AMPERAMPER"
  | Raw_parser.AMPERSAND              -> "AMPERSAND"
  | Raw_parser.AND                    -> "AND"
  | Raw_parser.ANDOP x                -> s "ANDOP" x
  | Raw_parser.AS                     -> "AS"
  | Raw_parser.ASSERT                 -> "ASSERT"
  | Raw_parser.BACKQUOTE              -> "BACKQUOTE"
  | Raw_parser.BANG                   -> "BANG"
  | Raw_parser.BAR                    -> "BAR"
  | Raw_parser.BARBAR                 -> "BARBAR"
  | Raw_parser.BARRBRACKET            -> "BARRBRACKE"
  | Raw_parser.BEGIN                  -> "BEGIN"
  | Raw_parser.CHAR c                 -> p "CHAR" "%C" c
  | Raw_parser.CLASS                  -> "CLASS"
  | Raw_parser.COLON                  -> "COLON"
  | Raw_parser.COLONCOLON             -> "COLONCOLON"
  | Raw_parser.COLONEQUAL             -> "COLONEQUAL"
  | Raw_parser.COLONGREATER           -> "COLONGREAT"
  | Raw_parser.COMMA                  -> "COMMA"
  | Raw_parser.COMMENT (x, _loc)      -> p "COMMENT" "%S" x
  | Raw_parser.CONSTRAINT             -> "CONSTRAINT"
  | Raw_parser.DO                     -> "DO"
  | Raw_parser.DOCSTRING _            -> "DOCSTRING"
  | Raw_parser.DONE                   -> "DONE"
  | Raw_parser.DOT                    -> "DOT"
  | Raw_parser.DOTDOT                 -> "DOTDOT"
  | Raw_parser.DOTOP x                -> s "DOTOP" x
  | Raw_parser.DOWNTO                 -> "DOWNTO"
  | Raw_parser.ELSE                   -> "ELSE"
  | Raw_parser.END                    -> "END"
  | Raw_parser.EOF                    -> "EOF"
  | Raw_parser.EOL                    -> "EOL"
  | Raw_parser.EQUAL                  -> "EQUAL"
  | Raw_parser.EXCEPTION              -> "EXCEPTION"
  | Raw_parser.EXTERNAL               -> "EXTERNAL"
  | Raw_parser.FALSE                  -> "FALSE"
  | Raw_parser.FLOAT (x, _)           -> s "FLOAT" x
  | Raw_parser.FOR                    -> "FOR"
  | Raw_parser.FUN                    -> "FUN"
  | Raw_parser.FUNCTION               -> "FUNCTION"
  | Raw_parser.FUNCTOR                -> "FUNCTOR"
  | Raw_parser.GREATER                -> "GREATER"
  | Raw_parser.GREATERRBRACE          -> "GREATERRBR"
  | Raw_parser.GREATERRBRACKET        -> "GREATERRBR"
  | Raw_parser.HASH                   -> "HASH"
  | Raw_parser.HASHOP x               -> s "HASHOP" x
  | Raw_parser.IF                     -> "IF"
  | Raw_parser.IN                     -> "IN"
  | Raw_parser.INCLUDE                -> "INCLUDE"
  | Raw_parser.INFIXOP0 x             -> s "INFIXOP0" x
  | Raw_parser.INFIXOP1 x             -> s "INFIXOP1" x
  | Raw_parser.INFIXOP2 x             -> s "INFIXOP2" x
  | Raw_parser.INFIXOP3 x             -> s "INFIXOP3" x
  | Raw_parser.INFIXOP4 x             -> s "INFIXOP4" x
  | Raw_parser.INHERIT                -> "INHERIT"
  | Raw_parser.INITIALIZER            -> "INITIALIZE"
  | Raw_parser.INT (x, _)             -> s "INT" x
  | Raw_parser.LABEL x                -> s "LABEL" x
  | Raw_parser.LAZY                   -> "LAZY"
  | Raw_parser.LBRACE                 -> "LBRACE"
  | Raw_parser.LBRACELESS             -> "LBRACELESS"
  | Raw_parser.LBRACKET               -> "LBRACKET"
  | Raw_parser.LBRACKETAT             -> "LBRACKETAT"
  | Raw_parser.LBRACKETATAT           -> "LBRACKETAT"
  | Raw_parser.LBRACKETATATAT         -> "LBRACKETAT"
  | Raw_parser.LBRACKETBAR            -> "LBRACKETBA"
  | Raw_parser.LBRACKETGREATER        -> "LBRACKETGR"
  | Raw_parser.LBRACKETLESS           -> "LBRACKETLE"
  | Raw_parser.LBRACKETPERCENT        -> "LBRACKETPE"
  | Raw_parser.LBRACKETPERCENTPERCENT -> "LBRACKETPE"
  | Raw_parser.LESS                   -> "LESS"
  | Raw_parser.LESSMINUS              -> "LESSMINUS"
  | Raw_parser.LET                    -> "LET"
  | Raw_parser.LETOP x                -> s "LETOP" x
  | Raw_parser.LIDENT x               -> s "LIDENT" x
  | Raw_parser.LPAREN                 -> "LPAREN"
  | Raw_parser.MATCH                  -> "MATCH"
  | Raw_parser.METHOD                 -> "METHOD"
  | Raw_parser.MINUS                  -> "MINUS"
  | Raw_parser.MINUSDOT               -> "MINUSDOT"
  | Raw_parser.MINUSGREATER           -> "MINUSGREAT"
  | Raw_parser.MODULE                 -> "MODULE"
  | Raw_parser.MUTABLE                -> "MUTABLE"
  | Raw_parser.NEW                    -> "NEW"
  | Raw_parser.NONREC                 -> "NONREC"
  | Raw_parser.OBJECT                 -> "OBJECT"
  | Raw_parser.OF                     -> "OF"
  | Raw_parser.OPEN                   -> "OPEN"
  | Raw_parser.OPTLABEL x             -> s "OPTLABEL" x
  | Raw_parser.OR                     -> "OR"
  | Raw_parser.PERCENT                -> "PERCENT"
  | Raw_parser.PLUS                   -> "PLUS"
  | Raw_parser.PLUSDOT                -> "PLUSDOT"
  | Raw_parser.PLUSEQ                 -> "PLUSEQ"
  | Raw_parser.PREFIXOP x             -> s "PREFIXOP" x
  | Raw_parser.PRIVATE                -> "PRIVATE"
  | Raw_parser.QUESTION               -> "QUESTION"
  | Raw_parser.QUOTE                  -> "QUOTE"
  | Raw_parser.RBRACE                 -> "RBRACE"
  | Raw_parser.RBRACKET               -> "RBRACKET"
  | Raw_parser.REC                    -> "REC"
  | Raw_parser.RPAREN                 -> "RPAREN"
  | Raw_parser.SEMI                   -> "SEMI"
  | Raw_parser.SEMISEMI               -> "SEMISEMI"
  | Raw_parser.SIG                    -> "SIG"
  | Raw_parser.STAR                   -> "STAR"
  | Raw_parser.STRING (x, _)          -> s "STRING" x
  | Raw_parser.STRUCT                 -> "STRUCT"
  | Raw_parser.THEN                   -> "THEN"
  | Raw_parser.TILDE                  -> "TILDE"
  | Raw_parser.TO                     -> "TO"
  | Raw_parser.TRUE                   -> "TRUE"
  | Raw_parser.TRY                    -> "TRY"
  | Raw_parser.TYPE                   -> "TYPE"
  | Raw_parser.UIDENT x               -> s "UIDENT" x
  | Raw_parser.UNDERSCORE             -> "UNDERSCORE"
  | Raw_parser.VAL                    -> "VAL"
  | Raw_parser.VIRTUAL                -> "VIRTUAL"
  | Raw_parser.WHEN                   -> "WHEN"
  | Raw_parser.WHILE                  -> "WHILE"
  | Raw_parser.WITH                   -> "WITH"

let dump_tokens tokens =
  List.iter (fun (token, {Lexing. pos_cnum; pos_bol; pos_lnum; _}, _endp) ->
      Printf.printf "% 4d:%02d   %s\n"
        pos_lnum (pos_cnum - pos_bol) (string_of_token token)
    ) tokens

(* Parsing *)

module P = Raw_parser
module I = P.MenhirInterpreter

let rec loop tokens cp =
  match cp with
  | I.Accepted x -> Some x
  | I.Rejected -> None
  | I.Shifting (_, _, _) | I.AboutToReduce (_, _) | I.HandlingError _ ->
    loop tokens (I.resume cp)
  | I.InputNeeded _ ->
    match tokens with
    | [] -> assert false
    | token :: tokens -> loop tokens (I.offer cp token)

(* Entrypoint *)

let () =
  let len = Array.length Sys.argv in
  if len = 1 then
    Printf.eprintf
      "Usage: '%s' { '-debug' | 'filename.ml' | 'filename.mli' }"
      Sys.argv.(0)
  else
    let debug = ref false in
    for i = 1 to len - 1 do
      match Sys.argv.(i) with
      | "-debug" -> debug := true
      | fname ->
        let tokens = lex_file fname in
        (* dump_tokens tokens; *)
        (* Interface or implementation? Check last character *)
        if fname <> "" && fname.[String.length fname - 1] = 'i' then
          match loop tokens (P.Incremental.interface Lexing.dummy_pos) with
          | None -> prerr_endline "Failed to parse interface"
          | Some intf -> Format.printf "%a\n%!" Pprintast.signature intf
        else
          match loop tokens (P.Incremental.implementation Lexing.dummy_pos) with
          | None -> prerr_endline "Failed to parse implementation"
          | Some impl -> Format.printf "%a\n%!" Pprintast.structure impl
    done

