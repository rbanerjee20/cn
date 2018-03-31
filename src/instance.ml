open Instance_manager

let dummy_io =
  let open Pipeline in
  let skip = fun _ -> Exception.except_return ()
  in {
    pass_message=   skip;
    set_progress=   skip;
    run_pp=         (fun _ -> skip);
    print_endline=  skip;
    print_debug=    (fun _ -> skip);
    warn=           skip;
  }

let setup_cerb_conf cerb_debug_level cpp_cmd impl_filename =
  let open Pipeline in
  let core_stdlib = load_core_stdlib ()
  in {
    debug_level=         cerb_debug_level;
    pprints=             [];
    astprints=           [];
    ppflags=             [];
    typecheck_core=      false;
    rewrite_core=        true;
    sequentialise_core=  true;
    cpp_cmd=             cpp_cmd;
    core_stdlib=         core_stdlib;
    core_impl=           load_core_impl core_stdlib impl_filename;
  }

(* It would be nice if Smt2 could use polymorphic variant *)
let to_smt2_mode = function
  | Random -> Smt2.Random
  | Exhaustive -> Smt2.Exhaustive

(* TODO: this hack is due to cerb_conf be undefined when running Cerberus *)
let hack conf mode =
  let open Global_ocaml in
  cerb_conf := fun () -> {
    cpp_cmd=            conf.Pipeline.cpp_cmd;
    pps=                [];
    ppflags=            [];
    core_stdlib=        conf.Pipeline.core_stdlib;
    core_impl_opt=      Some conf.Pipeline.core_impl;
    core_parser=        (fun _ -> failwith "No core parser");
    exec_mode_opt=      Some (to_smt2_mode mode);
    ocaml=              false;
    ocaml_corestd=      false;
    progress=           false;
    rewrite=            conf.Pipeline.rewrite_core;
    sequentialise=      conf.Pipeline.sequentialise_core;
    concurrency=        false;
    preEx=              false;
    error_verbosity=    Global_ocaml.Basic;
    batch=              true;
    experimental_unseq= false;
    typecheck_core=     conf.Pipeline.typecheck_core;
    defacto=            false;
    default_impl=       false;
    action_graph=       false;
  }

let respond f = function
  | Exception.Result r ->
    f r
  | Exception.Exception err ->
    Failure (Pp_errors.to_string err)

(* elaboration *)

