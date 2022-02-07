
%token LP  [@recover.cost 0]
%token RP  [@recover.cost 1]
%token EOF [@recover.cost 100]

%start <int> s

%%
 
s: RP a EOF { $2 };

a: b LP RP  { $1 + 1 }

b: a  { $1 }
 | RP { 0 }


(* call = expr ()
 * expr = call
 *      = ..
 * 
 * expr = expr ()
 *      = ... *)

(* It isn't left recursion
 *
 * a: LP RP b { $3 + 1 }
 * 
 * b: a  { $1 }
 *  | RP { 0 } *)


(* After substitution
 *
 * a: a LP RP  { $1 + 1 }
 *  | RP LP RP { 1 } *)

(* Hidden left-recursion: ok

a: b LP RP  { $1 + 1 }
 | { 0 };

b: a { $1 }

 *)

(* Direct left-recursion: ok

a: a LP RP  { $1 + 1 }
 | { 0 };
 *)



(* Hidden left-recursion: error

a: b a LP RP  { $1 + 1 }
 | { 0 };

b: { 0 }

 *)

 (* b:
 * | a { $1 }
 * | RP  { 0  }; *)

(* b :
 * | b1 { $1 }
 * | b2 { $1 };
 * 
 * b1 [@recover.cost 100] :
 * | a { $1 };
 * 
 * b2 :
 * | RP  { 0  } *)
