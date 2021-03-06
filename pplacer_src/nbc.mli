open Ppatteries

exception Invalid_base of char

val bases: string
val informative: char -> bool
val word_to_int: string -> int
val int_to_word: ?word_length:int -> int -> string
val gen_count_by_seq: int -> (int -> unit) -> string -> unit

val max_word_length: int
val random_winner_max_index: ('a, 'b, 'c) Bigarray.Array1.t -> int

module Preclassifier: sig
  type 'a t
  exception Tax_id_not_found of Tax_id.t
  val make: (int, 'a) Bigarray.kind -> int -> Tax_id.t array -> 'a t
  val tax_id_idx: 'a t -> Tax_id.t -> int
  val add_seq: 'a t -> Tax_id.t -> string -> unit
end

module Classifier: sig
  type t
  type rank = Rank of int | Auto_rank | All_ranks
  val make: ?n_boot:int -> ?map_file:(Unix.file_descr * bool) -> ?rng:Random.State.t -> 'a Preclassifier.t -> t
  val classify: t -> ?like_rdp:bool -> ?random_tie_break:bool -> string -> Tax_id.t
  val bootstrap: t -> ?like_rdp:bool -> ?random_tie_break:bool -> string -> float Tax_id.TaxIdMap.t
  val of_refpkg:
    ?ref_aln:Alignment.t -> ?n_boot:int -> ?map_file:(Unix.file_descr * bool) -> ?rng:Random.State.t ->
    int -> rank -> Refpkg.t -> t
end
