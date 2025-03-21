(*
 * SPDX-FileCopyrightText: 2021 Serokell <https://serokell.io/>
 * SPDX-License-Identifier: MPL-2.0

 * Copyright (c) 2019 Frédéric Bour
 * SPDX-License-Identifier: MIT
 *)

module Location = Custom_compiler_libs.Location

let split_pos {Lexing. pos_lnum; pos_bol; pos_cnum; _} =
  (pos_lnum, pos_cnum - pos_bol)

let rev_filter ~f xs =
  let rec aux f acc = function
    | x :: xs when f x -> aux f (x :: acc) xs
    | _ :: xs -> aux f acc xs
    | [] -> acc
  in
  aux f [] xs

let rec rev_scan_left acc ~f ~init = function
  | [] -> acc
  | x :: xs ->
    let init = f init x in
    rev_scan_left (init :: acc) ~f ~init xs

(* Minimal signature that required from user for debug printing (tracing) *)

module type USER_PRINTER =
  sig
    module I : MenhirLib.IncrementalEngine.EVERYTHING

    val print : string -> unit
    val print_symbol : I.xsymbol -> unit
    val print_element : (I.element -> unit) option
    val print_token : I.token -> unit
  end

(* Full signature
     That separation allows users to redefine functions from full interface *)

module type PRINTER =
  sig
    include USER_PRINTER

    val print_current_state : 'a I.env -> unit
    val print_env : 'a I.env -> unit
  end

(* Make full parser from minimal one *)

module MakePrinter (U : USER_PRINTER)
       : PRINTER with module I = U.I
  =
  struct
    include U
    include MenhirLib.Printers.Make (U.I) (U)
  end

