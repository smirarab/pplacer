(* The bark for newick gtrees, i.e. trees that only have bl, name, and boot.
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

let float_approx_compare epsilon x y =
  let diff = x -. y in
  if abs_float diff <= epsilon then 0
  else if diff < 0. then -1
  else 1

let floato_approx_compare epsilon a b =
  match (a, b) with
  | (Some x, Some y) -> float_approx_compare epsilon x y
  | (a, b) -> Pervasives.compare a b

let compare ?epsilon:(epsilon=0.) ?cmp_boot:(cmp_boot=true) b1 b2 =
  let fc = floato_approx_compare epsilon in
  try
    Base.raise_if_different fc b1#get_bl_opt b2#get_bl_opt;
    Base.raise_if_different compare b1#get_name_opt b2#get_name_opt;
    if cmp_boot then Base.raise_if_different fc b1#get_boot_opt b2#get_boot_opt;
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
