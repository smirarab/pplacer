open Ppatteries
open Subcommand
open Guppy_cmdobjs

let save_named_fal fname fal =
  Csv.save fname (Guppy_splitify.fal_to_strll fal)

let expand full_length m arr =
  let full = Array.make full_length 0. in
  Array.iteri (fun i v -> full.(IntMap.find i m) <- v) arr;
  full

class virtual pca_cmd () =
object (self)
  inherit subcommand () as super
  inherit output_cmd ~show_fname:false ~prefix_required:true () as super_output
  inherit mass_cmd () as super_mass
  inherit heat_cmd () as super_heat
  inherit refpkg_cmd ~required:false as super_refpkg
  inherit placefile_cmd () as super_placefile
  inherit splitify_cmd () as super_splitify

  val write_n = flag "--write-n"
    (Formatted (5, "The number of principal coordinates to write out (default is %d)."))
  val scale = flag "--scale"
    (Plain (false, "Scale variances to one before performing principal components."))
  val symmv = flag "--symmv"
    (Plain (false, "Use a complete eigendecomposition rather than power iteration."))
  val raw_eval = flag "--raw-eval"
    (Plain (false, "Output the raw eigenvalue rather than the fraction of variance."))

  method specl =
    super_output#specl
    @ super_mass#specl
    @ super_refpkg#specl
    @ super_heat#specl
    @ [
      int_flag write_n;
      toggle_flag scale;
      toggle_flag symmv;
    ]
    @ super_splitify#specl

  method private virtual prep_data : 'prl_t -> 'data_t * 'extra_t
  method private virtual expand_combol : 'combol_t -> 'extra_t -> 'fullcombol_t

  method private placefile_action prl =
    self#check_placerunl prl;
    let scale = fv scale
    and write_n = fv write_n
    and _, t = self#get_rpo_and_tree (List.hd prl)
    and prefix = self#single_prefix ~requires_user_prefix:true () in

    let (data, extra) = self#prep_data prl in

    let n_unique_rows = List.length (List.sort_unique compare data) in
    if n_unique_rows <= 2 then
      failwith(Printf.sprintf "You have only %d unique row(s) in your data \
      after transformation. This is not enough to do edge PCA." n_unique_rows);
    let write_n =
      if n_unique_rows < write_n then begin
        Printf.printf "You have only %d unique rows in your data after \
          transformation. Restricting to this number of principal components.\n"
          n_unique_rows;
        n_unique_rows
      end
      else
        write_n
    in
    let (eval, evect) =
      Pca.gen_pca ~use_raw_eval:(fv raw_eval)
        ~scale ~symmv:(fv symmv) write_n (Array.of_list data)
    in
    let combol = (List.combine (Array.to_list eval) (Array.to_list evect))
    and names = (List.map Placerun.get_name prl) in

    let full_combol = self#expand_combol combol extra in

    Phyloxml.named_gtrees_to_file
      (prefix^".xml")
      (List.map
         (fun (eval, evect) ->
           (Some (string_of_float eval),
            self#heat_tree_of_float_arr t evect |> self#maybe_numbered))
         full_combol);
    save_named_fal
      (prefix^".rot")
      (List.map (fun (eval, evect) -> (string_of_float eval, evect)) combol);
    save_named_fal
      (prefix^".trans")
      (List.combine
         names
         (List.map (fun d -> Array.map (Pca.dot d) evect) data));
    save_named_fal
      (prefix^".edgediff")
      (List.combine names data);
    ()

end