let elaborate ~conf ~filename =
  let return = Exception.except_return in
  let (>>=)  = Exception.except_bind in
  hack (fst conf) Random;
  print_endline ("Elaborating: " ^ filename);
  Debug_ocaml.print_debug 2 [] (fun () -> "Elaborating: " ^ filename);
  try
    Pipeline.c_frontend conf filename
    >>= function
    | (Some cabs, Some ail, sym_suppl, core) ->
      Pipeline.core_passes conf ~filename core
      >>= fun (core', _) ->
      return (cabs, ail, sym_suppl, core')
    | _ ->
      Exception.throw (Location_ocaml.unknown,
                       Errors.OTHER "fatal failure core pass")
  with
  | e ->
    Debug_ocaml.warn [] (fun () ->
        "Exception raised during elaboration. " ^ Printexc.to_string e
      ); raise e

let result_of_elaboration (cabs, ail, _, core) =
  let string_of_doc d =
    let buf = Buffer.create 1024 in
    PPrint.ToBuffer.pretty 1.0 80 buf d;
    Buffer.contents buf
  in
  let elim_paragraph_sym = Str.global_replace (Str.regexp_string "§") "" in
  let mk_elab d = Some (elim_paragraph_sym @@ string_of_doc d) in
  let (core, locs) =
    let module Param_pp_core = Pp_core.Make (struct
        let show_std = true
        let show_location = true
        let show_proc_decl = false
      end) in
    Colour.do_colour := false;
    Param_pp_core.pp_file core
    |> string_of_doc
    |> Location_mark.extract
  in Elaboration
    { pp= {
        cabs= None;
        ail=  mk_elab @@ Pp_ail.pp_program ail;
        core= Some (elim_paragraph_sym core)
      };
      ast= {
        cabs= mk_elab @@ Pp_cabs.pp_translation_unit false false cabs;
        ail=  mk_elab @@ Pp_ail_ast.pp_program ail;
        core = None;
      };
      locs= locs;
    }

(* execution *)

let execute ~conf ~filename (mode: exec_mode) =
  let return = Exception.except_return in
  let (>>=)  = Exception.except_bind in
  hack (fst conf) mode;
  Debug_ocaml.print_debug 2 [] (fun () ->
      "Executing in " ^ string_of_exec_mode mode ^ " mode: " ^ filename
    );
  try
    elaborate ~conf ~filename
    >>= fun (cabs, ail, sym_suppl, core) ->
    Pipeline.interp_backend dummy_io sym_suppl core [] true false false
      (to_smt2_mode mode)
    >>= function
    | Either.Left res ->
      return (String.concat "\n" res)
    | Either.Right res ->
      return (string_of_int res)
  with
  | e ->
    Debug_ocaml.warn [] (fun () ->
        "Exception raised during execution." ^ Printexc.to_string e
      ); raise e

(* WARN: fresh new ids *)
let _fresh_node_id : int ref = ref 0
let new_id () = _fresh_node_id := !_fresh_node_id + 1; !_fresh_node_id

let encode s = Marshal.to_string s [Marshal.Closures]
let decode s = Marshal.from_string s 0

let rec multiple_steps step_state (Nondeterminism.ND m, st) =
  let get_location _ = None in (* TODO *)
  let create_branch lab (st: Driver.driver_state) (ns, es, previousNode) =
    let nodeId  = new_id () in
    let mem     = Ocaml_mem.serialise_mem_state st.Driver.layout_state in
    let newNode = Branch (nodeId, lab, mem, get_location st) in
    let ns' = newNode :: ns in
    let es' = Edge (previousNode, nodeId) :: es in
    (ns', es', nodeId)
  in
  let create_leafs st ms (ns, es, previousNode) =
    let (is, ns') = List.fold_left (fun (is, ns) (l, m) ->
        let i = new_id () in
        let n = Leaf (i, l, encode (m, st)) in
        (i::is, n::ns)
      ) ([], ns) ms in
    let es' = (List.map (fun n -> Edge (previousNode, n)) is) @ es in
    (ns', es', previousNode)
  in
  let exec_tree (ns, es, _) = Interaction (None, (ns, es)) in
  let finish res (ns, es, _) = Interaction (Some res, (ns, es)) in
  try
    let open Nondeterminism in
    let one_step step_state = function
      | (NDactive a, st') ->
        let str_v = String_core.string_of_value a.Driver.dres_core_value in
        let res =
          "Defined {value: \"" ^ str_v ^ "\", stdout: \""
          ^ String.escaped a.Driver.dres_stdout
          ^ "\", blocked: \""
          ^ if a.Driver.dres_blocked then "true\"}" else "false\"}"
        in
        create_branch str_v st' step_state
        |> finish res
      | (NDkilled r, st') ->
        create_branch "killed" st' step_state
        |> finish "killed"
      | (NDbranch (str, _, m1, m2), st') ->
        create_branch str st' step_state
        |> create_leafs st' [("opt1", m1); ("opt2", m2)]
        |> exec_tree
      | (NDguard (str, _, m), st') ->
        create_leafs st' [(str, m)] step_state
        |> exec_tree
      | (NDnd (str, (_,m)::ms), st') ->
        (* json_of_step (msg.steps, str, m, st') *)
        failwith "Ndnd"
      | (NDstep ms, st') ->
        create_leafs st' ms step_state
        |> exec_tree
      | _ -> failwith ""
    in begin match m st with
      | (NDstep [(lab, m')], st') ->
        let step_state' = create_branch lab st' step_state in
        multiple_steps step_state' (m', st')
      | act -> one_step step_state act
    end
  with
  | e -> Debug_ocaml.warn [] (fun () ->
      "Exception raised during execution." ^ Printexc.to_string e
    ); raise e

let step ~conf ~filename = function
  | None ->
    let step_init () =
      let return = Exception.except_return in
      let (>>=)  = Exception.except_bind in
      hack (fst conf) Random;
      elaborate ~conf ~filename
      >>= fun (_, _, sym_suppl, core) ->
      let core' = Core_run_aux.convert_file core in
      let st0   = Driver.initial_driver_state sym_suppl core' in
      return (Driver.drive false false sym_suppl core' [], st0)
    in begin match step_init () with
      | Exception.Result (m, st) ->
        let initId   = new_id () in
        let nodeId   = Leaf (initId, "Initial State", encode (m, st)) in
        Interaction (None, ([nodeId], []))
      | Exception.Exception err ->
        Failure (Pp_errors.to_string err)
    end
  | Some (marshalled_state, node) ->
    hack (fst conf) Random;
    decode marshalled_state
    |> multiple_steps ([], [], node)

(* instance *)

module Instance : Instance = struct
  let pipe_conf =
    let impl = "gcc_4.9.0_x86_64-apple-darwin10.8.0" in
    let cpp_cmd = "cc -E -C -traditional-cpp -nostdinc -undef -D__cerb__ -I "
                ^ Pipeline.cerb_path ^ "/include/c/libc -I "
                ^ Pipeline.cerb_path ^ "/include/c/posix"
    in setup_cerb_conf 0 cpp_cmd impl

  let name =
    print_endline ("Creating instance of " ^ Prelude.string_of_mem_switch ());
    Prelude.string_of_mem_switch ()

  let instance_conf conf =
    let new_conf = { pipe_conf with Pipeline.rewrite_core= conf.rewrite }
    in (new_conf, dummy_io)

  let elaborate user_conf filename =
    print_endline ("Accessing " ^ name);
    let conf = instance_conf user_conf in
    elaborate ~conf ~filename
    |> respond result_of_elaboration

  let execute user_conf filename mode =
    print_endline ("Accessing " ^ name);
    let conf = instance_conf user_conf in
    execute ~conf ~filename mode
    |> respond (fun s -> Execution s)

  let step user_conf filename active =
    print_endline ("Accessing " ^ name);
    let conf = instance_conf user_conf in
    step ~conf ~filename active
end

let () =
  print_endline ("Loading " ^ Ocaml_mem.name);
  Instance_manager.set_model (module Instance)