(* Simple printer that do nothing. Useful if debug isn't used *)

module DummyPrinter (I: MenhirLib.IncrementalEngine.EVERYTHING)
       : PRINTER with module I = I
  = MakePrinter (struct
                   module I = I
                   let print _ = ()
                   let print_symbol _ = ()
                   let print_element = None
                   let print_token _ = ()
                 end)

(*  Signature of module that is generated by the [merlin_recover] *)

module type RECOVERY_GENERATED =
  sig
    module I : MenhirLib.IncrementalEngine.EVERYTHING

    (* Note: [Location.t] is just default, but the type of the first argument
             [loc] isn't restricted in the [RecoverParser] and can be inferred
             from actual usage in attributes. In this case, you should shadow
             this function your signature and convert your type into
             [Location.t] in an implementation *)
    val default_value : Custom_compiler_libs.Location.t -> 'a I.symbol -> 'a

    type action =
      | Abort
      | R of int
      | S : 'a I.symbol -> action
      | Sub of action list

    type decision =
      | Nothing
      | One of action list
      | Select of (int -> action list)

    val depth : int array

    val can_pop : 'a I.terminal -> bool

    val recover : int -> decision


    val token_of_terminal : 'a I.terminal -> 'a -> I.token

    val nullable : 'a I.nonterminal -> bool

    val print_symbol : 'a I.symbol -> string
  end

module type RECOVERY =
  sig
    include RECOVERY_GENERATED

    (* User customization functions *)

    (* Customization that slightly affects on internal heuristics of choosing recovery ways.
       But returning [false] always also works well in many cases. *)
    val guide : 'a I.symbol -> bool

    val use_indentation_heuristic : bool

    val is_eof : I.token -> bool
  end

module Make
    (Parser   : MenhirLib.IncrementalEngine.EVERYTHING)
    (Recovery : RECOVERY with module I := Parser)
    (Printer  : PRINTER with module I = Parser) =
struct

  type 'a candidate = {
    line: int;
    min_col: int;
    max_col: int;
    env: 'a Parser.env;
  }

  type 'a candidates = {
    shifted: Parser.xsymbol option;
    final: 'a option;
    candidates: 'a candidate list;
  }

  module T = struct
    [@@@ocaml.warning "-37"]

    type 'a checkpoint =
      | InputNeeded of 'a Parser.env
      | Shifting of 'a Parser.env * 'a Parser.env * bool
      | AboutToReduce of 'a Parser.env * Parser.production
      | HandlingError of 'a Parser.env
      | Accepted of 'a
      | Rejected
    external inj : 'a checkpoint -> 'a Parser.checkpoint = "%identity"
  end

  let feed_token ~allow_reduction token env =
    let rec aux allow_reduction = function
      | Parser.HandlingError _ | Parser.Rejected -> `Fail
      | Parser.AboutToReduce _ when not allow_reduction -> `Fail
      | Parser.Accepted v -> `Accept v
      | Parser.Shifting _ | Parser.AboutToReduce _ as checkpoint ->
        aux true (Parser.resume checkpoint)
      | Parser.InputNeeded env as checkpoint -> `Recovered (checkpoint, env)
    in
    aux allow_reduction (Parser.offer (T.inj (T.InputNeeded env)) token)

  let rec follow_guide col env = match Parser.top env with
    | None -> col
    | Some (Parser.Element (state, _, pos, _)) ->
      if Recovery.guide (Parser.incoming_symbol state) then
        match Parser.pop env with
        | None -> col
        | Some env -> follow_guide (snd (split_pos pos)) env
      else
        col

  let candidate env =
    let line, min_col, max_col =
      match Parser.top env with
      | None -> 1, 0, 0
      | Some (Parser.Element (state, _, pos, _)) ->
        let depth = Recovery.depth.(Parser.number state) in
        let line, col = split_pos pos in
        if depth = 0 then
          line, col, col
        else
          let col' = match Parser.pop_many depth env with
            | None -> max_int
            | Some env ->
              match Parser.top env with
              | None -> max_int
              | Some (Parser.Element (_, _, pos, _)) ->
                follow_guide (snd (split_pos pos)) env
          in
          line, min col col', max col col'
    in
    { line; min_col; max_col; env }

  (* Drop first candidates that's more indented than [(line, col)] position 
     and last ones that's less indented *)
  let indentation_heuristic (line : int) (col : int) 
    (candidates : 'a candidate list) : 'a candidate list =
    let more_indented candidate =
      line <> candidate.line && candidate.min_col > col in
    let recoveries =
      let rec aux = function
        | x :: xs when more_indented x -> aux xs
        | xs -> xs
      in
      aux candidates
    in
    let same_indented candidate =
      line = candidate.line ||
      (candidate.min_col <= col && col <= candidate.max_col)
    in
    let rec aux = function
      | x :: xs when same_indented x -> x :: aux xs
      | _ -> []
    in
    aux recoveries

  let attempt (r : 'a candidates) token =
    let module P = struct
            open Printer

            let num = ref 0

            let print_prelude token =
              match token with (token, _, _) ->
                print ">>>> Recovery attempt on token \"";
                print_token token;
                print "\"\n";

                (* print "Stack:"; *)
                (* print_env r; *)
                print "\n\n"

            let print_candidate x =
              print @@ Printf.sprintf "Candidate #%d\n" !num; num := !num + 1;
              print "Stack:\n";
              print_env x.env

            let print_fail () =
              print ">>>> Recovery failed\n"

            let print_recovered env candidates =
              print ">>>> recovered with state:\n";
              print_current_state env;
              print "\n";
              print "Other candidates:\n";
              List.iteri (fun i c ->
                      print @@ Printf.sprintf "%d: " i;
                      print_current_state c.env;
                      print "\n"
                  ) candidates;

        end
    in
    P.print_prelude token;
    let _, startp, _ = token in
    let line, col = split_pos startp in
    let recoveries =
      if Recovery.use_indentation_heuristic then
        indentation_heuristic line col r.candidates
      else
        r.candidates in
    let rec aux = function
      | [] -> P.print_fail ();
              `Fail
      | x :: xs ->
         P.print_candidate x;
         match feed_token ~allow_reduction:true token x.env with
        | `Fail ->
          aux xs
        | `Recovered (InputNeeded env as checkpoint, _) ->
           P.print_recovered env xs;
           `Ok (checkpoint, x.env)
        | `Recovered _ -> failwith "Impossible"
        | `Accept v ->
          begin match aux xs with
            | `Fail -> `Accept v
            | x -> x
          end
    in
    aux recoveries

  let decide env =
    let rec nth_state env n =
      if n = 0 then
        match Parser.top env with
        | None -> -1 (*allow giving up recovery on empty files*)
        | Some (Parser.Element (state, _, _, _)) -> Parser.number state
      else
        match Parser.pop env with
        | None -> assert (n = 1); -1
        | Some env -> nth_state env (n - 1)
    in
    let st = nth_state env 0 in
    match Recovery.recover st with
    | Recovery.Nothing -> []
    | Recovery.One actions -> actions
    | Recovery.Select f -> f (nth_state env Recovery.depth.(st))

  let generate (type a) (env : a Parser.env) =
    let module E = struct
      exception Result of a
    end in
    let shifted = ref None in
    let rec aux acc env =
      match Parser.top env with
      | None -> None, acc
      | Some (Parser.Element (_state, _, _startp, endp)) ->
        let actions = decide env in
        let candidate0 = candidate env in
        let rec eval (env : a Parser.env) : Recovery.action -> a Parser.env = function
          | Recovery.Abort ->
            raise Not_found
          | Recovery.R prod ->
            let prod = Parser.find_production prod in
            Parser.force_reduction prod env
          | Recovery.S (Parser.N n as sym) ->
            let xsym = Parser.X sym in
            if !shifted = None && not (Recovery.nullable n) then
              shifted := Some xsym;
            let loc = {Location. loc_start = endp; loc_end = endp; loc_ghost = true} in
            let v = Recovery.default_value loc sym in
            Parser.feed sym endp v endp env
          | Recovery.S (Parser.T t as sym) ->
            let xsym = Parser.X sym in
            if !shifted = None then shifted := Some xsym;
            let loc = {Location. loc_start = endp; loc_end = endp; loc_ghost = true} in
            let v = Recovery.default_value loc sym in
            let token = (Recovery.token_of_terminal t v, endp, endp) in
            begin match feed_token ~allow_reduction:true token env with
              | `Fail -> assert false
              | `Accept v -> raise (E.Result v)
              | `Recovered (_,env) -> env
            end
          | Recovery.Sub actions ->
            List.fold_left eval env actions
        in
        match
          rev_scan_left [] ~f:eval ~init:env actions
          |> List.map (fun env -> {candidate0 with env})
        with
        | exception Not_found -> None, acc
        | exception (E.Result v) -> Some v, acc
        | [] -> None, acc
        | (candidate :: _) as candidates ->
          aux (candidates @ acc) candidate.env
    in
    let final, candidates = aux [] env in
    (!shifted, final, candidates)

  let generate env =
    Printer.print "Generate candidates for env:\nStack:\n";
    Printer.print_env env;
    let shifted, final, candidates = generate env in
    let candidates = rev_filter candidates
        ~f:(fun t -> not (Parser.env_has_default_reduction t.env))
    in
    { shifted; final; candidates = (candidate env) :: candidates }

  (* TODO: simplify code blow: ['a step] is not needed if we would do recovery us
     one step which though can consume more than one token at once.
     [resume_cp] should be inlined *)

  type 'a step =
      CorrectCp of 'a Parser.checkpoint
    | Recovering of 'a Parser.checkpoint * 'a candidates
    | Success of 'a
    | RecoveryFailure of 'a Parser.checkpoint

  (** Repeat [resume] until we get succeeded, inputneeded or error *)
  let rec resume_cp cp : ('a step, 'a Parser.checkpoint) result =
    match cp with
    | Parser.InputNeeded _ -> Ok (CorrectCp cp)
    | Parser.Accepted x -> Ok (Success x)
    | Parser.HandlingError _ | Parser.Rejected -> Error cp
    | Parser.Shifting _ | Parser.AboutToReduce _  -> resume_cp (Parser.resume cp)

  let assert_cp_is_InputNeeded = function
    | Parser.InputNeeded _ -> ()
    | _ -> Printer.print "Assert failed: cp is not InputNeeded"

  let try_recovery failure_cp candidates token : 'a step =
      match attempt candidates token with
      | `Ok (cp, _) ->
        assert_cp_is_InputNeeded cp;
        CorrectCp cp
      | `Accept v -> Success v
      | `Fail ->
        let token, _, _ = token in
        if not (Recovery.is_eof token) then
          let () = Printer.print "Recover is not successful, then skip the token" in
          Recovering (failure_cp, candidates) (* proceed recovering with next token *)
        else
          match candidates.final with
          | Some v -> Success v
          | None ->
            Printer.print "Error recovery: no final candidate\n";
            RecoveryFailure failure_cp

  let loop_handle_recover
      (success : 'a -> 'b)
      (fail    : 'a Parser.checkpoint -> 'b)
      (log_error : 'a Parser.checkpoint -> 'a Parser.checkpoint -> unit)
      (supplier : unit -> Parser.token * Lexing.position * Lexing.position)
      (start : 'a Parser.checkpoint)
    : 'b
    =
    let step (parser : 'a step) token : 'a step =
      match parser with
      | CorrectCp (Parser.InputNeeded env as inputneeded_cp) ->
        begin match resume_cp (Parser.offer inputneeded_cp token) with
          | Ok step -> step
          | Error failure_cp ->
            Printer.print "Error recovery: SyntaxError found\n";
            log_error inputneeded_cp failure_cp;
            let candidates = generate env in
            try_recovery failure_cp candidates token
      end
      | CorrectCp cp ->
        Printer.print "Error recovery: impossible case\n";
        RecoveryFailure cp
      | Recovering (failure_cp, candidates) ->
        Printer.print "Try recovery again\n";
        try_recovery failure_cp candidates token
      | RecoveryFailure _ | Success _ as step -> step
    in
    let rec loop parser =
      let token = supplier () in
      begin match step parser token with
        | Success v          -> success v
        | RecoveryFailure cp -> fail cp
        | CorrectCp _ | Recovering _ as st -> loop st
      end
    in loop (CorrectCp start)
end
