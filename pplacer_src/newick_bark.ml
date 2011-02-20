(* pplacer v1.0. Copyright (C) 2009-2010  Frederick A Matsen.
 * This file is part of pplacer. pplacer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The bark for newick gtrees, i.e. trees that only have bl, name, and boot.
*)

open Fam_batteries
open MapsSets

exception No_bl
exception No_name
exception No_boot

let opt_val_to_string val_to_string = function
  | Some x -> val_to_string x
  | None -> ""

let ppr_opt_named name ppr_val ff = function
  | Some x -> Format.fprintf ff " %s = %a;@," name ppr_val x
  | None -> ()

let write_something_opt write_it ch = function
  | Some x -> write_it ch x
  | None -> ()

class newick_bark arg =

  let (bl, name, boot) =
    match arg with
    | `Empty -> (None, None, None)
    | `Of_bl_name_boot (bl, name, boot) -> (bl, name, boot)
  in

  object (self)
    val bl = bl
    val name = name
    val boot = boot

    method get_bl_opt = bl
    method get_bl =
      match bl with | Some x -> x | None -> raise No_bl
    method set_bl_opt xo = {< bl = xo >}
    method set_bl (x:float) = {< bl = Some x >}

    method get_name_opt = name
    method get_name =
      match name with | Some s -> s | None -> raise No_name
    method set_name_opt so = {< name = so >}
    method set_name s = {< name = Some s >}

    method get_boot_opt = boot
    method get_boot =
      match boot with | Some x -> x | None -> raise No_boot
    method set_boot_opt xo = {< boot = xo >}
    method set_boot x = {< boot = Some x >}

    method to_newick_string =
      (opt_val_to_string (Printf.sprintf "%g") boot) ^
      (opt_val_to_string (fun s -> s) name) ^
      (opt_val_to_string (fun x -> ":"^(Printf.sprintf "%g" x)) bl)

    method private ppr_inners ff =
      ppr_opt_named "bl" Format.pp_print_float ff bl;
      ppr_opt_named "name" Format.pp_print_string ff name;
      ppr_opt_named "boot" Format.pp_print_float ff boot

    method ppr ff =
      Format.fprintf ff "@[{%a}@]" (fun ff () -> self#ppr_inners ff) ()

    method to_xml = begin
      let maybe_list f = function
        | Some x -> f x
        | None -> []
      in maybe_list (fun name -> [Myxml.tag "name" name]) name
      @ maybe_list (fun bl -> [Myxml.tag "branch_length" (Printf.sprintf "%g" bl)]) bl
      @ maybe_list (fun boot ->
        [Myxml.tag "confidence" ~attributes:[("type", "bootstrap")] (Printf.sprintf "%g" boot)]) boot
    end

    method to_numbered id =
      {< name = Some
                (match name with
                | Some s -> Printf.sprintf "@%s" s
                | None -> "");
         boot = Some (float_of_int id); >}

  end

let compare b1 b2 =
  try
    Base.raise_if_different compare b1#get_bl_opt b2#get_bl_opt;
    Base.raise_if_different compare b1#get_name_opt b2#get_name_opt;
    Base.raise_if_different compare b1#get_boot_opt b2#get_boot_opt;
    0
  with
  | Base.Different c -> c


let map_find_loose id m =
  if IntMap.mem id m then IntMap.find id m
  else new newick_bark `Empty

let map_set_bl id bl m =
  IntMap.add id ((map_find_loose id m)#set_bl bl) m

let map_set_name id name m =
  IntMap.add id ((map_find_loose id m)#set_name name) m

let map_set_boot id boot m =
  IntMap.add id ((map_find_loose id m)#set_boot boot) m
