module LS = LogicalSorts
module BT = BaseTypes
module SymSet = Set.Make(Sym)
module TE = TypeErrors
module RE = Resources.RE
module AT = ArgumentTypes

open Global
open TE
open Pp



module Make
         (G : sig val global : Global.t end)
         (S : Solver.S) 
         (L : Local.S)
  = struct
  module E = Explain.Make(G)(S)(L)
  
  module Typing = Typing.Make(L)
  open Typing
  open Effectful.Make(Typing)

  module WIT = struct


    let check_bound loc kind s = 
      let@ is_bound = bound s kind in
      if is_bound then return ()
      else fail loc (TE.Unbound_name (Sym s))


    let illtyped_index_term context it has expected =
      fun explain_local ->
      let (context_pp, it_pp) = E.illtyped_index_term explain_local context it in
      TypeErrors.Illtyped_it {context = context_pp; it = it_pp; 
                              has; expected = "integer or real"}


    let ensure_integer_or_real_type loc context it = 
      let open BT in
      match IT.bt it with
      | (Integer | Real) -> return ()
      | _ -> 
         let expect = "integer or real type" in
         failS loc (illtyped_index_term context it (IT.bt it) expect)

    let ensure_set_type loc context it = 
      let open BT in
      match IT.bt it with
      | Set bt -> return bt
      | _ -> failS loc (illtyped_index_term context it (IT.bt it) "set type")

    let ensure_list_type loc context it = 
      let open BT in
      match IT.bt it with
      | List bt -> return bt
      | _ -> failS loc (illtyped_index_term context it (IT.bt it) "list type")

    let ensure_array_type loc context it = 
      let open BT in
      match IT.bt it with
      | Array (abt, rbt) -> return (abt, rbt)
      | _ -> failS loc (illtyped_index_term context it (IT.bt it) "array type")

    let ensure_option_type loc context it = 
      let open BT in
      match IT.bt it with
      | Option bt -> return bt
      | _ -> failS loc (illtyped_index_term context it (IT.bt it) "option type")

    let get_struct_decl loc tag = 
      match SymMap.find_opt tag G.global.struct_decls with
      | Some decl -> return decl
      | None -> fail loc (Missing_struct tag)

    open BaseTypes
    open LogicalSorts
    open IndexTerms

    type t = IndexTerms.t


    let rec infer : 'bt. Loc.t -> context:(BT.t IT.term) -> 'bt IT.term -> IT.t m =
        fun loc ~context (IT (it, _)) ->
        match it with
        | Lit lit ->
           let@ (bt, lit) = match lit with
             | Sym s ->
                let@ () = check_bound loc KLogical s in
                let@ bt = get_l s in
                return (bt, Sym s)
             | Z z -> 
                return (Integer, Z z)
             | Q (n,n') -> 
                return (Real, Q (n,n'))
             | Pointer p -> 
                return (Loc, Pointer p)
             | Bool b -> 
                return (BT.Bool, Bool b)
             | Unit -> 
                return (BT.Unit, Unit)
             | Default bt -> 
                return (bt, Default bt)
           in
           return (IT (Lit lit, bt))
        | Arith_op arith_op ->
           let@ (bt, arith_op) = match arith_op with
             | Add (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (IT.bt t, Add (t, t'))
             | Sub (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (IT.bt t, Sub (t, t'))
             | Mul (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (IT.bt t, Mul (t, t'))
             | Div (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (IT.bt t, Div (t, t'))
             | Exp (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (IT.bt t, Exp (t, t'))
             | Rem (t,t') ->
                let@ t = check loc ~context Integer t in
                let@ t' = check loc ~context Integer t' in
                return (Integer, Rem (t, t'))
           in
           return (IT (Arith_op arith_op, bt))
        | Cmp_op cmp_op ->
           let@ (bt, cmp_op) = match cmp_op with
             | LT (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (BT.Bool, LT (t, t'))
             | LE (t,t') ->
                let@ t = infer loc ~context t in
                let@ () = ensure_integer_or_real_type loc context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (BT.Bool, LE (t, t'))
           in
           return (IT (Cmp_op cmp_op, bt))
        | Bool_op bool_op ->
           let@ (bt, bool_op) = match bool_op with
             | And ts ->
                let@ ts = ListM.mapM (check loc ~context Bool) ts in
                return (BT.Bool, And ts)
             | Or ts ->
                let@ ts = ListM.mapM (check loc ~context Bool) ts in
                return (BT.Bool, Or ts)
             | Impl (t,t') ->
                let@ t = check loc ~context Bool t in
                let@ t' = check loc ~context Bool t' in
                return (BT.Bool, Impl (t, t'))
             | Not t ->
                let@ t = check loc ~context Bool t in
                return (BT.Bool, Not t)
             | ITE (t,t',t'') ->
                let@ t = check loc ~context Bool t in
                let@ t' = infer loc ~context t' in
                let@ t'' = check loc ~context (IT.bt t') t'' in
                return (IT.bt t', ITE (t, t', t''))
             | EQ (t,t') ->
                let@ t = infer loc ~context t in
                let@ t' = check loc ~context (IT.bt t) t' in
                return (BT.Bool, EQ (t,t')) 
           in
           return (IT (Bool_op bool_op, bt))
        | Tuple_op tuple_op ->
           let@ (bt, tuple_op) = match tuple_op with
             | Tuple ts ->
                let@ ts = ListM.mapM (infer loc ~context) ts in
                let bts = List.map IT.bt ts in
                return (BT.Tuple bts, Tuple ts)
             | NthTuple (n, t') ->
                let@ t' = infer loc ~context t' in
                let@ item_bt = match IT.bt t' with
                  | Tuple bts ->
                     begin match List.nth_opt bts n with
                     | Some t -> return t
                     | None -> 
                        failS loc (fun explain_local ->
                            let (context_pp, t'_pp) = E.illtyped_index_term explain_local context t' in
                            Generic
                              (!^"Illtyped expression" ^^^ context_pp ^^ dot ^^^
                                 !^"Expected" ^^^ t'_pp ^^^ !^"to be tuple with at least" ^^^ !^(string_of_int n) ^^^
                                   !^"components, but has type" ^^^ BT.pp (Tuple bts))
                          )
                     end
                  | _ -> 
                     failS loc (fun explain_local ->
                         let (context_pp, t'_pp) = E.illtyped_index_term explain_local context t' in
                         Generic
                           (!^"Illtyped expression" ^^^ context_pp ^^ dot ^^^
                              !^"Expected" ^^^ t'_pp ^^^ !^"to have tuple type, but has type" ^^^
                                BT.pp (IT.bt t'))
                       )
                in
                return (item_bt, NthTuple (n, t'))
           in
           return (IT (Tuple_op tuple_op, bt))
        | Struct_op struct_op ->
           let@ (bt, struct_op) = match struct_op with
             | Struct (tag, members) ->
                let@ layout = get_struct_decl loc tag in
                let decl_members = Memory.member_types layout in
                let@ () = 
                  let has = List.length members in
                  let expect = List.length decl_members in
                  if has = expect then return ()
                  else fail loc (Number_members {has; expect})
                in
                let@ members = 
                  ListM.mapM (fun (member,t) ->
                      let@ bt = match List.assoc_opt Id.equal member decl_members with
                        | Some sct -> return (BT.of_sct sct)
                        | None -> 
                           failS loc (fun explain_local ->
                               let context_pp = E.index_term explain_local context in
                               Generic
                                 (!^"Illtyped expression" ^^^ context_pp ^^ dot ^^^
                                    !^"struct" ^^^ Sym.pp tag ^^^ !^"does not have member" ^^^ Id.pp member)
                             )
                      in
                      let@ t = check loc ~context bt t in
                      return (member, t)
                    ) members
                in
                return (BT.Struct tag, Struct (tag, members))
             | StructMember (t, member) ->
                let@ t = infer loc ~context t in
                let@ tag = match IT.bt t with
                  | Struct tag -> return tag
                  | _ -> 
                     failS loc (fun explain_local ->
                         let (context_pp, t_pp) = E.illtyped_index_term explain_local context t in
                         Generic (!^"Illtyped expression" ^^^ context_pp ^^ dot ^^^
                                    !^"Expected" ^^^ t_pp ^^^ !^"to have struct type" ^^^ 
                                      !^"but has type" ^^^ BT.pp (IT.bt t))
                       )
                in
                let@ layout = get_struct_decl loc tag in
                let decl_members = Memory.member_types layout in
                let@ bt = match List.assoc_opt Id.equal member decl_members with
                  | Some sct -> return (BT.of_sct sct)
                  | None -> 
                     failS loc (fun explain_local ->
                         let (context_pp, t_pp) = E.illtyped_index_term explain_local context t in
                         Generic
                           (!^"Illtyped expression" ^^^ context_pp ^^ dot ^^^
                              t_pp ^^^ !^"does not have member" ^^^ Id.pp member)
                       )
                in
                return (bt, StructMember (t, member))
           in
           return (IT (Struct_op struct_op, bt))
        | Pointer_op pointer_op ->
           let@ (bt, pointer_op) = match pointer_op with 
             | Null ->
                return (BT.Loc, Null)
             | AddPointer (t, t') ->
                let@ t = check loc ~context Loc t in
                let@ t' = check loc ~context Integer t' in
                return (Loc, AddPointer (t, t'))
             | SubPointer (t, t') ->
                let@ t = check loc ~context Loc t in
                let@ t' = check loc ~context Integer t' in
                return (Loc, SubPointer (t, t'))
             | MulPointer (t, t') ->
                let@ t = check loc ~context Loc t in
                let@ t' = check loc ~context Integer t' in
                return (Loc, MulPointer (t, t'))
             | LTPointer (t, t') ->
                let@ t = check loc ~context Loc t in
                let@ t' = check loc ~context Loc t' in
                return (BT.Bool, LTPointer (t, t'))
             | LEPointer (t, t') ->
                let@ t = check loc ~context Loc t in
                let@ t' = check loc ~context Loc t' in
                return (BT.Bool, LEPointer (t, t'))
             | IntegerToPointerCast t ->
                let@ t = check loc ~context Integer t in
                return (Loc, IntegerToPointerCast t)
             | PointerToIntegerCast t ->
                let@ t = check loc ~context Loc t in
                return (Integer, PointerToIntegerCast t)
             | MemberOffset (tag, member) ->
                return (Integer, MemberOffset (tag, member))
             | ArrayOffset (ct, t) ->
                let@ t = check loc ~context Integer t in
                return (Integer, ArrayOffset (ct, t))
           in
           return (IT (Pointer_op pointer_op, bt))
        | CT_pred ct_pred ->
           let@ (bt, ct_pred) = match ct_pred with
             | AlignedI t ->
                let@ t_t = check loc ~context Loc t.t in
                let@ t_align = check loc ~context Integer t.align in
                return (BT.Bool, AlignedI {t = t_t; align=t_align})
             | Aligned (t, ct) ->
                let@ t = check loc ~context Loc t in
                return (BT.Bool, Aligned (t, ct))
             | Representable (ct, t) ->
                let@ t = check loc ~context (BT.of_sct ct) t in
                return (BT.Bool, Representable (ct, t))
           in
           return (IT (CT_pred ct_pred, bt))
        | List_op list_op ->
           let@ (bt, list_op) = match list_op with
             | Nil -> 
                fail loc (Polymorphic_it context)
             | Cons (t1,t2) ->
                let@ t1 = infer loc ~context t1 in
                let@ t2 = check loc ~context (List (IT.bt t1)) t2 in
                return (BT.List (IT.bt t1), Cons (t1, t2))
             | List [] ->
                fail loc (Polymorphic_it context)
             | List (t :: ts) ->
                let@ t = infer loc ~context t in
                let@ ts = ListM.mapM (check loc ~context (IT.bt t)) ts in
                return (BT.List (IT.bt t), List (t :: ts))
             | Head t ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_list_type loc context t in
                return (bt, Head t)
             | Tail t ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_list_type loc context t in
                return (BT.List bt, Tail t)
             | NthList (i, t) ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_list_type loc context t in
                return (bt, NthList (i, t))
           in
           return (IT (List_op list_op, bt))
        | Set_op set_op ->
           let@ (bt, set_op) = match set_op with
             | SetMember (t,t') ->
                let@ t = infer loc ~context t in
                let@ t' = check loc ~context (Set (IT.bt t)) t' in
                return (BT.Bool, SetMember (t, t'))
             | SetUnion its ->
                let (t, ts) = List1.dest its in
                let@ t = infer loc ~context t in
                let@ itembt = ensure_set_type loc context t in
                let@ ts = ListM.mapM (check loc ~context (Set itembt)) ts in
                return (Set itembt, SetUnion (List1.make (t, ts)))
             | SetIntersection its ->
                let (t, ts) = List1.dest its in
                let@ t = infer loc ~context t in
                let@ itembt = ensure_set_type loc context t in
                let@ ts = ListM.mapM (check loc ~context (Set itembt)) ts in
                return (Set itembt, SetIntersection (List1.make (t, ts)))
             | SetDifference (t, t') ->
                let@ t  = infer loc ~context t in
                let@ itembt = ensure_set_type loc context t in
                let@ t' = check loc ~context (Set itembt) t' in
                return (Set itembt, SetDifference (t, t'))
             | Subset (t, t') ->
                let@ t = infer loc ~context t in
                let@ itembt = ensure_set_type loc context t in
                let@ t' = check loc ~context (Set itembt) t' in
                return (BT.Bool, Subset (t,t'))
           in
           return (IT (Set_op set_op, bt))
        | Option_op option_op ->
           let@ (bt, option_op) = match option_op with
             | Something t ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_option_type loc context t in
                return (BT.Option bt, Something t)
             | Nothing bt ->
                return (BT.Option bt, Nothing bt)
             | Is_some t ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_option_type loc context t in
                return (BT.Bool, Is_some t)
             | Value_of_some t ->
                let@ t = infer loc ~context t in
                let@ bt = ensure_option_type loc context t in
                return (bt, Value_of_some t)
           in
           return (IT (Option_op option_op, bt))
        | Array_op array_op -> 
           let@ (bt, array_op) = match array_op with
             | Const (index_bt, t) ->
                let@ t = infer loc ~context t in
                return (BT.Array (index_bt, IT.bt t), Const (index_bt, t))
             | Mod (t1, t2, t3) ->
                let@ t2 = infer loc ~context t2 in
                let@ t3 = infer loc ~context t3 in
                let bt = BT.Array (IT.bt t2, IT.bt t3) in
                let@ t1 = check loc ~context bt t1 in
                return (bt, Mod (t1, t2, t3))
             | App (t, arg) -> 
                let@ t = infer loc ~context t in
                let@ (abt, bt) = ensure_array_type loc context t in
                let@ arg = check loc ~context abt arg in
                return (bt, App (t, arg))
           in
           return (IT (Array_op array_op, bt))

      and check : 'bt. Loc.t -> context:(BT.t IT.term) -> LS.t -> 'bt IT.term -> IT.t m =
        fun loc ~context ls it ->
        match it, ls with
        | IT (List_op Nil, _), List bt ->
           return (IT (List_op Nil, BT.List bt))
        | _, _ ->
           let@ it = infer loc ~context it in
           if LS.equal ls (IT.bt it) then
             return it
           else
             failS loc (fun explain_local ->
                 let (context_pp, it_pp) = E.illtyped_index_term explain_local context it in
                 Illtyped_it {context = context_pp; it = it_pp; 
                              has = IT.bt it; expected = Pp.plain (LS.pp ls)}
               )

    let infer loc it = 
      pure (infer loc ~context:it it)

    let check loc ls it = 
      pure (check loc ~context:it ls it)

  end


  module WRE = struct

    open Resources.RE

    let get_predicate_def loc name = 
      match Global.get_predicate_def G.global name with
      | Some def -> return def
      | None -> fail loc (Missing_predicate name)
      
    let ensure_same_argument_number loc input_output has ~expect =
      if has = expect then return () else 
        match input_output with
        | `Input -> fail loc (Number_input_arguments {has; expect})
        | `Output -> fail loc (Number_input_arguments {has; expect})
        
    let welltyped loc resource = 
      pure begin match resource with
        | Point b -> 
           let@ _ = WIT.check loc BT.Loc b.pointer in
           let@ _ = WIT.infer loc b.value in
           let@ _ = WIT.check loc BT.Bool b.init in
           let@ _ = WIT.check loc BT.Real b.permission in
           return ()
        | QPoint b -> 
           let@ () = add_l b.qpointer Loc in
           let@ _ = WIT.infer loc b.value in
           let@ _ = WIT.check loc BT.Bool b.init in
           let@ _ = WIT.check loc BT.Real b.permission in
           return ()
        | Predicate p -> 
           let@ def = get_predicate_def loc p.name in
           let has_iargs, expect_iargs = List.length p.iargs, List.length def.iargs in
           let has_oargs, expect_oargs = List.length p.oargs, List.length def.oargs in
           let@ () = ensure_same_argument_number loc `Input has_iargs ~expect:expect_iargs in
           let@ () = ensure_same_argument_number loc `Output has_oargs ~expect:expect_oargs in
           let@ _ = WIT.check loc BT.Loc p.pointer in
           let@ _ = 
             ListM.mapM (fun (arg, expected_sort) ->
                 WIT.check loc expected_sort arg
               ) (List.combine (p.iargs @ p.oargs) 
                 (List.map snd def.iargs @ List.map snd def.oargs))
           in
           let@ _ = WIT.check loc BT.Real p.permission in
           return ()
        | QPredicate p -> 
           let@ def = get_predicate_def loc p.name in
           let has_iargs, expect_iargs = List.length p.iargs, List.length def.iargs in
           let has_oargs, expect_oargs = List.length p.oargs, List.length def.oargs in
           let@ () = ensure_same_argument_number loc `Input has_iargs ~expect:expect_iargs in
           let@ () = ensure_same_argument_number loc `Output has_oargs ~expect:expect_oargs in
           let@ () = add_l p.qpointer Loc in
           let@ _ = 
             ListM.mapM (fun (arg, expected_sort) ->
                 WIT.check loc expected_sort arg
               ) (List.combine (p.iargs @ p.oargs) 
                 (List.map snd def.iargs @ List.map snd def.oargs))
           in
           let@ _ = WIT.check loc BT.Real p.permission in
           return ()
        end


    let resource_mode_check loc infos undetermined resource = 
      let free_inputs = 
        SymSet.diff (IT.free_vars_list (RE.inputs resource)) 
          (RE.bound resource)
      in
      let@ () = match SymSet.elements (SymSet.inter free_inputs undetermined) with
        | [] -> return ()
        | lvar :: _ -> 
           let (loc, odescr) = SymMap.find lvar infos in
           fail loc (Unconstrained_logical_variable (lvar, odescr))
      in
      let@ fixed = 
        ListM.fold_leftM (fun fixed output ->
            (* if the logical variables in the outputs are already determined, ok *)
            if SymSet.is_empty (SymSet.inter (IT.free_vars output) undetermined) 
            then return fixed else
              (* otherwise, check that there is a single unification
                 variable that can be resolved by unification *)
              match RE.quantifier resource, output with
              | None, 
                IT (Lit (Sym s), _) -> 
                 return (SymSet.add s fixed)
              | Some (q, _), 
                IT (Array_op (App (IT (Lit (Sym s), _), IT (Lit (Sym s'), _))), _)
                   when Sym.equal s' q ->
                 return (SymSet.add s fixed)
              (* otherwise, fail *)
              | _ ->
                 let bad = List.hd (SymSet.elements undetermined) in
                 let (loc, odescr) = SymMap.find bad infos in
                 fail loc (Logical_variable_not_good_for_unification (bad, odescr))
          ) SymSet.empty (RE.outputs resource)
      in
      return fixed

  end

  module WLC = struct
    type t = LogicalConstraints.t


    let welltyped loc lc =
      pure begin match lc with
        | LC.T it -> 
           let@ _ = WIT.check loc BT.Bool it in
           return ()
        | LC.Forall ((s,bt), trigger, it) ->
           let@ () = add_l s bt in
           let@ _ = WIT.check loc BT.Bool it in
           match trigger with
           | None -> return ()
           | Some trigger -> 
              (* let@ _ = WIT.infer loc local trigger in *)
              return ()
        end
  end

  module WLRT = struct

    open LogicalReturnTypes
    type t = LogicalReturnTypes.t

    let rec welltyped loc lrt = 
      pure begin match lrt with
        | Logical ((s,ls), info, lrt) -> 
           let lname = Sym.fresh_same s in
           let@ () = add_l lname ls in
           let lrt = subst [(s, IT.sym_ (lname, ls))] lrt in
           welltyped loc lrt
        | Resource (re, info, lrt) -> 
           let@ () = WRE.welltyped (fst info) re in
           let@ () = add_r None re in
           welltyped loc lrt
        | Constraint (lc, info, lrt) ->
           let@ () = WLC.welltyped (fst info) lc in
           let@ () = add_c lc in
           welltyped loc lrt
        | I -> 
           return ()
        end

    let mode_check loc determined lrt = 
      let rec aux determined undetermined infos lrt = 
      match lrt with
      | Logical ((s, _), info, lrt) ->
         aux determined (SymSet.add s undetermined) 
           (SymMap.add s info infos) lrt
      | Resource (re, info, lrt) ->
         let@ fixed = WRE.resource_mode_check (fst info) infos undetermined re in
         let determined = SymSet.union determined fixed in
         let undetermined = SymSet.diff undetermined fixed in
         aux determined undetermined infos lrt
      | Constraint (_, _info, lrt) ->
         aux determined undetermined infos lrt
      | I ->
         match SymSet.elements undetermined with
         | [] -> return ()
         | s :: _ -> 
            let (loc, odescr) = SymMap.find s infos in
            fail loc (Unconstrained_logical_variable (s, odescr))
      in
      aux determined SymSet.empty SymMap.empty lrt 

    let good loc lrt = 
      let@ () = welltyped loc lrt in
      let@ all_vars = all_vars () in
      let@ () = mode_check loc (SymSet.of_list all_vars) lrt in
      return ()

  end


  module WRT = struct

    include ReturnTypes
    type t = ReturnTypes.t

    let welltyped loc rt = 
      pure begin match rt with 
        | Computational ((name,bt), _info, lrt) ->
           let name' = Sym.fresh_same name in
           let lname = Sym.fresh () in
           let@ () = add_l lname bt in
           let@ () = add_a name' (bt, lname) in
           let lrt = LRT.subst [(name, IT.sym_ (lname, bt))] lrt in
           WLRT.welltyped loc lrt
        end

    let mode_check loc determined rt = 
      match rt with
      | Computational ((s, _), _info, lrt) ->
         WLRT.mode_check loc (SymSet.add s determined) lrt

    
    let good loc rt =
      let@ () = welltyped loc rt in
      let@ all_vars = all_vars () in
      let@ () = mode_check loc (SymSet.of_list all_vars) rt in
      return ()

  end



  module WFalse = struct
    include False
    type t = False.t
    let welltyped _ _ = return ()
    let mode_check _ _ _ = return ()
  end

  module type WOutputSpec = sig val name_bts : (string * LS.t) list end
  module WOutputDef (Spec : WOutputSpec) = struct
    include OutputDef
    type t = OutputDef.t
    let check loc assignment =
      let name_bts = List.sort (fun (s, _) (s', _) -> String.compare s s') Spec.name_bts in
      let assignment = List.sort (fun (s, _) (s', _) -> String.compare s s') assignment in
      let rec aux name_bts assignment =
        match name_bts, assignment with
        | [], [] -> return ()
        | (name, bt) :: name_bts, (name', it) :: assignment when String.equal name name' ->
           let@ _ = WIT.check loc bt it in
           aux name_bts assignment
        | (name, _) :: _, _ -> fail loc (Generic !^("missing output argument " ^ name))
        | _, (name, _) :: _ -> fail loc (Generic !^("surplus output argument " ^ name))
      in
      aux name_bts assignment
    let mode_check _ _ _ = return ()
    let welltyped loc assignment = 
      check loc assignment

end


  module type WI_Sig = sig
    type t
    val subst : IndexTerms.t Subst.t -> t -> t
    val pp : t -> Pp.document
    val mode_check : Loc.t -> SymSet.t -> t -> unit m
    val welltyped : Loc.t -> t -> unit m
  end




  module WAT (WI: WI_Sig) = struct


    type t = WI.t AT.t

    let rec welltyped kind loc (at : t) : unit m = 
      pure begin match at with
        | AT.Computational ((name,bt), _info, at) ->
           let name' = Sym.fresh_same name in
           let lname = Sym.fresh () in
           let@ () = add_l lname bt in
           let@ () = add_a name' (bt, lname) in
           let at = AT.subst WI.subst [(name, IT.sym_ (lname, bt))] at in
           welltyped kind loc at
        | AT.Logical ((s,ls), _info, at) -> 
           let lname = Sym.fresh_same s in
           let@ () = add_l lname ls in
           let at = AT.subst WI.subst [(s, IT.sym_ (lname, ls))] at in
           welltyped kind loc at
        | AT.Resource (re, info, at) -> 
           let@ () = WRE.welltyped (fst info) re in
           let@ () = add_r None re in
           welltyped kind loc at
        | AT.Constraint (lc, info, at) ->
           let@ () = WLC.welltyped (fst info) lc in
           let@ () = add_c lc in
           welltyped kind loc at
        | AT.I i -> 
           let@ provable = provable in
           if provable (LC.t_ (IT.bool_ false))
           then fail loc (Generic !^("this "^kind^" makes inconsistent assumptions"))
           else WI.welltyped loc i
        end


    let mode_check loc determined ft = 
      let rec aux determined undetermined infos ft = 
      match ft with
      | AT.Computational ((s, _), _info, ft) ->
         aux (SymSet.add s determined) undetermined infos ft
      | AT.Logical ((s, _), info, ft) ->
         aux determined (SymSet.add s undetermined) 
           (SymMap.add s info infos) ft
      | AT.Resource (re, _info, ft) ->
         let@ fixed = WRE.resource_mode_check loc infos undetermined re in
         let determined = SymSet.union determined fixed in
         let undetermined = SymSet.diff undetermined fixed in
         aux determined undetermined infos ft
      | AT.Constraint (_, _info, ft) ->
         aux determined undetermined infos ft
      | AT.I rt ->
         match SymSet.elements undetermined with
         | [] -> WI.mode_check loc determined rt
         | s :: _ -> 
            let (loc, odescr) = SymMap.find s infos in
            fail loc (Unconstrained_logical_variable (s, odescr))
      in
      aux determined SymSet.empty SymMap.empty ft


    let good kind loc ft = 
      let@ () = welltyped kind loc ft in
      let@ all_vars = all_vars () in
      let@ () = mode_check loc (SymSet.of_list all_vars) ft in
      return ()

  end


  module WFT = WAT(WRT)
  module WLT = WAT(WFalse)
  module WPackingFT(Spec : WOutputSpec) = WAT(WOutputDef(Spec))

  module WPD = struct
    
    let welltyped pd = 
      pure begin
          let open Predicates in
          let@ () = add_l pd.pointer BT.Loc in
          let@ () = add_l pd.permission BT.Real in
          let@ () = ListM.iterM (fun (s, ls) -> add_l s ls) pd.iargs in
          let module WPackingFT = WPackingFT(struct let name_bts = pd.oargs end)  in
          ListM.iterM (fun {loc; guard; packing_ft} ->
              let@ _ = WIT.check loc BT.Bool guard in
              WPackingFT.welltyped "clause" pd.loc packing_ft
            ) pd.clauses
        end

    let mode_check determined pd = 
      let open Predicates in
      let determined = 
        List.fold_left (fun determined (s, _) -> 
            SymSet.add s determined
          ) determined pd.iargs
      in
      let module WPackingFT = WPackingFT(struct let name_bts = pd.oargs end)  in
      ListM.iterM (fun {loc; guard; packing_ft} ->
          WPackingFT.mode_check pd.loc determined packing_ft
        ) pd.clauses

    let good pd =
      let@ () = welltyped pd in
      let@ all_vars = all_vars () in
      let@ () = mode_check (SymSet.of_list all_vars) pd in
      return ()

  end


end
