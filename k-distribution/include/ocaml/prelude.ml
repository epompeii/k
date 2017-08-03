open Constants

module KMap = Map.Make(K)
module KSet = Set.Make(K)

open Constants.K
type k = K.t

(* this is needed so that statically linked binary will contain this module that is needed by dynamically linked realdef *)
let _ = Gc.stat

exception Stuck of k
exception Not_implemented

let interned_bottom = [Bottom]

module MemoKey = struct
  type t = k list
  let compare c1 c2 = compare_klist c1 c2
end

module Memo = Map.Make(MemoKey)

module KIdentityHash = struct
  type t = k
  let equal = equal_k
  let hash = Hashtbl.hash_param 1000 1000
end

type step_function = StepFunc of (k -> (k * step_function))

module KIdentityHashtbl = Hashtbl.Make(KIdentityHash)

module KMemoIdentityHash = struct
  type t = k
  let equal = equal_k
  let hash = hash_k_param 900
end

module KMemoIdentityHashtbl = Hashtbl.Make(KMemoIdentityHash)

module GuardElt = struct
  type t = Guard of int
  let compare c1 c2 = match c1 with Guard(i1) -> match c2 with Guard(i2) -> i2 - i1
end
module Guard = Set.Make(GuardElt)
let freshCounter : Z.t ref = ref Z.zero
let isTrue(c: k) : bool = match c with
| ([(Bool true)]) -> true
| _ -> false
let rec list_range (c: k list * int * int) : k list = match c with
| (_, 0, 0) -> []
| (head :: tail, 0, len) -> head :: list_range(tail, 0, len - 1)
| (_ :: tail, n, len) -> list_range(tail, n - 1, len)
| ([], _, _) -> raise(Failure "list_range")
let float_to_string (f: Gmp.FR.t) : string = if Gmp.FR.is_nan f then "NaN" else if Gmp.FR.is_inf f then if Gmp.FR.sgn f > 0 then "Infinity" else "-Infinity" else Gmp.FR.to_string_base_digits Gmp.GMP_RNDN 10 0 f
let precise_float_to_string (f,p,e) = float_to_string(f) ^ "p" ^ string_of_int p ^ "x" ^ string_of_int e
let k_of_list lbl l = match l with
  [] -> denormalize (KApply((unit_for lbl),[]))
| hd :: tl -> List.fold_left (fun list el -> denormalize (KApply(lbl, [list] :: [denormalize (KApply((el_for lbl),[el]))] :: []))) (denormalize (KApply((el_for lbl),[hd]))) tl
let k_of_set lbl s = if (KSet.cardinal s) = 0 then denormalize (KApply((unit_for lbl),[])) else
  let hd = KSet.choose s in KSet.fold (fun el set -> denormalize (KApply(lbl, [set] :: [denormalize (KApply((el_for lbl),[el]))] :: []))) (KSet.remove hd s) (denormalize (KApply((el_for lbl),[hd])))
let k_of_map lbl m = if (KMap.cardinal m) = 0 then denormalize (KApply((unit_for lbl),[])) else
  let (k,v) = KMap.choose m in KMap.fold (fun k v map -> denormalize (KApply(lbl, [map] :: [denormalize (val_for lbl k v)] :: []))) (KMap.remove k m) (denormalize (val_for lbl k v))
