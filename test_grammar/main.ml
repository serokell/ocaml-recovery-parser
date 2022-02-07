
module Inter = Parser.MenhirInterpreter

(* let filename = Sys.argv.(1) *)
exception ParsingError of string

(* Debug printer *)

let tracing_channel = stdout
let error_recovery_tracing = true

module TracingPrinter
  = Merlin_recovery.MakePrinter
    (struct
      module I = Inter
      let print str =
        if error_recovery_tracing then
          Printf.fprintf tracing_channel "%s" str;
        flush_all ()

      let print_symbol = function
        | Inter.X s -> print @@ Parser_recover.print_symbol s

      let print_element = None

      let print_token t = print @@ "Tkn"
    end)


module R = Merlin_recovery.Make
    (Inter)
    (struct
      include Parser_recover

      let default_value _loc sym =
        default_value sym
      (* TODO *)

      let guide _ = false
    end)
    (* (Merlin_recovery.DummyPrinter (Inter)) *)
    (TracingPrinter)

module Recover =
struct
  type 'a parser =
    | Correct of 'a Inter.checkpoint
    | Recovering of 'a Inter.checkpoint * 'a R.candidates
    (* [Recovering (failure_checkpoint, candidates)]  *)

  type 'a step =
    | Intermediate of 'a parser
    | Success of 'a
    | Error of 'a Inter.checkpoint

  let rec normalize checkpoint =
    match checkpoint with
    | Inter.InputNeeded _ -> Intermediate (Correct checkpoint)
    | Inter.Accepted x    -> Success x
    | Inter.HandlingError _ | Inter.Rejected        -> Error checkpoint
    | Inter.Shifting _      | Inter.AboutToReduce _ ->
      normalize (Inter.resume checkpoint)

  let recovery_env = function
    | Inter.InputNeeded env -> env
    | _ -> assert false

  let step parser failure token : 'a step * string option =
    let try_recovery failure_cp candidates: 'a step =
      begin match R.attempt candidates token with
        | `Ok (Inter.InputNeeded _ as cp, _) ->
          Intermediate (Correct cp)
        | `Ok _     -> failwith "Impossible"
        | `Accept x -> Success x
        | `Fail ->
          begin match token with
            | EOF, _, _ (* when Token.is_eof token *) ->
              begin match candidates.final with
                | Some x -> Success x
                | None -> Error failure_cp (* Fatal error *)
              end
            (* If recovering fails skip token and try again. *)
            | _ ->
              Intermediate (Recovering (failure_cp, candidates))
          end
      end in
    match parser with
    | Correct cp ->
      begin match normalize (Inter.offer cp token) with
        | Intermediate _ | Success _ as s -> (s, None)
        | Error failure_cp ->
          let error = failure failure_cp in
          TracingPrinter.print @@ Printf.sprintf "Error\n";  (* error.Region.value; *)
          let env = recovery_env cp in
          let candidates = R.generate env in
          (try_recovery failure_cp candidates, Some error)
      end
    | Recovering (failure_cp, candidates) ->
      (try_recovery failure_cp candidates, None)

  let loop_handle
      (success : 'a -> 'a) (failure : 'a Inter.checkpoint -> string)
      (supplier : unit -> Parser.token * Lexing.position * Lexing.position)
      (initial : 'a Inter.checkpoint) =
    let initial = Correct initial in
    let errors = ref [] in
    let rec loop parser =
      match supplier () with
      (* | exception LexingError msg -> Stdlib.Error (msg, !errors) *)
      | token ->
        let (s, error) = (step parser failure token) in
        begin match error with
          | Some error -> errors := error :: !errors;
          | None       -> ()
        end;
        match s with
        | Success x              -> Stdlib.Ok (success x, !errors)
        | Intermediate (parser)  -> loop parser
        (* Fatal recovery error !!! *)
        | Error cp               -> Stdlib.Error (failure cp, !errors)
    in loop initial
end

(* let get_message_on_failure (module ParErr : PAR_ERR) checkpoint =
 *   let msg = get_error_message (module ParErr) checkpoint in
 *   let window = get_window () in
 *   let region = Token.to_region window#current_token
 *   in Region.{value = msg; region} *)

(* let incr_menhir_recovery lexbuf_of (module ParErr : PAR_ERR) source =
 *   let lexbuf       = lexbuf_of source
 *   and menhir_lexer = mk_menhir_lexer Lexer.scan in
 *   let supplier     = Inter.lexer_lexbuf_to_supplier menhir_lexer lexbuf in
 *   let failure      = get_message_on_failure (module ParErr) in
 *   let interpreter  = Recover.loop_handle success failure supplier in
 *   let module Incr  = Parser.Incremental in
 *   let parser       = Incr.main lexbuf.Lexing.lex_curr_p in
 *   let result       = interpreter parser
 *   in flush_all (); result *)

let main () =
(*   let input = open_in filename in *)
  let buf = Lexing.from_channel stdin in
  (* let v = (Parser.s Lexer.token buf) in *)
  let supplier = Inter.lexer_lexbuf_to_supplier Lexer.token buf in
  let failure x = "Error" in
  let v = Recover.loop_handle (fun x -> x) failure supplier (Parser.Incremental.s buf.Lexing.lex_curr_p) in
  match v with
    Ok (v, _) -> Printf.printf "%d" v
  | _ -> failwith "Error result"
 
let _ = main ()
