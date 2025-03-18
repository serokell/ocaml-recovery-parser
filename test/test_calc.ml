
module M = Grammar.Calc
module I = M.Parser.MenhirInterpreter


type answer =
  | Ok of M.Ast.t
  | Error (* TODO: position *)
[@@deriving sexp, compare]

let parse (s : String.t) : answer =
  let lexbuf = Lexing.from_string s in
  let _ = M.Parser.expr_eof in
  let supplier = I.lexer_lexbuf_to_supplier M.Lexer.read lexbuf in
  let start_ch = M.Parser.Incremental.expr_eof lexbuf.lex_start_p in
  I.loop_handle_undo (fun x -> Ok x) (fun _ _ -> Error) supplier start_ch

open M.Ast

let%test_unit _ =
  [%test_eq: answer] (parse "2") (Ok (Int 2))
let%test_unit _ =
  [%test_eq: answer] (parse "2 + 2") (Ok (Add (Int 2, Int 2)))
let%test_unit _ =
  [%test_eq: answer] (parse "1 * (2 + 3)") (Ok (Mul (Int 1, Par (Add (Int 2, Int 3)))))

let%test_unit _ =
  [%test_eq: answer] (parse "1 *") (Error)
let%test_unit _ =
  [%test_eq: answer] (parse "*" ) (Error)
let%test_unit _ =
  [%test_eq: answer] (parse "" ) (Error)
let%test_unit _ =
  [%test_eq: answer] (parse "1 1" ) (Error)

let is_eof (t: M.Parser.token) : bool =
  match t with
    M.Parser.EOF -> true
  | _ -> false


module RecoveryConfig =
  struct
    include M.Recover
    let guide _ = false
    let use_indentation_heuristic = false
    let is_eof = is_eof
  end

module RecoveryTracing =
  MenhirRecoveryLib.DummyPrinter (I)

(* module RecoveryTracing = *)
(*   MenhirRecoveryLib.MakePrinter (struct *)
(*     module I = I *)
(*     let print (s: string) = Printf.printf "%s" s *)
(*     let print_symbol = function *)
(*       (I.X s) -> Printf.printf "%s" (M.Recover.print_symbol s) *)
(*     let print_element = None *)
(*     let print_token (t : M.Parser.token) = *)
(*       let s = match t with *)
(*         | RIGHT_BR -> "RIGHT_BR" *)
(*         | PLUS -> "PLUS" *)
(*         | MUL -> "MUL" *)
(*         | LEFT_BR -> "LEFT_BR" *)
(*         | INT i -> string_of_int i *)
(*         | EOF -> "EOF" *)
(*       in Printf.printf "%s" s *)
(*   end) *)

module R = MenhirRecoveryLib.Make (I) (RecoveryConfig) (RecoveryTracing)

let parse2 (s : String.t) : answer =
  let lexbuf = Lexing.from_string s in
  let _ = M.Parser.expr_eof in
  let supplier = I.lexer_lexbuf_to_supplier M.Lexer.read lexbuf in
  let start_ch = M.Parser.Incremental.expr_eof lexbuf.lex_start_p in
  R.loop_handle_recover (fun x -> Ok x) (fun _ -> Error) supplier start_ch

let%test_unit _ =
  [%test_eq: answer] (parse2 "2") (Ok (Int 2))
let%test_unit _ =
  [%test_eq: answer] (parse2 "2 + 2") (Ok (Add (Int 2, Int 2)))
let%test_unit _ =
  [%test_eq: answer] (parse2 "1 * (2 + 3)") (Ok (Mul (Int 1, Par (Add (Int 2, Int 3)))))

let%test_unit _ =
  [%test_eq: answer] (parse2 "1 *") (Ok (Mul (Int 1, Int 42)))
let%test_unit _ =
  [%test_eq: answer] (parse2 "*") (Error)
let%test_unit _ =
  [%test_eq: answer] (parse2 "* 2") (Ok (Int 2))
let%test_unit _ =
  [%test_eq: answer] (parse2 "") (Error)
let%test_unit _ =
  [%test_eq: answer] (parse2 "1 1") (Ok (Int 1))