let k_of_array sort a = let uuid = Uuidm.create `V4 in
  fst (Dynarray.fold_left (fun (res,i) elt -> match elt with [Bottom] -> res,(Z.add i Z.one) | _ -> (denormalize(KApply((el_for_array sort),[[res]; [Int i]; elt]))),(Z.add i Z.one)) ((denormalize(KApply((unit_for_array sort), [[String (Uuidm.to_string uuid)]; [Int (Z.of_int (Dynarray.length a))]]))),Z.zero) a)
let k_char_escape (buf: Buffer.t) (c: char) : unit = match c with
| '"' -> Buffer.add_string buf "\\\""
| '\\' -> Buffer.add_string buf "\\\\"
| '\n' -> Buffer.add_string buf "\\n"
| '\t' -> Buffer.add_string buf "\\t"
| '\r' -> Buffer.add_string buf "\\r"
| _ when let code = Char.code c in code >= 32 && code < 127 -> Buffer.add_char buf c
| _ -> Buffer.add_string buf (Printf.sprintf "\\x%02x" (Char.code c))
let k_string_escape str =
  let buf = Buffer.create (String.length str) in
  String.iter (k_char_escape buf) str; Buffer.contents buf
let print_k_binary (c: k) : string =  let buf = Buffer.create 16 in
  let ktoken_code = "\x01" in
  let kapply_code = "\x02" in
  let ksequence_code = "\x03" in
  let injectedklabel_code = "\x06" in
  let end_code = "\x07" in
  let backreference_code = "\x08" in
  let table_size = (1 lsl 18) in
  let intern = Hashtbl.create 16 in
  let k_intern = KIdentityHashtbl.create table_size in
  let terms_visited = ref 0 in
  let print_int (i: int) : unit =
    let one = (i lsr 24) land 0xff in
    let two = (i lsr 16) land 0xff in
    let three = (i lsr 8) land 0xff in
    let four = (i lsr 0) land 0xff in
    Buffer.add_char buf (Char.chr one);
    Buffer.add_char buf (Char.chr two);
    Buffer.add_char buf (Char.chr three);
    Buffer.add_char buf (Char.chr four) in
  let print_string (s: string) : unit =
    let idx = try Hashtbl.find intern s with Not_found -> Hashtbl.length intern in
    print_int (Hashtbl.length intern - idx);
    if idx = Hashtbl.length intern then
      (print_int (String.length s);
      for i = 0 to (String.length s) - 1 do
        Buffer.add_char buf '\x00';
        Buffer.add_char buf (String.get s i)
      done;
      let new_idx = (Hashtbl.length intern) in
      assert (not (Hashtbl.mem intern s));
      Hashtbl.add intern s new_idx)
    else () in
  let add_intern (c: k) : unit =
    KIdentityHashtbl.replace k_intern c !terms_visited;
    terms_visited := !terms_visited + 1;
    if !terms_visited land (table_size - 1) = 0 then KIdentityHashtbl.clear k_intern else () in
  let rec print_klist(c: k list) : unit = match c with
  | [] -> ()
  | e::l  -> print_k e 0; print_klist l
  and print_k(c: k) (size: int) : unit = match c with
  | [] -> if size <> 1 then (Buffer.add_string buf ksequence_code; add_intern c; print_int size) else ()
  | e::l -> print_kitem(normalize e, [e]); print_k l (size + 1)
  and print_kitem = function (c, as_k) ->
  if KIdentityHashtbl.mem k_intern as_k then
    (Buffer.add_string buf backreference_code; print_int (!terms_visited - (KIdentityHashtbl.find k_intern as_k)); add_intern as_k)
  else match c with
  | KApply(klabel, klist) -> print_klist klist; Buffer.add_string buf kapply_code; add_intern as_k; print_string (print_klabel_string klabel); Buffer.add_char buf '\x00'; print_int (List.length klist)
  | KItem (KToken(sort, s)) -> Buffer.add_string buf ktoken_code; add_intern as_k; print_string s; print_string (print_sort sort)
  | KItem (InjectedKLabel(klabel)) -> Buffer.add_string buf injectedklabel_code; add_intern as_k; print_string (print_klabel_string klabel); Buffer.add_char buf '\x00'
  | KItem (Bool(b)) -> print_kitem(KItem (KToken(SortBool, string_of_bool(b))), [Bool b])
  | KItem (String(s)) -> print_kitem(KItem (KToken(SortString, "\"" ^ (k_string_escape s) ^ "\"")), [String s])
  | KItem (Int(i)) -> print_kitem(KItem (KToken(SortInt, Z.to_string(i))), [Int i])
  | KItem (Float(f,e,p)) -> print_kitem(KItem (KToken(SortFloat, precise_float_to_string(f,p,e))), [Float(f,e,p)])
  | KItem (Bottom) -> print_kitem(KApply(Lbl'Hash'Bottom, []), interned_bottom)
  | KItem (List(sort,lbl,l)) -> print_kitem(normalize (k_of_list lbl l), [List(sort,lbl,l)])
  | KItem (Set(sort,lbl,s)) -> print_kitem(normalize (k_of_set lbl s), [Set(sort,lbl,s)])
  | KItem (Map(sort,lbl,m)) -> print_kitem(normalize (k_of_map lbl m), [Map(sort,lbl,m)])
  | KItem (Array(sort,a)) -> print_kitem(normalize (k_of_array sort a), [Array(sort,a)])
  in Buffer.add_string buf "\x7fKAST\x04\x00\x01"; print_k c 0; Buffer.add_string buf end_code;
  Buffer.contents buf

let print_k (c: k) : string = let buf = Buffer.create 16 in
  let rec print_klist(c: k list) : unit = match c with
  | [] -> Buffer.add_string buf ".KList"
  | e::[] -> print_k(e)
  | e1::e2::l -> print_k(e1); Buffer.add_string buf ", "; print_klist(e2::l)
  and print_k(c: k) : unit = match c with
  | [] -> Buffer.add_string buf ".K"
  | e::[] -> print_kitem(normalize e)
  | e1::e2::l -> print_kitem(normalize e1); Buffer.add_string buf " ~> "; print_k(e2::l)
  and print_kitem(c: normal_kitem) : unit = match c with
  | KApply(klabel, klist) -> Buffer.add_string buf (print_klabel klabel); Buffer.add_char buf '('; print_klist(klist); Buffer.add_char buf ')'
  | KItem (KToken(sort, s)) -> Buffer.add_string buf "#token(\""; Buffer.add_string buf (k_string_escape s);
        Buffer.add_string buf "\", \""; Buffer.add_string buf (print_sort sort); Buffer.add_string buf "\")"
  | KItem (InjectedKLabel(klabel)) -> Buffer.add_string buf "#klabel("; Buffer.add_string buf (print_klabel klabel); Buffer.add_char buf ')'
  | KItem (Bool(b)) -> print_kitem(KItem (KToken(SortBool, string_of_bool(b))))
  | KItem (String(s)) -> print_kitem(KItem (KToken(SortString, "\"" ^ (k_string_escape s) ^ "\"")))
  | KItem (Int(i)) -> print_kitem(KItem (KToken(SortInt, Z.to_string(i))))
  | KItem (Float(f,e,p)) -> print_kitem(KItem (KToken(SortFloat, precise_float_to_string(f,p,e))))
  | KItem (Bottom) -> print_kitem(KApply(Lbl'Hash'Bottom, []))
  | KItem (List(_,lbl,l)) -> print_kitem(normalize (k_of_list lbl l))
  | KItem (Set(_,lbl,s)) -> print_kitem(normalize (k_of_set lbl s))
  | KItem (Map(_,lbl,m)) -> print_kitem(normalize (k_of_map lbl m))
  | KItem (Array(sort,a)) -> print_kitem(normalize (k_of_array sort a))
  | KItem (ThreadLocal) -> print_kitem(KApply(Lbl'Hash'ThreadLocal, []))
  | KItem (Thread(k1, k2, k3, k4)) -> print_kitem(KApply(Lbl'Hash'Thread, [k1; k2; k3; k4]))
  in print_k c; Buffer.contents buf
module Subst = Map.Make(String)
let print_subst (out: out_channel) (c: k Subst.t) : unit =
  output_string out "1\n"; Subst.iter (fun v k -> output_string out (v ^ "\n" ^ (print_k k) ^ "\n")) c
let print_subst_binary (out: out_channel) (c: k Subst.t) : unit =
  output_binary_int out 1; Subst.iter (fun v k -> output_binary_int out (String.length v); output_string out v; output_string out (print_k_binary k)) c
let emin (exp: int) (prec: int) : int = (- (1 lsl (exp - 1))) + 4 - prec
let emin_normal (exp: int) : int = (- (1 lsl (exp - 1))) + 2
let emax (exp: int) : int = 1 lsl (exp - 1)
let round_to_range (c: kitem) : kitem = match c with
    Float(f,e,p) -> let (cr, t) = (Gmp.FR.check_range p Gmp.GMP_RNDN (emin e p) (emax e) f) in Float((Gmp.FR.subnormalize cr t Gmp.GMP_RNDN),e,p)
  | _ -> raise (Invalid_argument "round_to_range")
let curr_fd : Z.t ref = ref (Z.of_int 3)
let file_descriptors = let m = Hashtbl.create 5 in Hashtbl.add m (Z.of_int 0) Unix.stdin; Hashtbl.add m (Z.of_int 1) Unix.stdout; Hashtbl.add m (Z.of_int 2) Unix.stderr; m
let default_file_perm = 0o777
let convert_open_flags (s: string) : Unix.open_flag list =
  match s with
      "r" -> [Unix.O_RDONLY]
    | "w" -> [Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CREAT]
    | "wx" -> [Unix.O_WRONLY; Unix.O_EXCL; Unix.O_CREAT]
    | "a" -> [Unix.O_WRONLY; Unix.O_APPEND; Unix.O_CREAT]
    | "rb" -> [Unix.O_RDONLY]
    | "wb" -> [Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CREAT]
    | "wbx" -> [Unix.O_WRONLY; Unix.O_EXCL; Unix.O_CREAT]
    | "ab" -> [Unix.O_WRONLY; Unix.O_APPEND; Unix.O_CREAT]
    | "r+" -> [Unix.O_RDWR]
    | "w+" -> [Unix.O_RDWR; Unix.O_TRUNC; Unix.O_CREAT]
    | "w+x" -> [Unix.O_RDWR; Unix.O_EXCL; Unix.O_CREAT]
    | "a+" -> [Unix.O_RDWR; Unix.O_APPEND; Unix.O_CREAT]
    | "r+b" | "rb+" -> [Unix.O_RDWR]
    | "w+b" | "wb+" -> [Unix.O_RDWR; Unix.O_TRUNC; Unix.O_CREAT]
    | "w+bx" | "wb+x" -> [Unix.O_RDWR; Unix.O_EXCL; Unix.O_CREAT]
    | "a+b" | "ab+" -> [Unix.O_RDWR; Unix.O_APPEND; Unix.O_CREAT]
    | _ -> raise (Invalid_argument "convert_open_flags")
let unix_error (f: unit -> k) = try f () with Unix.Unix_error(err,_,_) as ex -> match err with
| EUNKNOWNERR(i) -> [KApply1((parse_klabel "#unknownIOError"), [Int (Z.of_int i)])]
| _ -> [KApply0(parse_klabel(match err with
| E2BIG -> "#E2BIG_K-IO"
| EACCES -> "#EACCES_K-IO"
| EAGAIN -> "#EAGAIN_K-IO"
| EBADF -> "#EBADF_K-IO"
| EBUSY -> "#EBUSY_K-IO"
| ECHILD -> "#ECHILD_K-IO"
| EDEADLK -> "#EDEADLK_K-IO"
| EDOM -> "#EDOM_K-IO"
| EEXIST -> "#EEXIST_K-IO"
| EFAULT -> "#EFAULT_K-IO"
| EFBIG -> "#EFBIG_K-IO"
| EINTR -> "#EINTR_K-IO"
| EINVAL -> "#EINVAL_K-IO"
| EIO -> "#EIO_K-IO"
| EISDIR -> "#EISDIR_K-IO"
| EMFILE -> "#EMFILE_K-IO"
| EMLINK -> "#EMLINK_K-IO"
| ENAMETOOLONG -> "#ENAMETOOLONG_K-IO"
| ENFILE -> "#ENFILE_K-IO"
| ENODEV -> "#ENODEV_K-IO"
| ENOENT -> "#ENOENT_K-IO"
| ENOEXEC -> "#ENOEXEC_K-IO"
| ENOLCK -> "#ENOLCK_K-IO"
| ENOMEM -> "#ENOMEM_K-IO"
| ENOSPC -> "#ENOSPC_K-IO"
| ENOSYS -> "#ENOSYS_K-IO"
| ENOTDIR -> "#ENOTDIR_K-IO"
| ENOTEMPTY -> "#ENOTEMPTY_K-IO"
| ENOTTY -> "#ENOTTY_K-IO"
| ENXIO -> "#ENXIO_K-IO"
| EPERM -> "#EPERM_K-IO"
| EPIPE -> "#EPIPE_K-IO"
| ERANGE -> "#ERANGE_K-IO"
| EROFS -> "#EROFS_K-IO"
| ESPIPE -> "#ESPIPE_K-IO"
| ESRCH -> "#ESRCH_K-IO"
| EXDEV -> "#EXDEV_K-IO"
| EWOULDBLOCK -> "#EWOULDBLOCK_K-IO"
| EINPROGRESS -> "#EINPROGRESS_K-IO"
| EALREADY -> "#EALREADY_K-IO"
| ENOTSOCK -> "#ENOTSOCK_K-IO"
| EDESTADDRREQ -> "#EDESTADDRREQ_K-IO"
| EMSGSIZE -> "#EMSGSIZE_K-IO"
| EPROTOTYPE -> "#EPROTOTYPE_K-IO"
| ENOPROTOOPT -> "#ENOPROTOOPT_K-IO"
| EPROTONOSUPPORT -> "#EPROTONOSUPPORT_K-IO"
| ESOCKTNOSUPPORT -> "#ESOCKTNOSUPPORT_K-IO"
| EOPNOTSUPP -> "#EOPNOTSUPP_K-IO"
| EPFNOSUPPORT -> "#EPFNOSUPPORT_K-IO"
| EAFNOSUPPORT -> "#EAFNOSUPPORT_K-IO"
| EADDRINUSE -> "#EADDRINUSE_K-IO"
| EADDRNOTAVAIL -> "#EADDRNOTAVAIL_K-IO"
| ENETDOWN -> "#ENETDOWN_K-IO"
| ENETUNREACH -> "#ENETUNREACH_K-IO"
| ENETRESET -> "#ENETRESET_K-IO"
| ECONNABORTED -> "#ECONNABORTED_K-IO"
| ECONNRESET -> "#ECONNRESET_K-IO"
| ENOBUFS -> "#ENOBUFS_K-IO"
| EISCONN -> "#EISCONN_K-IO"
| ENOTCONN -> "#ENOTCONN_K-IO"
| ESHUTDOWN -> "#ESHUTDOWN_K-IO"
| ETOOMANYREFS -> "#ETOOMANYREFS_K-IO"
| ETIMEDOUT -> "#ETIMEDOUT_K-IO"
| ECONNREFUSED -> "#ECONNREFUSED_K-IO"
| EHOSTDOWN -> "#EHOSTDOWN_K-IO"
| EHOSTUNREACH -> "#EHOSTUNREACH_K-IO"
| ELOOP -> "#ELOOP_K-IO"
| EOVERFLOW -> "#EOVERFLOW_K-IO"
| EUNKNOWNERR(i) -> failwith "unreachable"
))]

let to_string_base (base: int) (i: Z.t) : string = match base with
  10 -> Z.format "%d" i
| 2 -> Z.format "%b" i
| 8 -> Z.format "%o" i
| 16 -> Z.format "%x" i
| _ -> raise Not_implemented
let to_zarith (i: Gmp.Z.t) : Z.t = Z.of_string (Gmp.Z.to_string i)
let from_zarith (i: Z.t) : Gmp.Z.t = Gmp.Z.from_string (Z.to_string i)

let deconstruct_float (f: Gmp.FR.t) (prec: int) (e: int) : bool * int * Z.t option =
 let (digits, exp) = Gmp.FR.to_string_exp_base_digits Gmp.GMP_RNDN 2 prec f in match digits with
 | "@Inf@" -> false, (emax e), Some Z.zero
 | "-@Inf@" -> true, (emax e), Some Z.zero
 | "@NaN@" -> false, (emax e), None
 | "-@NaN@" -> true, (emax e), None
 | _ -> let min_exp = emin_normal e in
 let significand = Z.abs (Z.of_string_base 2 digits) in
 let scaled_significand = if exp < min_exp then
   (Z.shift_right significand (min_exp - (exp - 1))) else
   significand in
 let true_exp = if exp < min_exp then min_exp else if exp > (emax e) then emax e else (exp - 1) in
 (String.get digits 0 = '-'), true_exp, Some scaled_significand

let float_regexp = Str.regexp "\\(.*\\)[pP]\\([0-9]+\\)[xX]\\([0-9]+\\)"

let unescape_k_string (str: string) =
  let str = String.sub str 1 (String.length str - 2) in
  Scanf.unescaped str

 let parse_float (str: string) : int * int * string =
   let (cMAX_FLOAT_PREC, cMAX_FLOAT_EXP) = (237, 19) in
  if Str.string_match float_regexp str 0 then
    let prec = int_of_string (Str.matched_group 2 str) in
    let exp = int_of_string (Str.matched_group 3 str) in
    (prec, exp, (Str.matched_group 1 str))
  else (cMAX_FLOAT_PREC, cMAX_FLOAT_EXP, str)

let ktoken (s: sort) (str: string) : kitem = match s with
| SortInt -> Int (Z.of_string str)
| SortFloat -> let (p,e,f) = parse_float str in (round_to_range(Float ((Gmp.FR.from_string_prec_base p Gmp.GMP_RNDN 10 f), e, p)))
| SortString -> String (unescape_k_string str)
| SortBool -> Bool (bool_of_string str)
| _ -> KToken(s,str)

let get_exit_code(subst: k Subst.t) : int = match (Subst.fold (fun k v res -> match (v, res) with
    [Int i], None -> Some (Z.to_int i)
  | [Int i], Some _ -> failwith "Bad exit code pattern"
  | _ -> res) subst None) with Some i -> i | _ -> failwith "Bad exit code pattern"

(* set to true if you don't want the k parser to evaluate functions.
   this is used by --ocaml-compile in order to prevent us from evaluating
   argv while marshalling data. *)
let no_parse_eval = ref false

module CONFIG =
struct
  let depth = ref (-1)
  let sys_argv = ref Sys.argv
  let output_file = ref "config"

  let set_sys_argv () =
    let has_rv_args () =
      try let _ = Sys.getenv "RV_MATCH_BINARY_FLAGS" in true
      with Not_found -> false
    in if has_rv_args () then
      let cmd = ref [Sys.argv.(0)] in
      let set_depth d = depth := d in
      let set_output_file outf = output_file := outf in
      let add_sys_argv arg = cmd := arg::!cmd in
      let anon_arg a = print_endline ("Invalid argument: " ^ a ^". Will be ignored") in
      let string_of_list l = "[" ^ String.concat "; " l ^ "]" in
    begin
      print_endline "RV_MATCH_BINARY_FLAGS is set. parsing RV_Match specific args.";
      let speclist = [
        ("--depth", Arg.Int (set_depth), "The maximum number of computational steps to execute the definition for.");
        ("--output-file", Arg.String (set_output_file), "The file to store (failing) configuration into.");
        ("--", Arg.Rest (add_sys_argv), "Command line for the program");
      ]
      in let usage_msg = "Invalid RV options. Usage:\n  " ^ Sys.argv.(0) ^ " <rv-options> -- <pgm-options>\nRV options available:"
      in Arg.parse speclist anon_arg usage_msg;
      sys_argv := Array.of_list (List.rev !cmd);
      print_endline ("Max depth: " ^ string_of_int !depth);
      print_endline ("Command line: " ^ string_of_list (List.rev !cmd));
    end
  else ()
end

module MAP =
struct

  let hook_element c lbl sort config ff = match c with
      k1, k2 -> [Map (sort,(collection_for lbl),(KMap.singleton k1 k2))]
  let hook_unit c lbl sort config ff = match c with
      () -> [Map (sort,(collection_for lbl),KMap.empty)]
  let hook_concat c lbl sort config ff = match c with
      ([Map (s,l1,k1)]), ([Map (_,l2,k2)])
        when (l1 = l2) -> [Map (s,l1,(KMap.union (fun k a b -> if a = b then Some a else raise Not_implemented) k1 k2))]
    | _ -> raise Not_implemented
  let hook_lookup c lbl sort config ff = match c with
      [Map (_,_,k1)], k2 -> (try KMap.find k2 k1 with Not_found -> interned_bottom)
    | [Bottom], k2 -> interned_bottom
    | _ -> raise Not_implemented
  let hook_lookupOrDefault c lbl sort config ff = match c with
      [Map (_,_,k1)], k2, k3 -> (try KMap.find k2 k1 with Not_found -> k3)
    | [Bottom], k2, k3 -> k3
    | _ -> raise Not_implemented
  let hook_update c lbl sort config ff = match c with
      [Map (s,l,k1)], k, v -> [Map (s,l,(KMap.add k v k1))]
    | _ -> raise Not_implemented
  let hook_remove c lbl sort config ff = match c with
      [Map (s,l,k1)], k2 -> [Map (s,l,(KMap.remove k2 k1))]
    | _ -> raise Not_implemented
  let hook_difference c lbl sort config ff = match c with
      [Map (s,l1,k1)], [Map (_,l2,k2)]
        when (l1 = l2) -> [Map (s,l1,(KMap.filter (fun k v -> try (compare (KMap.find k k2) v) <> 0 with Not_found -> true) k1))]
    | _ -> raise Not_implemented
  let hook_keys c lbl sort config ff = match c with
      [Map (_,_,k1)] -> [Set (SortSet, Lbl_Set_,(KMap.fold (fun k v -> KSet.add k) k1 KSet.empty))]
    | _ -> raise Not_implemented
  let hook_keys_list c lbl sort config ff = match c with
      [Map (_,_,k1)] -> [List (SortList, Lbl_List_,(match List.split (KMap.bindings k1) with l, _ -> l))]
    | _ -> raise Not_implemented
  let hook_in_keys c lbl sort config ff = match c with
      (k1, [Map (_,_,k2)]) -> [Bool (KMap.mem k1 k2)]
    | (k1, [Bottom]) -> [Bool false] (* case is useful for double map lookup *)
    | _ -> raise Not_implemented
  let hook_values c lbl sort config ff = match c with
      [Map (_,_,k1)] -> [List (SortList, Lbl_List_,(match List.split (KMap.bindings k1) with (_,vs) -> vs))]
    | _ -> raise Not_implemented
  let hook_choice c lbl sort config ff = match c with
      [Map (_,_,k1)] -> (match KMap.choose k1 with (k, _) -> k)
    | _ -> raise Not_implemented
  let hook_size c lbl sort config ff = match c with
      [Map (_,_,m)] -> [Int (Z.of_int (KMap.cardinal m))]
    | _ -> raise Not_implemented
  let hook_inclusion c lbl sort config ff = match c with
      [Map (s,l1,k1)], [Map (_,l2,k2)]
        when (l1 = l2) -> [Bool (KMap.for_all (fun k v -> try (compare (KMap.find k k2) v) = 0 with Not_found -> false) k1)]
    | _ -> raise Not_implemented
  let hook_updateAll c lbl sort config ff = match c with
      ([Map (s,l1,k1)]), ([Map (_,l2,k2)])
        when (l1 = l2) -> [Map (s,l1,(KMap.union (fun k a b -> match a, b with
                          _, v -> Some v) k1 k2))]
    | _ -> raise Not_implemented
  let hook_removeAll c lbl sort config ff = match c with
      [Map (s,l,k1)], [Set (_,_,k2)] -> [Map (s,l,KMap.filter (fun k v -> not (KSet.mem k k2)) k1)]
    | _ -> raise Not_implemented
end

module SET =
struct
  let hook_in c lbl sort config ff = match c with
      k1, [Set (_,_,k2)] -> [Bool (KSet.mem k1 k2)]
    | _ -> raise Not_implemented
  let hook_unit c lbl sort config ff = match c with
      () -> [Set (sort,(collection_for lbl),KSet.empty)]
  let hook_element c lbl sort config ff = match c with
      k -> [Set (sort,(collection_for lbl),(KSet.singleton k))]
  let hook_concat c lbl sort config ff = match c with
      [Set (sort,l1,s1)], [Set (_,l2,s2)] when (l1 = l2) -> [Set (sort,l1,(KSet.union s1 s2))]
    | _ -> raise Not_implemented
  let hook_difference c lbl sort config ff = match c with
      [Set (s,l1,k1)], [Set (_,l2,k2)] when (l1 = l2) -> [Set (s,l1,(KSet.diff k1 k2))]
    | _ -> raise Not_implemented
  let hook_inclusion c lbl sort config ff = match c with
      [Set (s,l1,k1)], [Set (_,l2,k2)] when (l1 = l2) -> [Bool (KSet.subset k1 k2)]
    | _ -> raise Not_implemented
  let hook_intersection c lbl sort config ff = match c with
      [Set (s,l1,k1)], [Set (_,l2,k2)] when (l1 = l2) -> [Set (s,l1,(KSet.inter k1 k2))]
    | _ -> raise Not_implemented
  let hook_choice c lbl sort config ff = match c with
      [Set (_,_,k1)] -> KSet.choose k1
    | _ -> raise Not_implemented
  let hook_size c lbl sort config ff = match c with
      [Set (_,_,s)] -> [Int (Z.of_int (KSet.cardinal s))]
    | _ -> raise Not_implemented
  let hook_set2list c lbl sort config ff = match c with
      [Set (_,_,s)] -> [List (SortList,Lbl_List_, (KSet.elements s))]
    | _ -> raise Not_implemented
  let hook_list2set c lbl sort config ff = match c with
      [List (_,_,l)] -> [Set (SortSet,Lbl_Set_, (KSet.of_list l))]
    | _ -> raise Not_implemented
end

module LIST =
struct
  let hook_unit c lbl sort config ff = match c with
      () -> [List (sort,(collection_for lbl),[])]
  let hook_element c lbl sort config ff = match c with
      k -> [List (sort,(collection_for lbl),[k])]
  let hook_concat c lbl sort config ff = match c with
      [List (s,lbl1,l1)], [List (_,lbl2,l2)] when (lbl1 = lbl2) -> [List (s,lbl1,(l1 @ l2))]
    | _ -> raise Not_implemented
  let hook_in c lbl sort config ff = match c with
      k1, [List (_,_,k2)] -> [Bool (List.mem k1 k2)]
    | _ -> raise Not_implemented
  let hook_get c lbl sort config ff = match c with
      [List (_,_,l1)], [Int i] ->
        let i = Z.to_int i in (try if i >= 0 then List.nth l1 i else List.nth l1 ((List.length l1) + i)
                               with Failure _ -> interned_bottom | Invalid_argument _ -> interned_bottom)
    | _ -> raise Not_implemented
  let hook_range c lbl sort config ff = match c with
      [List (s,lbl,l1)], [Int i1], [Int i2] ->
        (try [List (s,lbl,(list_range (l1, (Z.to_int i1), (List.length(l1) - (Z.to_int i2) - (Z.to_int i1)))))]
         with Failure _ -> interned_bottom)
    | _ -> raise Not_implemented
  let hook_size c lbl sort config ff = match c with
      [List (_,_,l)] -> [Int (Z.of_int (List.length l))]
    | _ -> raise Not_implemented
end

module ARRAY =
struct
  let hook_make c lbl sort config ff = match c with
      [Int len], k -> [Array (sort,(Dynarray.make (Z.to_int len) k))]
    | _ -> raise Not_implemented
  let hook_makeEmpty c lbl sort config ff = match c with
      [Int len] -> [Array (sort,(Dynarray.make (Z.to_int len) interned_bottom))]
    | _ -> raise Not_implemented
  let hook_lookup c lbl sort config ff = match c with
      [Array (_,a)], [Int idx] -> (try Dynarray.get a (Z.to_int idx) with Invalid_argument _ | Z.Overflow -> interned_bottom)
    | _ -> raise Not_implemented
  let hook_update c lbl sort config ff = match c with
      [Array (_,a)] as value, [Int i], k -> (try Dynarray.set a (Z.to_int i) k with Invalid_argument _ | Z.Overflow -> ()); value
    | _ -> raise Not_implemented
  let hook_remove c lbl sort config ff = match c with
      [Array (_,a)] as value, [Int i] -> (try Dynarray.set a (Z.to_int i) interned_bottom with Invalid_argument _ | Z.Overflow -> ()); value
    | _ -> raise Not_implemented
  let hook_updateAll c lbl sort config ff = match c with
      [Array (s,a)] as value, [Int i], [List (_,_,l)] -> List.iteri (fun j elt -> try Dynarray.set a (j + (Z.to_int i)) elt with Invalid_argument _ | Z.Overflow -> ()) l; value
    | _ -> raise Not_implemented
  let hook_in_keys c lbl sort config ff = match c with
      [Int i], [Array (_,a)] -> [Bool (try (match Dynarray.get a (Z.to_int i) with [Bottom] -> false | _ -> true) with Invalid_argument _ | Z.Overflow -> false)]
    | _ -> raise Not_implemented

  let hook_ctor c lbl sort config ff = match c with
      _, [Int len] -> [Array (sort,(Dynarray.make (Z.to_int len) interned_bottom))]
    | _ -> raise Not_implemented
end

module KREFLECTION =
struct
  let hook_sort c lbl sort config ff = match c with

      [KToken (sort, s)] -> [String (print_sort(sort))]
    | [Int _] -> [String "Int"]
    | [String _] -> [String "String"]
    | [Bool _] -> [String "Bool"]
    | [Map (s,_,_)] -> [String (print_sort s)]
    | [List (s,_,_)] -> [String (print_sort s)]
    | [Set (s,_,_)] -> [String (print_sort s)]
    | _ -> raise Not_implemented
  let hook_getKLabel c lbl sort config ff = match c with
      [k] -> (match (normalize k) with KApply (lbl, _) -> [InjectedKLabel lbl] | _ -> interned_bottom)
    | _ -> interned_bottom
  let hook_configuration c lbl sort config ff = match c with
      () -> config
  let hook_fresh c lbl sort config ff = match c with
      [String sort] -> let res = ff sort config !freshCounter in freshCounter := Z.add !freshCounter Z.one; res
    | _ -> raise Not_implemented
  let hook_getenv c lbl sort config ff = match c with
      [String key] -> [String (Sys.getenv key)]
    | _ -> raise Not_implemented
  let hook_argv c lbl sort config ff = match c with
      () -> [List (SortList, Lbl_List_,(Array.fold_right (fun arg res -> [String arg] :: res) !CONFIG.sys_argv []))]
end

module KEQUAL =
struct
  let hook_eq c lbl sort config ff = match c with
      k1, k2 -> [Bool ((compare k1 k2) = 0)]
  let hook_ne c lbl sort config ff = match c with
      k1, k2 -> [Bool ((compare k1 k2) <> 0)]
  let hook_ite c lbl sort config ff = match c with
      [Bool t], k1, k2 -> if t then k1 else k2
    | _ -> raise Not_implemented
end

module IO =
struct
  let hook_close c lbl sort config ff = match c with
      [Int i] -> unix_error (fun () -> Unix.close (Hashtbl.find file_descriptors i); [])
    | _ -> raise Not_implemented
  let hook_getc c lbl sort config ff = match c with
      [Int i] -> unix_error (fun () -> let b = Bytes.create 1 in match Unix.read (Hashtbl.find file_descriptors i) b 0 1 with
          0 -> [Int (Z.of_int (-1))]
        | _ -> [Int (Z.of_int (Char.code (Bytes.get b 0)))])
    | _ -> raise Not_implemented
  let hook_open c lbl sort config ff = match c with
      [String path], [String flags] ->
        unix_error (fun () -> let fd = Unix.openfile path (convert_open_flags flags) default_file_perm in
          let fd_int = !curr_fd in Hashtbl.add file_descriptors fd_int fd; curr_fd := (Z.add fd_int Z.one); [Int fd_int])
    | _ -> raise Not_implemented
  let hook_putc c lbl sort config ff = match c with
      [Int fd], [Int c] -> unix_error (fun () -> let _ = Unix.write (Hashtbl.find file_descriptors fd) (Bytes.make 1 (Char.chr (Z.to_int c))) 0 1 in [])
    | _ -> raise Not_implemented
  let hook_read c lbl sort config ff = match c with
      [Int fd], [Int len] -> unix_error (fun () -> let l = (Z.to_int len) in
        let b = Bytes.create l in let _ = Unix.read (Hashtbl.find file_descriptors fd) b 0 l in [String (Bytes.to_string b)])
    | _ -> raise Not_implemented
  let hook_seek c lbl sort config ff = match c with
      [Int fd], [Int off] -> unix_error (fun () -> let o = (Z.to_int off) in let _ = Unix.lseek (Hashtbl.find file_descriptors fd) o Unix.SEEK_SET in [])
    | _ -> raise Not_implemented
  let hook_seekEnd c lbl sort config ff = match c with
      [Int fd], [Int off] -> unix_error (fun () -> let o = (Z.to_int off) in let _ = Unix.lseek (Hashtbl.find file_descriptors fd) o Unix.SEEK_END in [])
    | _ -> raise Not_implemented
  let hook_tell c lbl sort config ff = match c with
      [Int fd] -> unix_error (fun () -> [Int (Z.of_int (Unix.lseek (Hashtbl.find file_descriptors fd) 0 Unix.SEEK_CUR))])
    | _ -> raise Not_implemented
  let hook_write c lbl sort config ff = match c with
      [Int fd], [String s] -> unix_error (fun () -> let b = Bytes.of_string s in let _ = Unix.write (Hashtbl.find file_descriptors fd) b 0 (Bytes.length b) in [])
    | _ -> raise Not_implemented

  let hook_stat c lbl sort config ff = raise Not_implemented
  let hook_lstat c lbl sort config ff = raise Not_implemented
  let hook_opendir c lbl sort config ff = raise Not_implemented
  let hook_parse c lbl sort config ff = raise Not_implemented
  let hook_parseInModule c lbl sort config ff = raise Not_implemented
  let hook_system c lbl sort config ff = raise Not_implemented
end

module BOOL =
struct
  let hook_and c lbl sort config ff = match c with
      [Bool b1], [Bool b2] -> [Bool (b1 && b2)]
    | _ -> raise Not_implemented
  let hook_andThen = hook_and
  let hook_or c lbl sort config ff = match c with
      [Bool b1], [Bool b2] -> [Bool (b1 || b2)]
    | _ -> raise Not_implemented
  let hook_orElse = hook_or
  let hook_not c lbl sort config ff = match c with
      [Bool b1] -> [Bool (not b1)]
    | _ -> raise Not_implemented
  let hook_implies c lbl sort config ff = match c with
      [Bool b1], [Bool b2] -> [Bool ((not b1) || b2)]
    | _ -> raise Not_implemented
  let hook_ne c lbl sort config ff = match c with
      [Bool b1], [Bool b2] -> [Bool (b1 <> b2)]
    | _ -> raise Not_implemented
  let hook_eq c lbl sort config ff = match c with
      [Bool b1], [Bool b2] -> [Bool (b1 = b2)]
    | _ -> raise Not_implemented
  let hook_xor = hook_ne
end

module STRING =
struct
  let hook_concat c lbl sort config ff = match c with
      [String s1], [String s2] -> [String (s1 ^ s2)]
    | _ -> raise Not_implemented
  let hook_lt c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool ((String.compare s1 s2) < 0)]
    | _ -> raise Not_implemented
  let hook_le c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool ((String.compare s1 s2) <= 0)]
    | _ -> raise Not_implemented
  let hook_gt c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool ((String.compare s1 s2) > 0)]
    | _ -> raise Not_implemented
  let hook_ge c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool ((String.compare s1 s2) >= 0)]
    | _ -> raise Not_implemented
  let hook_eq c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool (s1 = s2)]
    | _ -> raise Not_implemented
  let hook_ne c lbl sort config ff = match c with
      [String s1], [String s2] -> [Bool (s1 <> s2)]
    | _ -> raise Not_implemented
  let hook_chr c lbl sort config ff = match c with
      [Int i] -> [String (String.make 1 (Char.chr (Z.to_int i)))]
    | _ -> raise Not_implemented
  let hook_find c lbl sort config ff = match c with
      [String s1], [String s2], [Int i] ->
        (try [Int (Z.of_int (Str.search_forward (Str.regexp_string s2) s1 (Z.to_int i)))]
        with Not_found -> [Int (Z.of_int (-1))])
    | _ -> raise Not_implemented
  let hook_rfind c lbl sort config ff = match c with
      [String s1], [String s2], [Int i] ->
        (try [Int (Z.of_int (Str.search_backward (Str.regexp_string s2) s1 (Z.to_int i)))]
        with Not_found -> [Int (Z.of_int (-1))])
    | _ -> raise Not_implemented
  let hook_length c lbl sort config ff = match c with
      [String s] -> [Int (Z.of_int (String.length s))]
    | _ -> raise Not_implemented
  let hook_substr c lbl sort config ff = match c with
      [String s], [Int i1], [Int i2] -> [String (String.sub s (Z.to_int i1) (Z.to_int (Z.sub i2 i1)))]
    | _ -> raise Not_implemented
  let hook_ord c lbl sort config ff = match c with
      [String s] -> [Int (Z.of_int (Char.code (String.get s 0)))]
    | _ -> raise Not_implemented
  let hook_int2string c lbl sort config ff = match c with
      [Int i] -> [String (Z.to_string i)]
    | _ -> raise Not_implemented
  let hook_string2int c lbl sort config ff = match c with
      [String s] -> [Int (Z.of_string s)]
    | _ -> raise Not_implemented
  let hook_string2base c lbl sort config ff = match c with
      [String s], [Int i] -> [Int (Z.of_string_base (Z.to_int i) s)]
    | _ -> raise Not_implemented
  let hook_base2string c lbl sort config ff = match c with
      [Int i], [Int base] -> [String (to_string_base (Z.to_int base) i)]
    | _ -> raise Not_implemented
  let hook_string2token c lbl sort config ff = match c with
      [String sort], [String value] -> [ktoken (parse_sort sort) value]
    | _ -> raise Not_implemented
  let hook_token2string c lbl sort config ff = match c with
      [KToken(_,s)] -> [String s]
    | [Bool b] -> [String (string_of_bool b)]
    | [String s] -> [String ("\"" ^ (k_string_escape s) ^ "\"")]
    | [Int i] -> [String (Z.to_string i)]
    | [Float(f,p,e)] -> [String (precise_float_to_string (f,e,p))]
    | _ -> raise Not_implemented
  let hook_float2string c lbl sort config ff = match c with
      [Float (f,_,_)] -> [String (Gmp.FR.to_string_base_digits Gmp.GMP_RNDN 10 0 f)]
    | _ -> raise Not_implemented
  let hook_uuid c lbl sort config ff = match c with
      () -> let uuid = Uuidm.create `V4 in
      [String (Uuidm.to_string uuid)]
  let hook_floatFormat c lbl sort config ff = raise Not_implemented
  let hook_string2float c lbl sort config ff = raise Not_implemented
  let hook_replace c lbl sort config ff = raise Not_implemented
  let hook_replaceAll c lbl sort config ff = raise Not_implemented
  let hook_replaceFirst c lbl sort config ff = raise Not_implemented
  let hook_countAllOccurrences c lbl sort config ff = raise Not_implemented
  let hook_category c lbl sort config ff = raise Not_implemented
  let hook_directionality c lbl sort config ff = raise Not_implemented
  let hook_findChar c lbl sort config ff = raise Not_implemented
  let hook_rfindChar c lbl sort config ff = raise Not_implemented
