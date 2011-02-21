(* A specl is a specification list, which gets passed to Arg.parse_argv or
 * wrap_parse_argv. It specifies the options and the actions which are assocated
 * with those options.
*)

open MapsSets

let option_rex = Str.regexp "-.*"

(* print the commands available through cmd_map *)
let print_avail_cmds prg_name cmd_map =
  print_endline "Here is a list of commands available using this interface:";
  StringMap.iter (fun k v -> Printf.printf "\t%s\t" k; v []) cmd_map;
  Printf.printf
    "To get more help about a given command, type %s COMMAND --help\n"
    prg_name;
  ()

(* given an argl, process a subcommand *)
let process_cmd prg_name cmd_map argl =
  let print_need_cmd_error () =
    Printf.printf
      "please specify a %s command, e.g. %s COMMAND [...]"
      prg_name prg_name;
    print_avail_cmds prg_name cmd_map;
    exit 1
  in
  match argl with
    | s::_ ->
      if StringMap.mem s cmd_map then
        (StringMap.find s cmd_map) argl
      else if Str.string_match option_rex s 0 then
        print_need_cmd_error ()
      else begin
        print_endline ("Unknown "^prg_name^" command: "^s);
        print_avail_cmds prg_name cmd_map;
        exit 1
      end
    | [] -> print_need_cmd_error ()



(* externally facing *)

(* this takes an argument list, a specification list, and a usage string, does
 * the relevant parsing, and then spits out a list of anonymous arguments (those
 * not associated with command line flags. Note that one of the purposes here is
 * to mutate the prefs that are in specl, so this needs to get run first before
 * actually using any prefs.
 * *)
let wrap_parse_argv argl specl usage =
  let anonymous = ref [] in
  try
    Arg.parse_argv
      ~current:(ref 0) (* start from beginning *)
      (Array.of_list argl)
      specl
      (fun s -> anonymous := s::!anonymous)
      usage;
    (* we assume that some anonymous argument are needed *)
    if !anonymous = [] then begin
      print_endline usage;
      exit 0;
    end;
    List.rev !anonymous
  with
  | Arg.Bad s -> print_string s; exit 1
  | Arg.Help s -> print_string s; []

(* Makes a specification with a default value.
spec_with_default "--gray-level" (fun o -> Arg.Set_int o) prefs.gray_level
"Specify the amount of gray to mix into the color scheme. Default is %d.";
 * *)
let spec_with_default symbol setfun p help =
  (symbol, setfun p, Printf.sprintf help !p)

(* given a (string, f) list, make a map of it *)
let cmd_map_of_list l =
  List.fold_right (fun (k,v) -> StringMap.add k v) l StringMap.empty

(* intended to be the inner loop of a function *)
let inner_loop ~prg_name ~version cmd_map =
  Arg.parse
    [
      "-v", Arg.Unit (fun () -> Printf.printf "placeutil %s\n" version),
      "Print version and exit";
      "--cmds", Arg.Unit (fun () -> print_avail_cmds prg_name cmd_map),
      "Print a list of the available commands.";
    ]
    (fun _ -> (* anonymous args. tl to remove command name. *)
      process_cmd prg_name cmd_map (List.tl (Array.to_list Sys.argv));
      exit 0) (* need to exit to avoid processing the other anon args as cmds *)
    (Printf.sprintf
      "Type %s --cmds to see the list of available commands."
      prg_name)
