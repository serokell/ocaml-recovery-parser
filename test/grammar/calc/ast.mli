
open! Sexplib.Std
open! Ppx_compare_lib.Builtin

type t =
  | Int of int
  | Add of t * t
  | Mul of t * t
  | Par of t
[@@deriving sexp, compare]
