open Cerb_frontend
open Extra
open Panic
open Coq_ast
open Rc_annot

type typed_ail = GenTypes.genTypeCategory AilSyntax.ail_program
type ail_expr  = GenTypes.genTypeCategory AilSyntax.expression
type c_type    = Ctype.ctype
type i_type    = Ctype.integerType
type type_cat  = GenTypes.typeCategory
type loc       = Location_ocaml.t

let to_type_cat : GenTypes.genTypeCategory -> type_cat = fun tc ->
  let loc = Location_ocaml.unknown in
  let impl = Ocaml_implementation.hafniumIntImpl in
  let m_tc = GenTypesAux.interpret_genTypeCategory loc impl tc in
  match ErrorMonad.runErrorMonad m_tc with
  | Either.Right(tc) -> tc
  | Either.Left(_,_) -> assert false (* FIXME possible here? *)

let not_impl loc fmt = panic loc ("Not implemented: " ^^ fmt)

let forbidden loc fmt = panic loc ("Forbidden: " ^^ fmt)

(* Short names for common functions. *)
let sym_to_str : Symbol.sym -> string =
  Pp_symbol.to_string_pretty

let id_to_str : Symbol.identifier -> string =
  fun Symbol.(Identifier(_,id)) -> id

let loc_of_id : Symbol.identifier -> loc =
  fun Symbol.(Identifier(loc,_)) -> loc

(* Register a location. *)
let register_loc : Location.Pool.t -> loc -> Location.t = fun p loc ->
  match Location_ocaml.(get_filename loc, to_cartesian loc) with
  | (Some(f), Some((l1,c1),(0 ,0 ))) -> Location.make f l1 c1 l1 c1 p
  | (Some(f), Some((l1,c1),(l2,c2))) -> Location.make f l1 c1 l2 c2 p
  | (_      , _                    ) -> Location.none coq_locs

let register_str_loc : Location.Pool.t -> loc -> Location.t = fun p loc ->
  match Location_ocaml.(get_filename loc, to_cartesian loc) with
  | (Some(f), Some((l1,c1),(l2,c2))) -> Location.make f l1 (c1+1) l2 (c2-1) p
  | (_      , _                    ) -> Location.none coq_locs

let mkloc elt loc = Location.{ elt ; loc }

let noloc elt = mkloc elt (Location.none coq_locs)

(* Extract attributes with namespace ["rc"]. *)
let collect_rc_attrs : Annot.attributes -> rc_attr list =
  let fn acc Annot.{attr_ns; attr_id; attr_args} =
    match Option.map id_to_str attr_ns with
    | Some("rc") ->
        let rc_attr_id =
          let Symbol.(Identifier(loc, id)) = attr_id in
          mkloc id (register_loc rc_locs loc)
        in
        let rc_attr_args =
          let fn (loc, s) = mkloc s (register_str_loc rc_locs loc) in
          List.map fn attr_args
        in
        {rc_attr_id; rc_attr_args} :: acc
    | _          -> acc
  in
  fun (Annot.Attrs(attrs)) -> List.fold_left fn [] attrs

let rec translate_int_type : loc -> i_type -> Coq_ast.int_type = fun loc i ->
  let open Ctype in
  let open Ocaml_implementation in
  let size_of_base_type signed i =
    match i with
    (* Things defined in the standard libraries *)
    | IntN_t(_)       -> not_impl loc "size_of_base_type (IntN_t)"
    | Int_leastN_t(_) -> not_impl loc "size_of_base_type (Int_leastN_t)"
    | Int_fastN_t(_)  -> not_impl loc "size_of_base_type (Int_fastN_t)"
    | Intmax_t        -> not_impl loc "size_of_base_type (Intmax_t)"
    | Intptr_t        -> ItSize_t(signed)
    (* Normal integer types *)
    | Ichar | Short | Int_ | Long | LongLong ->
    let ity = if signed then Signed(i) else Unsigned i in
    match HafniumImpl.sizeof_ity ity with
    | Some(1) -> ItI8(signed)
    | Some(2) -> ItI16(signed)
    | Some(4) -> ItI32(signed)
    | Some(8) -> ItI64(signed)
    | Some(p) -> not_impl loc "unknown integer precision: %i" p
    | None    -> assert false
  in
  match i with
  | Char        -> size_of_base_type (hafniumIntImpl.impl_signed Char) Ichar
  | Bool        -> ItBool
  | Signed(i)   -> size_of_base_type true  i
  | Unsigned(i) -> size_of_base_type false i
  | Enum(s)     -> translate_int_type loc (HafniumImpl.typeof_enum s)
  (* Things defined in the standard libraries *)
  | Wchar_t     -> not_impl loc "layout_of (Wchar_t)"
  | Wint_t      -> not_impl loc "layout_of (Win_t)"
  | Size_t      -> ItSize_t(false)
  | Ptrdiff_t   -> not_impl loc "layout_of (Ptrdiff_t)"

(** [layout_of fa c_ty] translates the C type [c_ty] into a layout.  Note that
    argument [fa] must be set to [true] when in function arguments, since this
    requires a different tranlation for arrays (always pointers). *)
