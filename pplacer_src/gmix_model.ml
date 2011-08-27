open Ppatteries

module BA = Bigarray
module BA1 = BA.Array1
module BA2 = BA.Array2
module BA3 = BA.Array3

let log_of_2 = log 2.

(* integer big arrays *)
let iba1_create = BA1.create BA.int BA.c_layout
let iba1_mimic a = iba1_create (BA1.dim a)
let iba1_copy a = let b = iba1_mimic a in BA1.blit a b; b
let iba1_to_array a =
  let arr = Array.make (BA1.dim a) 0 in
  for i=0 to (BA1.dim a)-1 do arr.(i) <- a.{i} done;
  arr
let iba1_ppr ff a = Ppr.ppr_int_array ff (iba1_to_array a)
let iba1_pairwise_sum dest x y =
  let n = BA1.dim x in
  assert(n = BA1.dim y && n = BA1.dim dest);
  for i=0 to n-1 do
    BA1.unsafe_set
      dest i ((BA1.unsafe_get x i) + (BA1.unsafe_get y i))
  done

module Model: Glvm.Model =
struct

  (* this simply contains the information about the Markov process corresponding
   * to the model.
   *
   * we also include matrices mats which can be used as scratch to avoid having to
   * allocate for it. see prep_mats_for_bl below. *)

  type t = {
    statd: Gsl_vector.vector;
    diagdq: Diagd.t;
    seq_type: Alignment.seq_type;
    rates: float array;
    (* tensor is a tensor of the right shape to be a multi-rate transition matrix for the model *)
    tensor: Tensor.tensor;
  }
  type model_t = t

  let statd    model = model.statd
  let diagdq   model = model.diagdq
  let rates    model = model.rates
  let tensor   model = model.tensor
  let seq_type model = model.seq_type
  let n_states model = Alignment.nstates_of_seq_type model.seq_type
  let n_rates  model = Array.length (rates model)

  let build ref_align = function
    | Glvm.Gmix_model (model_name, emperical_freqs, opt_transitions, rates) ->
      let seq_type, (trans, statd) =
        if model_name = "GTR" then
          (Alignment.Nucleotide_seq,
           match opt_transitions with
             | Some transitions ->
               (Nuc_models.b_of_trans_vector transitions,
                Alignment.emper_freq 4 Nuc_models.nuc_map ref_align)
             | None -> failwith "GTR specified but no substitution rates given.")
        else
          (Alignment.Protein_seq,
           let model_trans, model_statd =
             Prot_models.trans_and_statd_of_model_name model_name in
           (model_trans,
            if emperical_freqs then
              Alignment.emper_freq 20 Prot_models.prot_map ref_align
            else
              model_statd))
      in
      let n_states = Alignment.nstates_of_seq_type seq_type in
      {
        statd = statd;
        diagdq = Diagd.normed_of_exchangeable_pair trans statd;
        seq_type = seq_type;
        rates = rates;
        tensor = Tensor.create (Array.length rates) n_states n_states;
      }

    | _ -> invalid_arg "build"

  (* prepare the tensor for a certain branch length *)
  let prep_tensor_for_bl model bl =
    Diagd.multi_exp model.tensor model.diagdq model.rates bl

  let get_symbol code = function
    | -1 -> '-'
    | i -> try code.(i) with | Invalid_argument _ -> assert(false)

  let to_sym_str code ind_arr =
    StringFuns.of_char_array (Array.map (get_symbol code) ind_arr)

  let code model =
    match seq_type model with
      | Alignment.Nucleotide_seq -> Nuc_models.nuc_code
      | Alignment.Protein_seq -> Prot_models.prot_code

  module Glv =
  struct

    (* glvs *)
    type t = {
      model: model_t;
      e: (int, BA.int_elt, BA.c_layout) BA1.t;
      a: Tensor.tensor;
    }

    let get_n_rates g = Tensor.dim1 g.a
    let get_n_sites g =
      let n = Tensor.dim2 g.a in
      assert(n = BA1.dim g.e);
      n
    let get_n_states g = Tensor.dim3 g.a

    let dims g = (get_n_rates g, get_n_sites g, get_n_states g)

    let ppr ff g =
      Format.fprintf ff "@[{ e = %a; @,a = %a }@]"
        iba1_ppr g.e
        Tensor.ppr g.a

    let make model ~n_rates ~n_sites ~n_states = {
      model;
      e = iba1_create n_sites;
      a = Tensor.create n_rates n_sites n_states;
    }

    (* make a glv of the same dimensions *)
    let mimic x = { x with
      e = iba1_mimic x.e;
      a = Tensor.mimic x.a;
    }

