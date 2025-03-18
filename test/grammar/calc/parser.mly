
%token <int> INT [@recover.expr 42]
%token LEFT_BR
%token RIGHT_BR
%token MUL
%token PLUS
%token EOF

%start <Ast.t> expr_eof
%{ open Ast %}
%%

expr_eof : e=expr_1; EOF; { e } ;

expr_1 :
  | e1=expr_2; PLUS; e2=expr_2; { Add (e1, e2) }
  | e=expr_2; { e } ;

expr_2 :
  | e1=expr_3; MUL; e2=expr_3;  { Mul (e1, e2) }
  | e=expr_3; { e } ;

expr_3 :
  | i=INT; { Int i }
  | LEFT_BR; e=expr_1; RIGHT_BR; { Par e } ;