let layout_of : bool -> c_type -> Coq_ast.layout = fun fa c_ty ->
  let rec layout_of Ctype.(Ctype(annots, c_ty)) =
    let loc = Annot.get_loc_ annots in
    match c_ty with
    | Void                -> LVoid
    | Basic(Integer(i))   -> LInt (translate_int_type loc i)
    | Basic(Floating(_))  -> not_impl loc "layout_of (Basic float)"
    | Array(_,_) when fa  -> LPtr
    | Array(c_ty,None )   -> LPtr
    | Array(c_ty,Some(n)) -> LArray(layout_of c_ty, Z.to_string n)
    | Function(_,_,_,_)   -> not_impl loc "layout_of (Function)"
    | Pointer(_,_)        -> LPtr
    | Atomic(c_ty)        -> layout_of c_ty
    | Struct(sym)         -> LStruct(sym_to_str sym, false)
    | Union(syn)          -> LStruct(sym_to_str syn, true )
  in
  layout_of c_ty

(* Hashtable of local variables to distinguish global ones. *)
let local_vars = Hashtbl.create 17

(* Hashtable of global variables used. *)
let used_globals = Hashtbl.create 5

(* Hashtable of used function. *)
let used_functions = Hashtbl.create 5

let (fresh_ret_id, reset_ret_id) =
  let counter = ref (-1) in
  let fresh () = incr counter; Printf.sprintf "$%i" !counter in
  let reset () = counter := -1 in
  (fresh, reset)

let (fresh_block_id, reset_block_id) =
  let counter = ref (-1) in
  let fresh () = incr counter; Printf.sprintf "#%i" !counter in
  let reset () = counter := -1 in
  (fresh, reset)

let rec ident_of_expr (AilSyntax.AnnotatedExpression(_,_,loc,e)) =
  let open AilSyntax in
  match e with
  | AilEident(sym)        -> Some(loc, sym_to_str sym)
  | AilEfunction_decay(e) -> ident_of_expr e
  | _                     -> None

let c_type_of_type_cat : type_cat -> c_type = fun tc ->
  match tc with
  | GenTypes.LValueType(_,c_ty,_) -> c_ty
  | GenTypes.RValueType(c_ty)     -> c_ty

let layout_of_tc : type_cat -> Coq_ast.layout = fun tc ->
  layout_of false (c_type_of_type_cat tc)

let is_atomic : c_type -> bool = AilTypesAux.is_atomic

let is_atomic_tc : GenTypes.typeCategory -> bool = fun tc ->
  is_atomic (c_type_of_type_cat tc)

let tc_of (AilSyntax.AnnotatedExpression(ty,_,_,_)) = to_type_cat ty

let loc_of (AilSyntax.AnnotatedExpression(_,_,loc,_)) = loc

let is_const_0 (AilSyntax.AnnotatedExpression(_, _, _, e)) =
  let open AilSyntax in
  match e with
  | AilEconst(c) ->
      begin
        match c with
        | ConstantInteger(IConstant(i,_,_)) -> Z.equal Z.zero i
        | _                                 -> false
      end
  | _            -> false

let op_type_of loc Ctype.(Ctype(_, c_ty)) =
  match c_ty with
  | Void                -> not_impl loc "op_type_of (Void)"
  | Basic(Integer(i))   -> OpInt(translate_int_type loc i)
  | Basic(Floating(_))  -> not_impl loc "op_type_of (Basic float)"
  | Array(_,_)          -> not_impl loc "op_type_of (Array)"
  | Function(_,_,_,_)   -> not_impl loc "op_type_of (Function)"
  | Pointer(_,c_ty)     -> OpPtr(layout_of false c_ty)
  | Atomic(_)           -> not_impl loc "op_type_of (Atomic)"
  | Struct(_)           -> not_impl loc "op_type_of (Struct)"
  | Union(_)            -> not_impl loc "op_type_of (Union)"

let op_type_of_tc : loc -> type_cat -> Coq_ast.op_type = fun loc tc ->
  op_type_of loc (c_type_of_type_cat tc)

(* We need similar function returning options for casts. *)
let op_type_opt loc Ctype.(Ctype(_, c_ty)) =
  match c_ty with
  | Void                -> None
  | Basic(Integer(i))   -> Some(OpInt(translate_int_type loc i))
  | Basic(Floating(_))  -> None
  | Array(_,_)          -> None
  | Function(_,_,_,_)   -> None
  | Pointer(_,c_ty)     -> Some(OpPtr(layout_of false c_ty))
  | Atomic(_)           -> None
  | Struct(_)           -> None
  | Union(_)            -> None

let op_type_tc_opt : loc -> type_cat -> Coq_ast.op_type option = fun loc tc ->
  op_type_opt loc (c_type_of_type_cat tc)

let struct_data : ail_expr -> string * bool = fun e ->
  let AilSyntax.AnnotatedExpression(gtc,_,_,_) = e in
  let open GenTypes in
  match gtc with
  | GenRValueType(GenPointer(_,Ctype(_,Struct(s))))
  | GenLValueType(_,Ctype(_,Struct(s)),_)           -> (sym_to_str s, false)
  | GenRValueType(GenPointer(_,Ctype(_,Union(s) )))
  | GenLValueType(_,Ctype(_,Union(s) ),_)           ->(sym_to_str s, true )
  | GenRValueType(_                               ) -> assert false
  | GenLValueType(_,_                 ,_)           -> assert false

let strip_expr (AilSyntax.AnnotatedExpression(_,_,_,e)) = e