end

open Gmp.RNG

module INT =
struct
  let hook_tmod c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.rem a b)]
    | _ -> raise Not_implemented
  let hook_add c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.add a b)]
    | _ -> raise Not_implemented
  let hook_le c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (Z.leq a b)]
    | _ -> raise Not_implemented
  let hook_eq c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (Z.equal a b)]
    | _ -> raise Not_implemented
  let hook_ne c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (not (Z.equal a b))]
    | _ -> raise Not_implemented
  let hook_and c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.logand a b)]
    | _ -> raise Not_implemented
  let hook_mul c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.mul a b)]
    | _ -> raise Not_implemented
  let hook_sub c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.sub a b)]
    | _ -> raise Not_implemented
  let hook_tdiv c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.div a b)]
    | _ -> raise Not_implemented
  let hook_shl c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.shift_left a (Z.to_int b))]
    | _ -> raise Not_implemented
  let hook_lt c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (Z.lt a b)]
    | _ -> raise Not_implemented
  let hook_ge c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (Z.geq a b)]
    | _ -> raise Not_implemented
  let hook_shr c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.shift_right a (Z.to_int b))]
    | _ -> raise Not_implemented
  let hook_gt c lbl sort config ff = match c with
      [Int a], [Int b] -> [Bool (Z.gt a b)]
    | _ -> raise Not_implemented
  let hook_pow c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.pow a (Z.to_int b))]
    | _ -> raise Not_implemented
  let hook_powmod c lbl sort config ff = match c with
      [Int a], [Int b], [Int c]-> [Int (Z.powm a b c)]
    | _ -> raise Not_implemented
  let hook_xor c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.logxor a b)]
    | _ -> raise Not_implemented
  let hook_or c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.logor a b)]
    | _ -> raise Not_implemented
  let hook_not c lbl sort config ff = match c with
      [Int a] -> [Int (Z.lognot a)]
    | _ -> raise Not_implemented
  let hook_abs c lbl sort config ff = match c with
      [Int a] -> [Int (Z.abs a)]
    | _ -> raise Not_implemented
  let hook_max c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.max a b)]
    | _ -> raise Not_implemented
  let hook_min c lbl sort config ff = match c with
      [Int a], [Int b] -> [Int (Z.min a b)]
    | _ -> raise Not_implemented
  let hook_rand c lbl sort config ff = match c with
      [Int max] -> let mpz = Gmp.Z.urandomm Gmp.RNG.default (from_zarith max) in
          [Int (to_zarith mpz)]
    | _ -> raise Not_implemented
  let hook_srand c lbl sort config ff = match c with
      [Int seed] -> let () = Gmp.Z.randseed Gmp.RNG.default (from_zarith seed) in []
    | _ -> raise Not_implemented
  let hook_ediv c lbl sort config ff = raise Not_implemented
  let hook_emod c lbl sort config ff = raise Not_implemented