(* deep copy *)
    let copy x = { x with
      e = iba1_copy x.e;
      a = Tensor.copy x.a;
    }

    let memcpy ~dst ~src =
      BA1.blit src.e dst.e;
      BA3.blit src.a dst.a

(* set all of the entries of the glv to some float *)
    let set_exp_and_all_entries g e x =
      BA1.fill g.e e;
      BA3.fill g.a x

    let set_all g ve va =
      BA1.fill g.e ve;
      Tensor.set_all g.a va

(* Find the "worst" fpclass of the floats in g. *)
    let fp_classify g =
      Tensor.fp_classify g.a

(* set g according to function fe for exponenent and fa for entries *)
    let seti g fe fa =
      let n_sites = get_n_sites g
      and n_rates = get_n_rates g
      and n_states = get_n_states g in
      for site=0 to n_sites-1 do
        for rate=0 to n_rates-1 do
          for state=0 to n_states-1 do
            g.a.{rate,site,state} <- fa ~rate ~site ~state
          done
        done;
        g.e.{site} <- fe site
      done

(* copy the site information from src to dst. _i is which site to copy. *)
    let copy_site ~src_i ~src ~dst_i ~dst =
      (dst.e).{dst_i} <- (src.e).{src_i};
      for rate=0 to (get_n_rates src)-1 do
        BA1.blit (BA3.slice_left_1 src.a rate src_i)
          (BA3.slice_left_1 dst.a rate dst_i)
      done

(* copy the sites marked with true in site_mask_arr from src to dst. the number
 * of trues in site_mask_arr should be equal to the number of sites in dst. *)
    let mask_into site_mask_arr ~src ~dst =
      let dst_n_sites = get_n_sites dst in
      let dst_i = ref 0 in
      Array.iteri
        (fun src_i b ->
          if b then begin
            assert(!dst_i < dst_n_sites);
            copy_site ~src ~src_i ~dst_i:(!dst_i) ~dst;
            incr dst_i;
          end)
        site_mask_arr;
      assert(!dst_i = dst_n_sites)

(* this is used when we have a pre-allocated GLV and want to fill it with a
 * same-length lv array. zero pulled exponents as well. *)
    let prep_constant_rate_glv_from_lv_arr g lv_arr =
      assert(lv_arr <> [||]);
      assert(get_n_sites g = Array.length lv_arr);
      assert(get_n_states g = Gsl_vector.length lv_arr.(0));
      seti g
        (fun _ -> 0)
        (fun ~rate:_ ~site ~state ->
          lv_arr.(site).{state})

(* *** pulling exponent *** *)

(* gets the base two exponent *)
    let get_twoexp x = snd (frexp x)

(* makes a float given a base two exponent. we use 0.5 because:
   # frexp (ldexp 1. 3);;
   - : float * int = (0.5, 4)
   so that's how ocaml interprets 2^i anyway.
*)
    let of_twoexp i = ldexp 0.5 (i+1)