let rec function_decls decls =
  let open AilSyntax in
  match decls with
  | []                                                           -> []
  | (id, (_, attrs, Decl_function(_,(_,ty),args,_,_,_))) :: decls ->
      (sym_to_str id, (ty, args, attrs)) :: function_decls decls
  | (_ , (_, _    , Decl_object(_,_,_)                )) :: decls ->
      function_decls decls

let global_fun_decls = ref []
let global_tag_defs = ref []

let tag_def_data : loc -> string -> (string * op_type) list = fun loc id ->
  let fs =
    match List.find (fun (s,_) -> sym_to_str s = id) !global_tag_defs with
    | (_, (_, Ctype.StructDef(fs,_)))
    | (_, (_, Ctype.UnionDef(fs)   )) -> fs
  in
  let fn (s, (_, _, c_ty)) = (id_to_str s, op_type_of loc c_ty) in
  List.map fn fs

let handle_invalid_annot : type a b. ?loc:loc -> b ->  (a -> b) -> a -> b =
    fun ?loc default f a ->
  try f a with Invalid_annot(err_loc, msg) ->
  begin
    match Location.get err_loc with
    | None    ->
        Panic.wrn loc "Invalid annotation (ignored).\n  → %s" msg
    | Some(d) ->
        Panic.wrn None "[%a] Invalid annotation (ignored).\n  → %s"
          Location.pp_data d msg
  end; default

