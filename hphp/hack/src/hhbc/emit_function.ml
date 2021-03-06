(**
 * Copyright (c) 2017, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
*)

open Instruction_sequence
module A = Ast
open Core

(* Given a function definition, emit code, and in the case of <<__Memoize>>,
 * a wrapper function
 *)
let emit_function : A.fun_ -> Hhas_function.t list =
  fun ast_fun ->
  let namespace = ast_fun.A.f_namespace in
  let original_id, _ =
    Hhbc_id.Function.elaborate_id namespace ast_fun.A.f_name in
  let function_is_async =
    ast_fun.Ast.f_fun_kind = Ast_defs.FAsync
    || ast_fun.Ast.f_fun_kind = Ast_defs.FAsyncGenerator in
  let default_dropthrough =
    if function_is_async
    then Some (gather [instr_null; instr_retc])
    else None in
  let function_attributes =
    Emit_attribute.from_asts namespace ast_fun.Ast.f_user_attributes in
  let is_memoize = Hhas_attribute.is_memoized function_attributes in
  let renamed_id =
    if is_memoize
    then Hhbc_id.Function.add_suffix original_id Emit_memoize_helpers.memoize_suffix
    else original_id in
  let scope = [Ast_scope.ScopeItem.Function ast_fun] in
  let function_body, function_is_generator, function_is_pair_generator =
    Emit_body.emit_body
      ~scope
      ~is_closure_body:false
      ~is_memoize
      ~skipawaitable:(ast_fun.Ast.f_fun_kind = Ast_defs.FAsync)
      ~is_return_by_ref:ast_fun.Ast.f_ret_by_ref
      ~default_dropthrough
      ~return_value:instr_null
      ~namespace
      ast_fun.Ast.f_params
      ast_fun.Ast.f_ret
      [Ast.Stmt (Ast.Block ast_fun.Ast.f_body)] in
  let normal_function =
    Hhas_function.make
      function_attributes
      renamed_id
      function_body
      function_is_async
      function_is_generator
      function_is_pair_generator in
  if is_memoize
  then [normal_function;
    Emit_memoize_function.emit_wrapper_function ~original_id ~renamed_id ast_fun]
  else [normal_function]

let emit_functions_from_program ast =
  List.concat_map ast
  (fun d ->
    match d with Ast.Fun fd -> emit_function fd | _ -> [])