end

module FLOAT =
struct
  let hook_isNaN c lbl sort config ff = match c with
      [Float (f,_,_)] -> [Bool (Gmp.FR.is_nan f)]
    | _ -> raise Not_implemented
  let hook_maxValue c lbl sort config ff = match c with
      [Int prec], [Int exp] -> let e = Z.to_int exp and p = Z.to_int prec in
        [round_to_range(Float ((Gmp.FR.nexttoward (emin e p) (emax e) (Gmp.FR.from_string_prec_base p Gmp.GMP_RNDN 10 "inf") Gmp.FR.zero),e,p))]
    | _ -> raise Not_implemented
  let hook_minValue c lbl sort config ff = match c with
      [Int prec], [Int exp] -> let e = Z.to_int exp and p = Z.to_int prec in
        [round_to_range(Float ((Gmp.FR.nexttoward (emin e p) (emax e) Gmp.FR.zero (Gmp.FR.from_string_prec_base p Gmp.GMP_RNDN 10 "inf")),e,p))]
    | _ -> raise Not_implemented
  let hook_round c lbl sort config ff = match c with
      [Float (f,_,_)], [Int prec], [Int exp] ->
        [round_to_range (Float (f,(Z.to_int exp),(Z.to_int prec)))]
    | _ -> raise Not_implemented
  let hook_abs c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.abs_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_ceil c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.rint_prec p Gmp.GMP_RNDU f),e,p))]
    | _ -> raise Not_implemented
  let hook_floor c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.rint_prec p Gmp.GMP_RNDD f),e,p))]
    | _ -> raise Not_implemented
  let hook_acos c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.acos_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_asin c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.asin_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_atan c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.atan_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_cos c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.cos_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_sin c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.sin_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_tan c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.tan_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_exp c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.exp_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_log c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.log_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_neg c lbl sort config ff = match c with
      [Float (f,e,p)] -> [round_to_range(Float ((Gmp.FR.neg_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_add c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)]
        when e1 = e2 && p1 = p2 -> [round_to_range(Float ((Gmp.FR.add_prec p1 Gmp.GMP_RNDN f1 f2),e1,p1))]
    | _ -> raise Not_implemented
  let hook_sub c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)]
        when e1 = e2 && p1 = p2 -> [round_to_range(Float ((Gmp.FR.sub_prec p1 Gmp.GMP_RNDN f1 f2),e1,p1))]
    | _ -> raise Not_implemented
  let hook_mul c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)]
        when e1 = e2 && p1 = p2 -> [round_to_range(Float ((Gmp.FR.mul_prec p1 Gmp.GMP_RNDN f1 f2),e1,p1))]
    | _ -> raise Not_implemented
  let hook_div c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)]
        when e1 = e2 && p1 = p2 -> [round_to_range(Float ((Gmp.FR.div_prec p1 Gmp.GMP_RNDN f1 f2),e1,p1))]
    | _ -> raise Not_implemented
  let hook_pow c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)]
        when e1 = e2 && p1 = p2 -> [round_to_range(Float ((Gmp.FR.pow_prec p1 Gmp.GMP_RNDN f1 f2),e1,p1))]
    | _ -> raise Not_implemented
  let hook_eq c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)] -> [Bool (Gmp.FR.equal f1 f2)]
    | _ -> raise Not_implemented
  let hook_lt c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)] -> [Bool (Gmp.FR.less f1 f2)]
    | _ -> raise Not_implemented
  let hook_le c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)] -> [Bool (Gmp.FR.lessequal f1 f2)]
    | _ -> raise Not_implemented
  let hook_gt c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)] -> [Bool (Gmp.FR.greater f1 f2)]
    | _ -> raise Not_implemented
  let hook_ge c lbl sort config ff = match c with
      [Float (f1,e1,p1)], [Float (f2,e2,p2)] -> [Bool (Gmp.FR.greaterequal f1 f2)]
    | _ -> raise Not_implemented
  let hook_precision c lbl sort config ff = match c with
      [Float (_,_,p)] -> [Int (Z.of_int p)]
    | _ -> raise Not_implemented
  let hook_exponentBits c lbl sort config ff = match c with
      [Float (_,e,_)] -> [Int (Z.of_int e)]
    | _ -> raise Not_implemented
  let hook_float2int c lbl sort config ff = match c with
      [Float (f,_,_)] -> [Int (to_zarith (Gmp.FR.to_z_f f))]
    | _ -> raise Not_implemented
  let hook_int2float c lbl sort config ff = match c with
      [Int i], [Int prec], [Int exp] ->
        [round_to_range(Float ((Gmp.FR.from_z_prec (Z.to_int prec) Gmp.GMP_RNDN (from_zarith i)),(Z.to_int exp),(Z.to_int prec)))]
    | _ -> raise Not_implemented
  let hook_min c lbl sort config ff = raise Not_implemented
  let hook_max c lbl sort config ff = raise Not_implemented
  let hook_rem c lbl sort config ff = raise Not_implemented
  let hook_root c lbl sort config ff = match c with
    | [Float (f,e,p)], [Int i] when Z.to_int i = 2 -> 
        [round_to_range(Float ((Gmp.FR.sqrt_prec p Gmp.GMP_RNDN f),e,p))]
    | _ -> raise Not_implemented
  let hook_sign c lbl sort config ff = match c with
      [Float (f,e,p)] -> (match deconstruct_float f e p with (s,_,_) -> [Bool s])
    | _ -> raise Not_implemented
  let hook_significand c lbl sort config ff = match c with
      [Float (f,e,p)] -> (match deconstruct_float f e p with (_, _, Some s) -> [Int s]
        | _ -> raise Not_implemented)
    | _ -> raise Not_implemented
  let hook_atan2 c lbl sort config ff = raise Not_implemented
  let hook_exponent c lbl sort config ff = match c with
      [Float (f,e,p)] -> (match deconstruct_float f e p with (_, exp, _) -> [Int (Z.of_int exp)])
    | _ -> raise Not_implemented
end