let rec translate_expr lval goal_ty e =
  let open AilSyntax in
  let res_ty = op_type_tc_opt (loc_of e) (tc_of e) in
  let AnnotatedExpression(_, _, loc, e) = e in
  let coq_loc = register_loc coq_locs loc in
  let locate e = mkloc e coq_loc in
  let translate = translate_expr lval None in
  let (e, l) as res =
    match e with
    | AilEunary(Address,e)         ->
        let (e, l) = translate_expr true None e in
        (locate (AddrOf(e)), l)
    | AilEunary(Indirection,e)     -> translate e
    | AilEunary(Plus,e)            -> translate e
    | AilEunary(op,e)              ->
        let ty = op_type_of_tc (loc_of e) (tc_of e) in
        let (e, l) = translate e in
        let op =
          match op with
          | Address     -> assert false (* Handled above. *)
          | Indirection -> assert false (* Handled above. *)
          | Plus        -> assert false (* Handled above. *)
          | Minus       -> NegOp
          | Bnot        -> NotIntOp
          | PostfixIncr -> forbidden loc "nested postfix increment"
          | PostfixDecr -> forbidden loc "nested postfix decrement"
        in
        (locate (UnOp(op, ty, e)), l)
    | AilEbinary(e1,op,e2)         ->
        let ty1 = op_type_of_tc (loc_of e1) (tc_of e1) in
        let ty2 = op_type_of_tc (loc_of e2) (tc_of e2) in
        let arith_op = ref false in
        let op =
          match op with
          | Eq             -> EqOp
          | Ne             -> NeOp
          | Lt             -> LtOp
          | Gt             -> GtOp
          | Le             -> LeOp
          | Ge             -> GeOp
          | And            -> not_impl loc "nested && operator"
          | Or             -> not_impl loc "nested || operator"
          | Comma          -> not_impl loc "binary operator (Comma)"
          | Arithmetic(op) ->
          arith_op := true;
          match op with
          | Mul  -> MulOp | Div  -> DivOp | Mod  -> ModOp | Add  -> AddOp
          | Sub  -> SubOp | Shl  -> ShlOp | Shr  -> ShrOp | Band -> AndOp
          | Bxor -> XorOp | Bor  -> OrOp
        in
        let (goal_ty, ty1, ty2) =
          match (ty1, ty2, res_ty) with
          | (OpInt(_), OpInt(_), Some((OpInt(_) as res_ty))) ->
              if !arith_op then (Some(res_ty), res_ty, res_ty) else
              if ty1 = ty2 then (None, ty1, ty2) else
              not_impl loc "Operand types not uniform for comparing operator."
          | (_       , _       , _                         ) ->
              (None        , ty1   , ty2   )
        in
        let (e1, l1) = translate_expr lval  goal_ty e1 in
        let (e2, l2) = translate_expr false goal_ty e2 in
        (locate (BinOp(op, ty1, ty2, e1, e2)), l1 @ l2)
    | AilEassign(e1,e2)            -> forbidden loc "nested assignment"
    | AilEcompoundAssign(e1,op,e2) -> not_impl loc "expr compound assign"
    | AilEcond(e1,e2,e3)           -> not_impl loc "expr cond"
    | AilEcast(q,c_ty,e)           ->
        begin
          match c_ty with
          | Ctype(_,Pointer(_,Ctype(_,Void))) when is_const_0 e ->
              let AnnotatedExpression(_, _, loc, _) = e in
              ({ elt = Val(Null) ; loc = register_loc coq_locs loc }, [])
          | _                                                   ->
          let ty = op_type_of_tc (loc_of e) (tc_of e) in
          let op_ty = op_type_of loc c_ty in
          let (e, l) = translate e in
          (locate (UnOp(CastOp(op_ty), ty, e)), l)
        end
    | AilEcall(e,es)               ->
        let (fun_loc, fun_id) =
          match ident_of_expr e with
          | None     -> not_impl loc "expr complicated call"
          | Some(id) -> id
        in
        let (_, args, attrs) = List.assoc fun_id !global_fun_decls in
        let attrs = collect_rc_attrs attrs in
        let annot_args =
          handle_invalid_annot ~loc [] function_annot_args attrs
        in
        let nb_args = List.length es in
        let check_useful (i, _, _) =
          if i >= nb_args then
            Panic.wrn (Some(loc))
              "Argument annotation not usable (not enough arguments)."
        in
        List.iter check_useful annot_args;
        let (es, l) =
          let fn i e =
            let (_, ty, _) = List.nth args i in
            match op_type_opt Location_ocaml.unknown ty with
            | Some(OpInt(_)) as goal_ty -> translate_expr lval goal_ty e
            | _                         -> translate e
          in
          let es_ls = List.mapi fn es in
          (List.map fst es_ls, List.concat (List.map snd es_ls))
        in
        let annotate i e =
          let annot_args = List.filter (fun (n, _, _) -> n = i) annot_args in
          let fn (_, k, coq_e) acc = mkloc (AnnotExpr(k, coq_e, e)) e.loc in
          List.fold_right fn annot_args e
        in
        let es = List.mapi annotate es in
        let ret_id = Some(fresh_ret_id ()) in
        Hashtbl.add used_functions fun_id ();
        let e_call =
          mkloc (Var(Some(fun_id), true)) (register_loc coq_locs fun_loc)
        in
        (locate (Var(ret_id, false)), l @ [(coq_loc, ret_id, e_call, es)])
    | AilEassert(e)                -> not_impl loc "expr assert nested"
    | AilEoffsetof(c_ty,is)        -> not_impl loc "expr offsetof"
    | AilEgeneric(e,gas)           -> not_impl loc "expr generic"
    | AilEarray(b,c_ty,oes)        -> not_impl loc "expr array"
    | AilEstruct(sym,fs) when lval -> not_impl loc "Struct initializer not supported in lvalue context"
    | AilEstruct(sym,fs)           ->
        let st_id = sym_to_str sym in
        (* Map of types for the fields. *)
        let map = try tag_def_data loc st_id with Not_found -> assert false in
        let fs =
          let fn (id, eo) = Option.map (fun e -> (id_to_str id, e)) eo in
          List.filter_map fn fs
        in
        let (fs, l) =
          let fn (id, e) (fs, l) =
            let ty = try List.assoc id map with Not_found -> assert false in
            let (e, l_e) = translate_expr lval (Some(ty)) e in
            ((id, e) :: fs, l_e @ l)
          in
          List.fold_right fn fs ([], [])
        in
        (locate (Struct(st_id, fs)), l)
    | AilEunion(sym,id,eo)         -> not_impl loc "expr union"
    | AilEcompound(q,c_ty,e)       -> translate e (* FIXME? *)
    | AilEmemberof(e,id)           ->
        if not lval then assert false;
        let (struct_name, from_union) = struct_data e in
        let (e, l) = translate e in
        (locate (GetMember(e, struct_name, from_union, id_to_str id)), l)
    | AilEmemberofptr(e,id)        ->
        let (struct_name, from_union) = struct_data e in
        let (e, l) = translate e in
        (locate (GetMember(e, struct_name, from_union, id_to_str id)), l)
    | AilEbuiltin(b)               -> not_impl loc "expr builtin"
    | AilEstr(s)                   -> not_impl loc "expr str"
    | AilEconst(c)                 ->
        let c =
          match c with
          | ConstantIndeterminate(c_ty) -> assert false
          | ConstantNull                -> Null
          | ConstantInteger(i)          ->
              begin
                match i with
                | IConstant(i,_,_) ->
                    let it =
                      match res_ty with
                      | Some(OpInt(it)) -> it
                      | _               -> assert false
                    in
                    Int(Z.to_string i, it)
                | _                -> not_impl loc "weird integer constant"
              end
          | ConstantFloating(_)         -> not_impl loc "constant float"
          | ConstantCharacter(_)        -> not_impl loc "constant char"
          | ConstantArray(_,_)          -> not_impl loc "constant array"
          | ConstantStruct(_,_)         -> not_impl loc "constant struct"
          | ConstantUnion(_,_,_)        -> not_impl loc "constant union"
        in
        (locate (Val(c)), [])
    | AilEident(sym)               ->
        let id = sym_to_str sym in
        let global = not (Hashtbl.mem local_vars id) in
        if global then Hashtbl.add used_globals id ();
        (locate (Var(Some(id), global)), [])
    | AilEsizeof(q,c_ty)           -> (locate (Val(SizeOf(layout_of false c_ty))), [])
    | AilEsizeof_expr(e)           -> not_impl loc "expr sizeof_expr"
    | AilEalignof(q,c_ty)          -> not_impl loc "expr alignof"
    | AilEannot(c_ty,e)            -> not_impl loc "expr annot"
    | AilEva_start(e,sym)          -> not_impl loc "expr va_start"
    | AilEva_arg(e,c_ty)           -> not_impl loc "expr va_arg"
    | AilEva_copy(e1,e2)           -> not_impl loc "expr va_copy"
    | AilEva_end(e)                -> not_impl loc "expr va_end"
    | AilEprint_type(e)            -> not_impl loc "expr print_type"
    | AilEbmc_assume(e)            -> not_impl loc "expr bmc_assume"
    | AilEreg_load(r)              -> not_impl loc "expr reg_load"
    | AilErvalue(e)                ->
        let res = match e with
        (* Struct initializers are lvalues for Ail, but rvalues for us. *)
        | AnnotatedExpression(_, _, _, AilEcompound(_, _, _)) -> translate e
        | _ ->
          let layout = layout_of_tc (tc_of e) in
          let atomic = is_atomic_tc (tc_of e) in
          let (e, l) = translate_expr true None e in
          let gen = if lval then Deref(atomic, layout, e) else Use(atomic, layout, e) in
          (locate gen, l)
        in res
    | AilEarray_decay(e)           -> translate e (* FIXME ??? *)
    | AilEfunction_decay(e)        -> not_impl loc "expr function_decay"
  in
  match (goal_ty, res_ty) with
  | (None         , _           )
  | (_            , None        ) -> res
  | (Some(goal_ty), Some(res_ty)) ->
      if goal_ty = res_ty then res
      else (mkloc (UnOp(CastOp(goal_ty), res_ty, e)) e.loc, l)

