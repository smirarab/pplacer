open Ppatteries

module BA = Bigarray
module BA1 = Bigarray.Array1

type int_vector = (int, BA.int_elt, BA.c_layout) BA1.t
external c_pam: int -> Matrix.matrix -> int_vector * float = "caml_pam"

module I = Mass_map.Indiv

let solve gt mass leaves =
  (* transm is old -> new *)
  let gt', transm = Gtree.renumber gt in
  let dist = Edge_rdist.build_pairwise_dist gt'
    |> Edge_rdist.find_pairwise_dist
  and leaf_arr = Gtree.leaf_ids gt' |> Array.of_list
  and trans i = IntMap.find i transm
  (* rtransm is new -> old *)
  and rtransm = IntMap.enum transm |> Enum.map swap |> IntMap.of_enum in
  let rtrans i = IntMap.find i rtransm
  and total_mass = I.total_mass mass in
  (* Generate a work matrix. *)
  let leaf_vec, work = IntMap.fold
    (fun i vl accum ->
      List.fold_left
        (fun accum {I.distal_bl; I.mass} ->
          (* bl scaled by mass *)
          Array.map (fun j -> mass *. (dist (trans i) distal_bl j 0.)) leaf_arr :: accum)
        accum
        vl)
    mass
    []
  |> Array.of_list
  |> Matrix.of_arrays
  (* rows are masses; columns are leaves. thus, we need to transpose *)
  |> Matrix.rect_transpose
  |> c_pam leaves
  in
  BA1.enum leaf_vec
  |> Enum.map (Array.get leaf_arr |- rtrans)
  |> IntSet.of_enum,
  work /. total_mass
