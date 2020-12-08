open Pp
open Resultat
module CF=Cerb_frontend
open CF.Mucore
open TypeErrors
open ReturnTypes


module SymMap = Map.Make(Sym)
module RE = Resources
module LT = ArgumentTypes.Make(False)
module FT = ArgumentTypes.Make(ReturnTypes)





let record_tagDefs (global: Global.t) tagDefs = 
  PmapM.foldM (fun sym def (global: Global.t) ->
      match def with
      | M_UnionDef _ -> 
         fail Loc.unknown (Unsupported !^"todo: union types")
      | M_StructDef (_ct, decl) -> 
         let struct_decls = SymMap.add sym decl global.struct_decls in
         return { global with struct_decls }
    ) tagDefs global


let record_funinfo global funinfo =
  let module WT = WellTyped.Make(struct let global = global end) in
  PmapM.foldM
    (fun fsym (M_funinfo (loc, Attrs attrs, ftyp, is_variadic, has_proto)) global ->
      let loc' = Loc.update Loc.unknown loc in
      if is_variadic then 
        let err = !^"Variadic function" ^^^ Sym.pp fsym ^^^ !^"unsupported" in
        fail loc' (Unsupported err)
      else
        let* () = WT.WFT.welltyped loc' WT.L.empty ftyp in
        let fun_decls = SymMap.add fsym (loc', ftyp) global.Global.fun_decls in
        return {global with fun_decls}
    ) funinfo global


(* check the types? *)
let record_impl genv impls = 
  let open Global in
  Pmap.fold (fun impl impl_decl genv ->
      match impl_decl with
      | M_Def (bt, _p) -> 
         { genv with impl_constants = ImplMap.add impl bt genv.impl_constants}
      | M_IFun (rbt, args, _body) ->
         let args_ts = List.map FT.mComputational args in
         let rt = FT.I (Computational ((Sym.fresh (), rbt), I)) in
         let ftyp = (Tools.comps args_ts) rt in
         let impl_fun_decls = ImplMap.add impl ftyp genv.impl_fun_decls in
         { genv with impl_fun_decls }
    ) impls genv


let print_initial_environment genv = 
  debug 1 (lazy (headline "initial environment"));
  debug 1 (lazy (Global.pp genv));
  return ()


let process_functions genv fns =
  let module C = Check.Make(struct let global = genv end) in
  PmapM.iterM (fun fsym fn -> 
      match fn with
      | M_Fun (rbt, args, body) ->
         let* (loc, ftyp) = match Global.get_fun_decl genv fsym with
           | Some t -> return t
           | None -> fail Loc.unknown (Missing_function fsym)
         in
         C.check_function loc fsym args rbt body ftyp
      | M_Proc (loc, rbt, args, body, labels) ->
         let loc = Loc.update Loc.unknown loc in
         let* (loc', ftyp) = match Global.get_fun_decl genv fsym with
           | Some t -> return t
           | None -> fail loc (Missing_function fsym)
         in
         C.check_procedure loc' fsym args rbt body ftyp labels
      | M_ProcDecl _
      | M_BuiltinDecl _ -> 
         return ()
    ) fns



let process mu_file =

  Debug_ocaml.begin_csv_timing "overall";

  let* mu_file = PreProcess.retype_file Loc.unknown mu_file in

  let solver_context = Solver.initial_context in

  let global = Global.empty solver_context in

  let* global = record_tagDefs global mu_file.mu_tagDefs in

  let global = record_impl global mu_file.mu_impl in

  let* global = record_funinfo global mu_file.mu_funinfo in

  let stdlib_funs = SymSet.of_list (Pset.elements (Pmap.domain mu_file.mu_stdlib)) in

  let global = { global with stdlib_funs } in

  let* () = print_initial_environment global in

  let* result = process_functions global mu_file.mu_funs in

  Debug_ocaml.end_csv_timing ();

  return result