type bool_expr =
  | BE_leaf of ail_expr
  | BE_neg  of bool_expr
  | BE_and  of bool_expr * bool_expr
  | BE_or   of bool_expr * bool_expr

let rec bool_expr : ail_expr -> bool_expr = fun e ->
  match strip_expr e with
  | AilEbinary(e1,And,e2) -> BE_and(bool_expr e1, bool_expr e2)
  | AilEbinary(e1,Or ,e2) -> BE_or(bool_expr e1, bool_expr e2)
  | AilEbinary(e1,Eq ,e2) ->
      begin
        let be1 = bool_expr e1 in
        let be2 = bool_expr e2 in
        match (is_const_0 e1, be1, is_const_0 e2, be2) with
        | (false, _         , false, _         )
        | (true , _         , true , _         )
        | (false, BE_leaf(_), true , _         )
        | (true , _         , false, BE_leaf(_)) -> BE_leaf(e)
        | (false, _         , true , _         ) -> BE_neg(be1)
        | (true , _         , false, _         ) -> BE_neg(be2)
      end
  | _                     -> BE_leaf(e)

type op_ty_opt = Coq_ast.op_type option

let trans_expr : ail_expr -> op_ty_opt -> (expr -> stmt) -> stmt =
    fun e goal_ty e_stmt ->
  let (e, calls) = translate_expr false goal_ty e in
  let fn (loc, id, e, es) stmt =
    mkloc (Call(id, e, es, stmt)) loc
  in
  List.fold_right fn calls (e_stmt e)

let trans_bool_expr : ail_expr -> (expr -> stmt) -> stmt = fun e e_stmt ->
  trans_expr e (Some(OpInt(ItBool))) e_stmt

let translate_bool_expr then_goto else_goto blocks e =
  let rec translate then_goto else_goto blocks be =
    match be with
    | BE_leaf(e)      ->
        let fn e = mkloc (If(e, then_goto, else_goto)) e.loc in
        (trans_bool_expr e fn, blocks)
    | BE_neg(be)      ->
        translate else_goto then_goto blocks be
    | BE_and(be1,be2) ->
        let id = fresh_block_id () in
        let id_goto = noloc (Goto(id)) in (* FIXME loc *)
        let (s, blocks) = translate id_goto else_goto blocks be1 in
        let blocks =
          let (s, blocks) = translate then_goto else_goto blocks be2 in
          SMap.add id (Some(no_block_annot), s) blocks
        in
        (s, blocks)
    | BE_or (be1,be2) ->
        let id = fresh_block_id () in
        let id_goto = noloc (Goto(id)) in (* FIXME loc *)
        let (s, blocks) = translate then_goto id_goto blocks be1 in
        let blocks =
          let (s, blocks) = translate then_goto else_goto blocks be2 in
          SMap.add id (Some(no_block_annot), s) blocks
        in
        (s, blocks)
  in
  translate then_goto else_goto blocks (bool_expr e)

let trans_lval e : expr =
  let (e, calls) = translate_expr true None e in
  if calls <> [] then assert false; e

(* Insert local variables. *)
let insert_bindings bindings =
  let fn (id, ((loc, _, _), _, c_ty)) =
    let id = sym_to_str id in
    if Hashtbl.mem local_vars id then
      not_impl loc "Variable name collision with [%s]." id;
    Hashtbl.add local_vars id (true, c_ty)
  in
  List.iter fn bindings

let collect_bindings () =
  let fn id (is_var, c_ty) acc =
    if is_var then (id, layout_of false c_ty) :: acc else acc
  in
  Hashtbl.fold fn local_vars []

