(*
 * Copyright (c) 2019 Frédéric Bour
 *
 * SPDX-License-Identifier: MIT
 *)

open MenhirSdk.Cmly_api
open Attributes
open Utils

(** Specification of synthesized tactics *)

module type SYNTHESIZER = sig
  module G : GRAMMAR

  (* Specification of problems

     There are two situations we want to synthesize solution for:

     - `Head` is when the dot is just in front of some non-terminal,
       and we would like to find a way to move the dot to the right of
       this symbol (by executing a sequence of actions that results in
       this non-terminal being pushed on the stack)

     - `Tail` is when the dot is in some production that we would like
       to reduce.
  *)

  type variable =
    | Head of G.lr1 * G.nonterminal
    | Tail of G.lr1 * G.production * int

  (* The integer parameter in `Tail` is the position of the dot in
     the production we are trying to reduce. This is necessary to
     uniquely identify a production that occurs multiple time in a
     state.

     For instance, in the grammar:

     %token<int> INT
     %token PLUS

     expr:
     | INT { $1 } (*const*)
     | expr PLUS expr { $1 + $2 } (*add*)

     Synthesizing `Head (st0, expr)` when `expr PLUS . expr` is in
     `st0` will output the actions to get to the state `st'`
     containing `expr PLUS expr .`.

     Synthesizing `Tail (st1, add, 1)` when `expr . PLUS expr` is in
     `st1` will output the actions that end up reducing `add` (which
     will likely be shifting `PLUS`, synthesizing `Head (st0, expr)`
     and reducing add).
  *)

  val variable_to_string : variable -> string
  (** A human readable representation of a [variable]. *)

  (** Specification of solutions

      A successful synthesis results in a list of actions. *)

  type action =
    | Abort
    | Reduce of G.production
    | Shift  of G.symbol
    | Seq    of action list

  (* `Abort` is issued if there is no solution. This is the case for instance
     if there is a semantic value that the synthesizer cannot produce, or a
     production with an infinite cost.

     `Shift` and `Reduce` are direct actions to execute on the parser.

     `Seq` is a sequence of action.
  *)

  val action_to_string : action -> string
  (** A human readable representation of an action. *)

  val solve : variable -> Cost.t * action list
  (** Give the solution found for a variable as a list of action. *)

  val report : Format.formatter -> unit
  (** Print the solutions or absence thereof for the whole grammar. *)
end

(** Synthesizer implementation *)

module Synthesizer (G : GRAMMAR) (A : ATTRIBUTES with module G = G)
  : SYNTHESIZER with module G := G =