(* pull out the exponent if it's below min_allowed_twoexp and return it. this
 * process is a bit complicated by the fact that we are partitioned by rate, as
 * can be seen below. *)
    let perhaps_pull_exponent min_allowed_twoexp g =
      let n_rates = get_n_rates g
      and n_sites = get_n_sites g in
      let max_twoexp = ref (-max_int) in
  (* cycle through sites *)
      for site=0 to n_sites-1 do
        max_twoexp := (-max_int);
    (* first find the max twoexp *)
        for rate=0 to n_rates-1 do
          let s = BA3.slice_left_1 g.a rate site in
          let (_, twoexp) = frexp (Gsl_vector.max s) in
          if twoexp > !max_twoexp then max_twoexp := twoexp
        done;
    (* now scale if it's needed *)
        if !max_twoexp < min_allowed_twoexp then begin
          for rate=0 to n_rates-1 do
        (* take the negative so that we "divide" by 2^our_twoexp *)
            Gsl_vector.scale
              (BA3.slice_left_1 g.a rate site)
              (of_twoexp (-(!max_twoexp)));
          done;
      (* bring the exponent out *)
          g.e.{site} <- g.e.{site} + !max_twoexp;
        end
      done


(* *** likelihood calculations *** *)

(* total all of the stored exponents. we use a float to avoid overflow. *)
    let total_twoexp g =
      let tot = ref 0. in
      for i=0 to (get_n_sites g)-1 do
        tot := !tot +. float_of_int (BA1.unsafe_get g.e i)
      done;
      !tot

(* total all of the stored exponents in a specified range. *)
    let bounded_total_twoexp g start last =
      let tot = ref 0. in
      for i=start to last do
        tot := !tot +. float_of_int (BA1.unsafe_get g.e i)
      done;
      !tot

(* the log "dot" of the likelihood vectors in the 0-indexed interval
 * [start,last] *)
    let bounded_logdot utilv_nsites x y start last =
      assert(dims x = dims y);
      assert(start >= 0 && start <= last && last < get_n_sites x);
      (Linear.bounded_logdot
         x.a y.a start last utilv_nsites)
      +. (log_of_2 *. ((bounded_total_twoexp x start last) +.
                          (bounded_total_twoexp y start last)))

(* just take the log "dot" of the likelihood vectors *)
    let logdot utilv_nsites x y =
      bounded_logdot utilv_nsites x y 0 ((get_n_sites x)-1)

(* multiply by a tensor *)
    let tensor_mul tensor ~dst ~src =
  (* iter over rates *)
      for i=0 to (Tensor.dim1 src.a)-1 do
        let src_mat = BA3.slice_left_2 src.a i
        and evo_mat = BA3.slice_left_2 tensor i
        and dst_mat = BA3.slice_left_2 dst.a i
        in
        Linear.gemmish dst_mat evo_mat src_mat
      done

(* take the pairwise product of glvs g1 and g2, then store in dest. *)
    let pairwise_prod ~dst g1 g2 =
      assert(dims g1 = dims g2);
      iba1_pairwise_sum dst.e g1.e g2.e;
      Linear.pairwise_prod dst.a g1.a g2.a

(* take the product of all of the GLV's in the list, then store in dst.
 * could probably be implemented more quickly, but typically we are only taking
 * pairwise products anyway. we pull out the x::y below to optimize for that
 * case. *)
    let listwise_prod dst = function
      | x::y::rest ->
      (* first product of first two *)
        pairwise_prod ~dst x y;
      (* now take product with each of the rest *)
        List.iter (pairwise_prod ~dst dst) rest
      | [src] ->
      (* just copy over *)
        memcpy ~dst ~src
      | [] -> assert(false)


(* For verification purposes. *)

    let get_a g ~rate ~site ~state = BA3.get g.a rate site state


  end

  type glv_t = Glv.t

  let make_glv model =
    Glv.make
      model
      ~n_states:(n_states model)
      ~n_rates:(n_rates model)

  (* this is used when we want to make a glv out of a list of likelihood
   * vectors. differs from below because we want to make a new one. *)
  let lv_arr_to_constant_rate_glv model n_rates lv_arr =
    assert(lv_arr <> [||]);
    let g = Glv.make
      model
      ~n_rates
      ~n_sites:(Array.length lv_arr)
      ~n_states:(Gsl_vector.length lv_arr.(0)) in
    Glv.prep_constant_rate_glv_from_lv_arr g lv_arr;
    g


(* take the log like of the product of three things then dot with the stationary
 * distribution. *)
    let log_like3 model utilv_nsites x y z =
      assert(Glv.dims x = Glv.dims y && Glv.dims y = Glv.dims z);
      (Linear.log_like3 (statd model)
         x.Glv.a
         y.Glv.a
         z.Glv.a
         utilv_nsites)
      +. (log_of_2 *.
            ((Glv.total_twoexp x) +. (Glv.total_twoexp y) +. (Glv.total_twoexp z)))

(* evolve_into:
 * evolve src according to model for branch length bl, then store the
 * results in dst.
 *)
    let evolve_into model ~dst ~src bl =
  (* copy over the exponents *)
      BA1.blit src.Glv.e dst.Glv.e;
  (* prepare the matrices in our matrix cache *)
      prep_tensor_for_bl model bl;
  (* iter over rates *)
      Glv.tensor_mul (tensor model) ~dst ~src

(* take the pairwise product of glvs g1 and g2, incorporating the stationary
 * distribution, then store in dest. *)
    let statd_pairwise_prod model ~dst g1 g2 =
      assert(Glv.dims g1 = Glv.dims g2);
      iba1_pairwise_sum dst.Glv.e g1.Glv.e g2.Glv.e;
      Linear.statd_pairwise_prod (statd model) dst.Glv.a g1.Glv.a g2.Glv.a

    let slow_log_like3 model x y z =
      let f_n_rates = float_of_int (n_rates model)
      and ll_tot = ref 0.
      and statd = statd model
      in
      for site=0 to (Glv.get_n_sites x)-1 do
        let site_like = ref 0. in
        for rate=0 to (Glv.get_n_rates x)-1 do
          for state=0 to (Glv.get_n_states x)-1 do
            site_like := !site_like +.
              statd.{state}
            *. (Glv.get_a x ~rate ~site ~state)
            *. (Glv.get_a y ~rate ~site ~state)
            *. (Glv.get_a z ~rate ~site ~state)
          done;
        done;
        if 0. >= !site_like then
          failwith (Printf.sprintf "Site %d has zero likelihood." site);
        ll_tot := !ll_tot
        +. log(!site_like /. f_n_rates)
        +. log_of_2 *.
          (float_of_int (x.Glv.e.{site} + y.Glv.e.{site} + z.Glv.e.{site}))
      done;
      !ll_tot

end

module Glv_edge = Glv_edge.Make(Model)
module Glv_arr = Glv_arr.Make(Model)

let init_of_prefs ref_dir_complete prefs ref_align =
  let opt_transitions = match Prefs.stats_fname prefs with
    | s when s = "" ->
      Printf.printf
        "NOTE: you have not specified a stats file. I'm using the %s model.\n"
        (Prefs.model_name prefs);
      None
    | _ -> Parse_stats.parse_stats ref_dir_complete prefs
  in
  if Alignment.is_nuc_align ref_align && (Prefs.model_name prefs) <> "GTR" then
    failwith "You have given me what appears to be a nucleotide alignment, but have specified a model other than GTR. I only know GTR for nucleotides!";
  Glvm.Gmix_model
    ((Prefs.model_name prefs),
     (Prefs.emperical_freqs prefs),
     opt_transitions,
     (Gamma.discrete_gamma
        (Prefs.gamma_n_cat prefs) (Prefs.gamma_alpha prefs)))

(* deprecated now *)
let init_of_stats_fname prefs stats_fname ref_align =
  prefs.Prefs.stats_fname := stats_fname;
  init_of_prefs "" prefs ref_align

let init_of_json json_fname ref_align =
  let o = Simple_json.of_file json_fname in
  let model_name = (Simple_json.find_string o "subs_model") in
  if Alignment.is_nuc_align ref_align && model_name <> "GTR" then
    failwith "You have given me what appears to be a nucleotide alignment, but have specified a model other than GTR. I only know GTR for nucleotides!";
  if "gamma" <> Simple_json.find_string o "ras_model" then
    failwith "For the time being, we only support gamma rates-across-sites model.";
  let gamma_o = Simple_json.find o "gamma" in
  let opt_transitions =
    if Simple_json.mem o "subs_rates" then begin
      let subs_rates_o = Simple_json.find o "subs_rates" in
      Some [|
        Simple_json.find_float subs_rates_o "ac";
        Simple_json.find_float subs_rates_o "ag";
        Simple_json.find_float subs_rates_o "at";
        Simple_json.find_float subs_rates_o "cg";
        Simple_json.find_float subs_rates_o "ct";
        Simple_json.find_float subs_rates_o "gt";
           |]
    end
    else None
  in
  Glvm.Gmix_model
    (model_name,
     (Simple_json.find_bool o "empirical_frequencies"),
     opt_transitions,
     (Gamma.discrete_gamma
        (Simple_json.find_int gamma_o "n_cats")
        (Simple_json.find_float gamma_o "alpha")))