let warn_ignored_attrs so attrs =
  let pp_rc ff {rc_attr_id = id; rc_attr_args = args} =
    Format.fprintf ff "%s(" id.elt;
    match args with
    | arg :: args ->
        let open Location in
        Format.fprintf ff "%s" arg.elt;
        List.iter (fun arg -> Format.fprintf ff ", %s" arg.elt) args;
        Format.fprintf ff ")"
    | []          ->
        Format.fprintf ff ")"
  in
  let fn attr =
    let desc s =
      let open AilSyntax in
      match s with
      | AilSblock(_,_)     -> "a block"
      | AilSgoto(_)        -> "a goto"
      | AilSreturnVoid
      | AilSreturn(_)      -> "a return"
      | AilSbreak          -> "a break"
      | AilScontinue       -> "a continue"
      | AilSskip           -> "a skip"
      | AilSexpr(_)        -> "an expression"
      | AilSif(_,_,_)      -> "an if statement"
      | AilSwhile(_,_)     -> "a while loop"
      | AilSdo(_,_)        -> "a do-while loop"
      | AilSswitch(_,_)    -> "a switch statement"
      | AilScase(_,_)      -> "a case statement"
      | AilSdefault(_)     -> "a default statement"
      | AilSlabel(_,_)     -> "a label"
      | AilSdeclaration(_) -> "a declaration"
      | AilSpar(_)         -> "a par statement"
      | AilSreg_store(_,_) -> "a register store statement"
    in
    let desc =
      match so with
      | Some(s) -> Printf.sprintf " (on %s)" (desc s)
      | None    -> " (on an outer block)"
    in
    Panic.wrn None "Ignored attribute [%a]%s." pp_rc attr desc
  in
  List.iter fn attrs