struct
  open G

  type variable =
    | Head of lr1 * nonterminal
    | Tail of lr1 * production * int

  let variable_to_string = function
    | Head (st, n) ->
      Printf.sprintf "Head (#%d, %s)"
        (Lr1.to_int st) (Nonterminal.name n)
    | Tail (st, prod, pos) ->
      Printf.sprintf "Tail (#%d, p%d, %d)"
        (Lr1.to_int st) (Production.to_int prod) pos

  type action =
    | Abort
    | Reduce of production
    | Shift  of symbol
    | Seq    of action list

  let rec action_to_string = function
    | Abort -> "Abort"
    | Reduce prod -> "Reduce p" ^ string_of_int (Production.to_int prod)
    | Shift  sym -> "Shift " ^ (symbol_name sym)
    | Seq actions ->
      "Seq [" ^ String.concat "; " (List.map action_to_string actions) ^ "]"


  (** The synthesizer specify the cost as a system of equations of the form
      $$
      x_i = \min_{j} ({\kappa_{i,j} + \sum_{k}x_{i,j,k}})
      $$
      which can be read as follow:

      - $x_i$ are variables, the thing we would like to know the cost of (the
        `Head` and `Tail` defined above)

      - $j$ ranges over the different branches, the different candidates (for
        instance, to synthesize a _non-terminal_, each production that reduces
        to this _non-terminal_ is a valid candidate)

      - each of these candidates is made of a constant and the sum of a
        possibly empty list of other variables

      Variables are valued in $\left[0,+\infin\right]$ (and the empty $\sum$
      defaults to $0$, the empty $min$ to $+\infin$).

      The solution is the least fixed point of this system computed by
      [Fix](https://gitlab.inria.fr/fpottier/fix) library.

      $$
      \begin{align}
        \text{head}_{st,nt} = & \min \left\{ \begin{array}{ll}
        \text{cost}(\text{empty-reductions}(st,nt))\\
        \text{tail-reductions}(st,nt)
      \end{array}
      \right.
      \\
      \text{empty-reductions}(st,nt) = &
      \\
      \text{tail}_{st,prod,i} = &
      \end{align}
      $$

      For a variable `Head (st, nt)` , the branches are the different
      productions that can reduce to `nt` and starts from state `st`. The
      constant is the same for all branches, $\kappa_{i,j} = \kappa_i$,
  *)

  let cost_of_prod    p = A.cost_of_prod p
  let cost_of_symbol  s = A.cost_of_symbol s
  let penalty_of_item i = A.penalty_of_item i

  let app var v = v var

  let bottom = (Cost.infinite, [Abort])

  let var var = match var with
    | Head _ -> app var
    | Tail (_,prod,pos) ->
      let prod_len = Array.length (Production.rhs prod) in
      assert (pos <= prod_len);
      if pos < prod_len
      then app var
      else const (cost_of_prod prod, [Reduce prod])

  let productions =
    let table = Array.make Nonterminal.count [] in
    Production.iter (fun p ->
        let nt = Nonterminal.to_int (Production.lhs p) in
        table.(nt) <- p :: table.(nt)
      );
    (fun nt -> table.(Nonterminal.to_int nt))

  let cost_of = function
    | Head (st, nt) ->
      begin fun v ->
        let minimize_over_prod (cost,_ as solution) prod =
          let (cost', _) as solution' = v (Tail (st, prod, 0)) in
          if cost <= cost' then solution else solution'
        in
        List.fold_left minimize_over_prod bottom (productions nt)
      end

    | Tail (st, prod, pos) ->
      let prod_len = Array.length (Production.rhs prod) in
      assert (pos <= prod_len);
      let penalty = penalty_of_item (prod, pos) in
      if Cost.is_infinite penalty then
        const bottom
      else if pos = prod_len then
        let can_reduce = List.exists
            (fun (_,p) -> prod == p) (Lr1.get_reductions st)
        in
        const (if can_reduce
               then (cost_of_prod prod, [Reduce prod])
               else (Cost.infinite, [Abort]))
      else
        let head =
          let sym, _, _ = (Production.rhs prod).(pos) in
          let cost = cost_of_symbol sym in
          if Cost.is_infinite cost
          then match sym with
            | T _ -> const bottom
            | N n -> var (Head (st, n))
          else const (cost, [Shift sym])
        in
        let tail =
          let sym, _, _ = (Production.rhs prod).(pos) in
          match List.assoc sym (Lr1.transitions st) with
          | st' -> var (Tail (st', prod, pos + 1))
          | exception Not_found ->
            (*report "no transition: #%d (%d,%d)\n"
              st.lr1_index prod.p_index pos;*)
            const bottom
        in
        (fun v ->
           let costh, actionh = head v in
           let costt, actiont = tail v in
           (Cost.add costh costt, Seq actionh :: actiont)
        )

  let solve =
    (*  For > 4.02
        let module Solver = Fix.Fix.ForType (struct
          type t = variable
        end) (struct
          type property = Cost.t * action list
          let bottom = (Cost.infinite, [Abort])
          let equal (x, _ : property) (y, _ : property) : bool =
            Cost.compare x y = 0
          let is_maximal _ = false
        end)
        in
    *)
    let module Solver = Fix.Make (struct
        type key = variable
        type 'data t = (key, 'data) Hashtbl.t
        let create () = Hashtbl.create 97
        let clear tbl = Hashtbl.clear tbl
        let add key value tbl = Hashtbl.add tbl key value
        let find key tbl = Hashtbl.find tbl key
        let iter f tbl = Hashtbl.iter f tbl
      end) (struct
        type property = Cost.t * action list
        let bottom = (Cost.infinite, [Abort])
        let equal (x, _ : property) (y, _ : property) : bool =
          Cost.compare x y = 0
        let is_maximal _ = false
      end)
    in
    Solver.lfp cost_of

  let report ppf =
    let open Format in
    let solutions = List.rev @@ Lr1.fold
        (fun st acc ->
           match
             List.fold_left (fun acc ((prod, pos) as item) ->
                 let solution = solve (Tail (st, prod, pos)) in
                 (item, solution) :: acc
               ) [] (Lr0.items (Lr1.lr0 st))
           with
           | [] ->
             fprintf ppf "no synthesis from %d\n" (Lr1.to_int st);
             acc
           | items -> (st, items) :: acc
        ) []
    in
    let fprintf = Format.fprintf in
    let rec print_action ppf = function
      | Abort -> fprintf ppf "Abort"
      | Reduce prod  -> fprintf ppf "Reduce %d" (Production.to_int prod)
      | Shift  (T t) -> fprintf ppf "Shift (T %s)" (Terminal.name t)
      | Shift  (N n) -> fprintf ppf "Shift (N %s)" (Nonterminal.mangled_name n)
      | Seq    actions -> fprintf ppf "Seq %a" print_actions actions
    and print_actions ppf = Utils.pp_list print_action ppf in
    let cost_to_string cost =
      if Cost.is_infinite cost then "inf" else sprintf "%2d" (Cost.to_int cost) in
    let print_item_with_solution ppf = function
      | (prod, pos), (cost, actions) ->
         fprintf ppf "Item(%3d, %1d) at cost %s:\n %a => %a\n"
             (Production.to_int prod) pos (cost_to_string cost)
             Print.item (prod, pos)
             print_actions actions
    in
    let sort_by_cost =
      List.stable_sort (fun (_, (cost1, _)) (_, (cost2, _)) -> compare cost1 cost2) in
    fprintf ppf "\n\n";
    fprintf ppf "\n(* COSTS OF SOLUTIONS: *)\n\n";
    List.iter (fun (state, items) ->
        fprintf ppf "State: #%d\n" (Lr1.to_int state);
        fprintf ppf "\n";
        List.iter (fun (item, solution) ->
                print_item_with_solution ppf (item, solution))
             (sort_by_cost items);
        fprintf ppf "\n\n"
      ) solutions;
    fprintf ppf "\n(* DEFAULT COST OF SYMBOLS: %s *)\n\n"
        (cost_to_string A.default_cost_of_symbol);
    fprintf ppf "\n(* DEFAULT COST OF PRODUCTIONS: %s *)\n\n"
        (cost_to_string A.default_cost_of_prod);
    fprintf ppf "\n(* PRODUCTIONS WITH NON-DEFAULT COST: *)\n\n";
    Production.iter (fun prod ->
      let cost = A.cost_of_prod prod in
      if Cost.compare cost A.default_cost_of_prod <> 0 then
          fprintf ppf "Production#%d %a at cost %s\n"
              (Production.to_int prod)
              Print.production prod
              (cost_to_string cost)
    );
    fprintf ppf "\n(* TERMINALS WITH NON-DEFAULT COST: *)\n\n";
    Terminal.iter (fun t ->
      let cost = A.cost_of_symbol (T t) in
      if (Cost.compare cost A.default_cost_of_symbol) <> 0 then
        fprintf ppf "%a at cost %s\n"
            Print.terminal t
            (cost_to_string cost)
    );
    fprintf ppf "\n(* NONTERMINALS WITH NON-INFINITE COST: *)\n\n";
    Nonterminal.iter (fun n ->
        let cost = cost_of_symbol (N n) in
        if not (Cost.is_infinite cost) then
          fprintf ppf "%a at cost %s\n"
              Print.nonterminal n
              (cost_to_string @@ cost)
    );
    fprintf ppf "\n(* PENALTY OF ITEMS (not equal zero): *)\n\n";
    Production.iter (fun prod ->
      for pos = 0 to Array.length (Production.rhs prod) - 1 do
        let item = (prod, pos) in
        let cost = penalty_of_item item in
        if Cost.compare cost Cost.zero <> 0 then
            fprintf ppf "Item (%3d, %d) %a at cost %s\n"
                (Production.to_int (prod)) pos
                Print.item item
                (cost_to_string @@ cost)
      done
    )
end