let translate_block stmts blocks ret_ty =
  let rec trans extra_attrs break continue final stmts blocks =
    let open AilSyntax in
    let resume goto = match goto with None -> assert false | Some(s) -> s in
    (* End of the block reached. *)
    match stmts with
    | []                                           -> (resume final, blocks)
    | (AnnotatedStatement(loc, attrs, s)) :: stmts ->
    let coq_loc = register_loc coq_locs loc in
    let locate e = mkloc e coq_loc in
    let attrs = List.rev (collect_rc_attrs attrs) in
    let attrs_used = ref false in
    let res =
      match s with
      (* Nested block. *)
      | AilSblock(bs, ss)   ->
          insert_bindings bs;
          attrs_used := true; (* Will be attach to the first loop we find. *)
          trans (extra_attrs @ attrs) break continue final (ss @ stmts) blocks
      (* End of block stuff, assuming [stmts] is empty. *)
      | AilSgoto(l)         -> (locate (Goto(sym_to_str l)), blocks)
      | AilSreturnVoid      ->
          (locate (Return(noloc (Val(Void)))), blocks)
      | AilSbreak           -> (resume break      , blocks)
      | AilScontinue        -> (resume continue   , blocks)
      | AilSreturn(e)       ->
          let goal_ty =
            match ret_ty with
            | Some(OpInt(_)) -> ret_ty
            | _              -> None
          in
          (trans_expr e goal_ty (fun e -> locate (Return(e))), blocks)
      (* All the other constructors. *)
      | AilSskip            ->
          trans extra_attrs break continue final stmts blocks
      | AilSexpr(e)         ->
          let (stmt, blocks) =
            trans extra_attrs break continue final stmts blocks
          in
          let incr_or_decr op = op = PostfixIncr || op = PostfixDecr in
          let stmt =
            match strip_expr e with
            | AilEassert(e)                        ->
                trans_bool_expr e (fun e -> locate (Assert(e, stmt)))
            | AilEassign(e1,e2)                    ->
                let atomic = is_atomic_tc (tc_of e1) in
                let e1 = trans_lval e1 in
                let layout = layout_of_tc (tc_of e) in
                let goal_ty =
                  let ty_opt = op_type_tc_opt (loc_of e) (tc_of e) in
                  match ty_opt with
                  | Some(OpInt(_)) -> ty_opt
                  | _              -> None
                in
                let fn e2 = locate (Assign(atomic, layout, e1, e2, stmt)) in
                trans_expr e2 goal_ty fn
            | AilEunary(op,e) when incr_or_decr op ->
                let atomic = is_atomic_tc (tc_of e) in
                let layout = layout_of_tc (tc_of e) in
                let int_ty =
                  let ty_opt = op_type_tc_opt (loc_of e) (tc_of e) in
                  match ty_opt with
                  | Some(OpInt(int_ty)) -> int_ty
                  | _                   -> assert false (* Badly typed. *)
                in
                let op = match op with PostfixIncr -> AddOp | _ -> SubOp in
                let e1 = trans_lval e in
                let e2 =
                  let one = locate (Val(Int("1", int_ty))) in
                  let use = locate (Use(atomic, layout, e1)) in
                  locate (BinOp(op, OpInt(int_ty), OpInt(int_ty), use, one))
                in
                locate (Assign(atomic, layout, e1, e2, stmt))
            | AilEcall(_,_)                        ->
                let (stmt, calls) =
                  match snd (translate_expr false None e) with
                  | []                  -> assert false
                  | (_,_,e,es) :: calls ->
                      (locate (Call(None, e, es, stmt)), calls)
                in
                let fn (loc, id, e, es) stmt =
                  mkloc (Call(id, e, es, stmt)) loc
                in
                List.fold_right fn calls stmt
            | _                                    ->
                attrs_used := true;
                let annots =
                  let fn () = Some(expr_annot attrs) in
                  handle_invalid_annot ~loc None fn ()
                in
                trans_expr e None (fun e -> locate (ExprS(annots, e, stmt)))
          in
          (stmt, blocks)
      | AilSif(e,s1,s2)     ->
          warn_ignored_attrs None extra_attrs;
          (* Translate the continuation. *)
          let (blocks, final) =
            if stmts = [] then (blocks, final) else
            let id_cont = fresh_block_id () in
            let (s, blocks) = trans [] break continue final stmts blocks in
            let blocks = SMap.add id_cont (Some(no_block_annot), s) blocks in
            (blocks, Some(mkloc (Goto(id_cont)) s.loc))
          in
          (* Translate the two branches. *)
          let (blocks, then_goto) =
            let id_then = fresh_block_id () in
            let (s, blocks) = trans [] break continue final [s1] blocks in
            let blocks = SMap.add id_then (Some(no_block_annot), s) blocks in
            (blocks, mkloc (Goto(id_then)) s.loc)
          in
          let (blocks, else_goto) =
            let id_else = fresh_block_id () in
            let (s, blocks) = trans [] break continue final [s2] blocks in
            let blocks = SMap.add id_else (Some(no_block_annot), s) blocks in
            (blocks, mkloc (Goto(id_else)) s.loc)
          in
          translate_bool_expr then_goto else_goto blocks e
      | AilSwhile(e,s)      ->
          let attrs = extra_attrs @ attrs in
          let id_cond = fresh_block_id () in
          let id_body = fresh_block_id () in
          (* Translate the continuation. *)
          let (blocks, goto_cont) =
            let id_cont = fresh_block_id () in
            let (s, blocks) = trans [] break continue final stmts blocks in
            let blocks = SMap.add id_cont (Some(no_block_annot), s) blocks in
            (blocks, mkloc (Goto(id_cont)) s.loc)
          in
          (* Translate the body. *)
          let (blocks, goto_body) =
            let break    = Some(goto_cont) in
            let continue = Some(locate (Goto(id_cond))) in
            let (s, blocks) = trans [] break continue continue [s] blocks in
            let blocks = SMap.add id_body (Some(no_block_annot), s) blocks in
            (blocks, mkloc (Goto(id_body)) s.loc)
          in
          (* Translate the condition. *)
          let (s, blocks) =
            translate_bool_expr goto_body goto_cont blocks e
          in
          let blocks =
            let annot =
              attrs_used := true;
              let fn () = Some(block_annot attrs) in
              handle_invalid_annot ~loc None fn ()
            in
            SMap.add id_cond (annot, s) blocks
          in
          (locate (Goto(id_cond)), blocks)
      | AilSdo(s,e)         ->
          let attrs = extra_attrs @ attrs in
          let id_cond = fresh_block_id () in
          let id_body = fresh_block_id () in
          (* Translate the continuation. *)
          let (blocks, goto_cont) =
            let id_cont = fresh_block_id () in
            let (s, blocks) = trans [] break continue final stmts blocks in
            let blocks = SMap.add id_cont (Some(no_block_annot), s) blocks in
            (blocks, mkloc (Goto(id_cont)) s.loc)
          in
          (* Translate the body. *)
          let (blocks, goto_body) =
            let break    = Some(goto_cont) in
            let continue = Some(noloc (Goto(id_cond))) in (* FIXME loc *)
            let (s, blocks) = trans [] break continue continue [s] blocks in
            let blocks = SMap.add id_body (Some(no_block_annot), s) blocks in
            (blocks, locate (Goto(id_body)))
          in
          (* Translate the condition. *)
          let (s, blocks) = translate_bool_expr goto_body goto_cont blocks e in
          let blocks =
            let annot =
              attrs_used := true;
              let fn () = Some(block_annot attrs) in
              handle_invalid_annot ~loc None fn ()
            in
            SMap.add id_cond (annot, s) blocks
          in
          (locate (Goto(id_body)), blocks)
      | AilSswitch(_,_)     -> not_impl loc "statement switch"
      | AilScase(_,_)       -> not_impl loc "statement case"
      | AilSdefault(_)      -> not_impl loc "statement default"
      | AilSlabel(l,s)      ->
          let (stmt, blocks) =
            trans extra_attrs break continue final (s :: stmts) blocks
          in
          let blocks =
            SMap.add (sym_to_str l) (Some(no_block_annot), stmt) blocks
          in
          (locate (Goto(sym_to_str l)), blocks)
      | AilSdeclaration(ls) ->
          let (stmt, blocks) =
            trans extra_attrs break continue final stmts blocks
          in
          let add_decl (id, e) stmt =
            let id = sym_to_str id in
            let ty =
              try snd (Hashtbl.find local_vars id)
              with Not_found -> assert false
            in
            let layout = layout_of false ty in
            let atomic = is_atomic ty in
            let goal_ty = op_type_opt Location_ocaml.unknown ty in
            let fn e =
              let var = noloc (Var(Some(id), false)) in
              noloc (Assign(atomic, layout, var, e, stmt))
            in
            trans_expr e goal_ty fn
          in
          (List.fold_right add_decl ls stmt, blocks)
      | AilSpar(_)          -> not_impl loc "statement par"
      | AilSreg_store(_,_)  -> not_impl loc "statement store"
    in
    if not !attrs_used then warn_ignored_attrs (Some(s)) attrs;
    res
  in
  trans [] None None (Some(noloc (Return(noloc (Val(Void)))))) stmts blocks

(** [translate fname ail] translates typed Ail AST to Coq AST. *)
let translate : string -> typed_ail -> Coq_ast.t = fun source_file ail ->
  (* Get the entry point. *)
  let (entry_point, sigma) =
    match ail with
    | (None    , sigma) -> (None               , sigma)
    | (Some(id), sigma) -> (Some(sym_to_str id), sigma)
  in

  (* Extract the different parts of the AST. *)
  let decls      = sigma.declarations         in
  (*let obj_defs   = sigma.object_definitions   in*)
  let fun_defs   = sigma.function_definitions in
  (*let assertions = sigma.static_assertions    in*)
  let tag_defs   = sigma.tag_definitions      in
  (*let ext_idmap  = sigma.extern_idmap         in*)

  (* Give global access to declarations. *)
  let fun_decls = function_decls decls in
  global_fun_decls := fun_decls;

  (* Give global access to tag declarations *)
  global_tag_defs := tag_defs;

  (* Get the global variables. *)
  let global_vars =
    let fn (id, (_, attrs, decl)) acc =
      match decl with
      | AilSyntax.Decl_object _ ->
         let annots = collect_rc_attrs attrs in
         let fn () = global_annot annots in
         let global_annot = handle_invalid_annot None fn () in
         (sym_to_str id, global_annot) :: acc
      | _                       -> acc
    in
    List.fold_right fn decls []
  in

  (* Get the definition of structs/unions. *)
  let structs =
    let build (id, (attrs, def)) =
      let (fields, struct_is_union) =
        match def with
        | Ctype.StructDef(fields,_) -> (fields, false)
        | Ctype.UnionDef(fields)    -> (fields, true )
      in
      let id = sym_to_str id in
      let struct_annot =
        let attrs = collect_rc_attrs attrs in
        if struct_is_union && attrs <> [] then
          Panic.wrn None "Attributes on unions like [%s] are ignored." id;
        if struct_is_union then Some(SA_union) else
        handle_invalid_annot None (fun _ -> Some(struct_annot attrs)) ()
      in
      let struct_members =
        let fn (id, (attrs, loc, c_ty)) =
          let ty =
            let loc = loc_of_id id in
            let annots = collect_rc_attrs attrs in
            let fn () = Some(member_annot annots) in
            handle_invalid_annot ~loc None fn ()
          in
          (id_to_str id, (ty, layout_of false c_ty))
        in
        List.map fn fields
      in
      let struct_deps =
        let fn acc (_, (_, layout)) =
          let rec extend acc layout =
            match layout with
            | LVoid         -> acc
            | LPtr          -> acc
            | LStruct(id,_) -> id :: acc
            | LInt(_)       -> acc
            | LArray(l,_)   -> extend acc l
          in
          extend acc layout
        in
        List.rev (List.fold_left fn [] struct_members)
      in
      let struct_ =
        { struct_name = id ; struct_annot ; struct_deps
        ; struct_is_union ; struct_members }
      in
      (id, struct_)
    in
    List.map build tag_defs
  in

  (* Get the definition of functions. *)
  let functions =
    let open AilSyntax in
    let build (func_name, (ret_ty, args_decl, attrs)) =
      (* Initialise all state. *)
      Hashtbl.reset local_vars; reset_ret_id (); reset_block_id ();
      Hashtbl.reset used_globals; Hashtbl.reset used_functions;
      (* Fist parse that annotations. *)
      let func_annot =
        let fn () = Some(function_annot (collect_rc_attrs attrs)) in
        handle_invalid_annot None fn ()
      in
      (* Then find out if the function is defined or just declared. *)
      match List.find (fun (id, _) -> sym_to_str id = func_name) fun_defs with
      | exception Not_found                                       ->
          (* Function is only declared. *)
          (func_name, FDec(func_annot))
      | (_, (_, _, args, AnnotatedStatement(loc, s_attrs, stmt))) ->
      (* Function is defined. *)
      let func_args =
        let fn i (_, c_ty, _) =
          let id = sym_to_str (List.nth args i) in
          Hashtbl.add local_vars id (false, c_ty);
          (id, layout_of true c_ty)
        in
        List.mapi fn args_decl
      in
      let _ =
        (* Collection top level local variables. *)
        match stmt with
        | AilSblock(bindings, _) -> insert_bindings bindings
        | _                      -> not_impl loc "Body not a block."
      in
      let func_init = fresh_block_id () in
      let func_blocks =
        let stmts =
          match stmt with
          | AilSblock(_, stmts) -> stmts
          | _                   -> not_impl loc "Body not a block."
        in
        let ret_ty = op_type_opt Location_ocaml.unknown ret_ty in
        let (stmt, blocks) = translate_block stmts SMap.empty ret_ty in
        let annots =
          let fn () =
            Some(block_annot (List.rev (collect_rc_attrs s_attrs)))
          in
          handle_invalid_annot None fn ()
        in
        SMap.add func_init (annots, stmt) blocks
      in
      let func_vars = collect_bindings () in
      let func_deps =
        let globals_used =
          (* We preserve order of declaration. *)
          List.filter (Hashtbl.mem used_globals) (List.map fst global_vars)
        in
        let func_used =
          (* We preserve order of declaration. *)
          let potential = List.map (fun (id, _) -> sym_to_str id) decls in
          List.filter (Hashtbl.mem used_functions) potential
        in
        (globals_used, func_used)
      in
      let func =
        { func_name ; func_annot ; func_args ; func_vars ; func_init
        ; func_deps ; func_blocks }
      in
      (func_name, FDef(func))
    in
    List.map build fun_decls
  in

  { source_file ; entry_point ; global_vars ; structs ; functions }
