open Poly_type

module type Type = Type

(** Exception raised when trying to divide a polynomial by a non-constant value *)
exception Div_by_non_constant

module Make (Vec: Vector.Type with module M = Rtree and module V = Var.Positive) = struct
    module Vec = Vec
    module Coeff = Vec.Coeff
	module V = Vec.V

	module MonomialBasis =
		struct
		(* monomial_basis represents a MONIC monomial (i.e. leading coeff = 1) *)
		type t = V.t list

		let to_string_param : t -> string -> string
			= fun vlist v->
			let rec(to_string_rec : V.t list -> V.t -> int -> string)
				= fun vlist prevar power ->
					match vlist with
					| [] -> let str = V.to_string' v prevar in
						if power = 1
						then str
						else String.concat "" [str ; "^" ; string_of_int power]
					| var :: tail ->
					if V.equal var prevar
					then to_string_rec tail prevar (power+1)
					else let str = V.to_string' v prevar in
						if power = 1
						then String.concat "" [str ; to_string_rec tail var 1]
						else String.concat "" [str ; "^" ; string_of_int power ; to_string_rec tail var 1]
			in
			if List.length vlist = 0
			then ""
			else to_string_rec (List.tl vlist) (List.nth vlist 0) 1

		let to_string : t -> string
			= fun vlist ->
			to_string_param vlist "x"

		let rec compare : t -> t -> int
			= fun m1 m2 ->
			match m1, m2 with
			| [], [] -> 0
			| [], _ :: _ -> -1
 		 	| _ :: _, [] -> 1
 		 	| x :: m1', x' :: m2' ->
 		   	let i = V.cmp x x' in
 		    	if i = 0
		     	then compare m1' m2'
		     	else i

		let equal : t -> t -> bool
			= fun m1 m2 ->
			compare m1 m2 = 0

		let rename : t -> V.t -> V.t -> t
			= fun m v v' ->
			List.map (fun var -> if V.equal var v then v' else var) m

		let eval : t -> (V.t -> Vec.Coeff.t) -> Vec.Coeff.t
			= fun m e ->
			List.fold_left
			(fun c v -> Vec.Coeff.mul c (e v))
			Vec.Coeff.u m

		let isLinear : t -> bool
		  = fun m -> List.length m <= 1

		let is_nonnegative : t -> bool
			= fun m ->
			match m with
			| [] -> true
			| [v] -> V.cmp v V.u >= 0
			| _ -> List.for_all (fun v -> V.cmp v V.u >= 0) m

		let mk : V.t list -> t
			= fun l ->
			if is_nonnegative l then List.fast_sort V.cmp l
			else Pervasives.invalid_arg ("SxPoly.Poly.Monomial.mk : invalid variable list " ^ (Misc.list_to_string V.to_string l ";"))

		let data : t -> V.t list
			= fun m -> m

		let null : t = []

		let change_variable : (t -> t option) -> t -> t
			= fun ch m ->
			match ch m with
			| Some m' -> m'
			| None -> m

        let partial_derivative : V.t -> t -> t
            = fun var m ->
            let rec partial_derivative_rec : t -> t -> t
                = fun acc -> function
                | [] -> []
                | v :: m' when V.equal v var -> acc @ m'
                | v :: m' when V.cmp v var > 0 -> []
                | v :: m' -> partial_derivative_rec (acc @ [v]) m'
            in
            partial_derivative_rec [] m

	end

	module Monomial =
		struct

		type t = MonomialBasis.t * Vec.Coeff.t

		let to_string : t -> string
			= fun m -> let (vlist, c) = m in
			match vlist with
			| [] -> Vec.Coeff.to_string c
			| _ -> if Vec.Coeff.equal c (Vec.Coeff.of_int 1)
				then MonomialBasis.to_string vlist
				else if Vec.Coeff.lt c (Vec.Coeff.of_int 0)
					then String.concat "" ["(";Vec.Coeff.to_string c;")*";MonomialBasis.to_string vlist]
					else String.concat "" [Vec.Coeff.to_string c ; "*" ; MonomialBasis.to_string vlist]

		let compare : t -> t -> int
			= fun (m1,_) (m2,_) ->
			MonomialBasis.compare m1 m2

		let equal : t -> t -> bool
			= fun (m1,c1) (m2,c2) ->
			MonomialBasis.compare m1 m2 = 0 && Vec.Coeff.equal c1 c2

		let canonO : t -> t option
			= fun (m, a) ->
  			if not (Vec.Coeff.well_formed_nonnull a)
  			then None
 			else Some (MonomialBasis.mk m, a)

		let canon : t -> t
		  = fun m ->
		  match canonO m with
		  | Some m' -> m'
		  | None -> Pervasives.invalid_arg ("SxPoly.SxPoly.Monomial.canon : " ^ (to_string m))

		let mk : MonomialBasis.t -> Vec.Coeff.t -> t
	  		= fun m a -> canon (m, a)

		let mk2 : V.t list -> Vec.Coeff.t -> t
	  		= fun m a -> canon (MonomialBasis.mk m, a)

	  	let mk3 : (V.t * int) list * Vec.Coeff.t -> t
			= fun (l,c) ->
			let l' = List.fold_left
				(fun res (v,i) ->
					if i > 0
					then (List.map (fun _ -> v) (Misc.range 0 i)) :: res
					else res)
				[] l
				|> List.concat
			in
			mk2 l' c

		let data : t -> MonomialBasis.t * Vec.Coeff.t
			= fun (m,c) -> (m,c)

		let mul : t -> t -> t
    		= fun (m1,c1) (m2,c2) ->
    		if Vec.Coeff.equal (Vec.Coeff.mul c1 c2) Vec.Coeff.z
    		then ([],Vec.Coeff.z)
    		else
    		let new_m = match (m1,m2) with
    		| ([],_) -> m2
    		| (_,[]) -> m1
    		| _ -> m1 @ m2
    		in (List.sort V.cmp new_m, Vec.Coeff.mul c1 c2)

		let isConstant : t -> bool
		  = fun (m,_) -> MonomialBasis.compare m MonomialBasis.null = 0

		let isLinear : t -> bool
		  = fun (m,_) -> List.length m = 1

		let eval : t -> (V.t -> Vec.Coeff.t) -> Vec.Coeff.t
			= fun (m,c) e ->
			if MonomialBasis.compare m [] = 0
			then c
			else Vec.Coeff.mul (MonomialBasis.eval m e) c

		let eval_partial : t -> (V.t -> Vec.Coeff.t option) -> t
			= fun (m,c) e ->
			List.fold_left
				(fun (m',c') v -> match (e v) with
					| Some c2 -> mul (m',c') (MonomialBasis.null, c2)
					| None -> mul (m',c') ([v], Vec.Coeff.u))
				([], c) m

		let change_variable : (MonomialBasis.t -> MonomialBasis.t option) -> t -> t
			= fun ch (m,c) ->
			(MonomialBasis.change_variable ch m, c)

        let partial_derivative : V.t -> t -> t
            = fun var (m,c) ->
            if List.exists (fun v -> V.equal var v) (MonomialBasis.data m)
            then (MonomialBasis.partial_derivative var m, c)
            else (MonomialBasis.null,Vec.Coeff.z)
	end

	type t = Monomial.t list

	let compare : t -> t -> int
		= fun p1 p2 ->
			match (p1,p2) with
			| ([],[]) -> 0
			| (_,[]) -> 1
			| ([],_) -> -1
			| (m1::tl1, m2::tl2) -> let x = Monomial.compare m1 m2 in
			match x with
				| 0 -> compare tl1 tl2
				| _ -> x

	let to_string : t -> string
	  = fun p ->
	  List.map Monomial.to_string p
	  |> String.concat " + "
	  |> fun s -> if String.length s = 0 then "0" else s

	let canon : t -> t
  		= let rec (collapseDups : t -> t)
      		= function
      			| [] | _ :: [] as p -> p
      			| m :: (m' :: p' as p) ->
	 			if Monomial.compare m m' = 0
	 			then collapseDups ((Pervasives.fst m, Vec.Coeff.add (Pervasives.snd m) (Pervasives.snd m')) :: p')
	 			else m :: collapseDups p
    		in
    		let fixConstant
     		 = fun p ->
      			let (cst, m) = List.partition (fun (m, _) -> MonomialBasis.compare m MonomialBasis.null = 0) p in
     	 			([], List.fold_left (fun n (_, a) -> Vec.Coeff.add n a) Vec.Coeff.z cst) :: m
    		in
    		fun p ->
    		fixConstant p
    		|> List.filter (fun (_, a) -> Vec.Coeff.well_formed_nonnull a)
    		|> List.map Monomial.canonO
    		|> List.map
				(function Some m -> m
				| None ->
					to_string p
					|> Printf.sprintf "SxPoly.canon: Monomial.canon on %s"
					|> Pervasives.failwith)
    		|> List.sort Monomial.compare
    		|> collapseDups
    		|> List.filter (fun (_, a) ->
				if Vec.Coeff.equal a Vec.Coeff.z
				then false
				else if Vec.Coeff.well_formed_nonnull a
					then true
					else
						to_string p
						|> Printf.sprintf "SxPoly.canon: Vec.Coeff.well_formed_nonnull on %s"
						|> Pervasives.failwith)
			|> function _ :: _ as p' -> p' | [] -> [[], Vec.Coeff.z]
	(*
	let mk : t -> Vec.Coeff.t -> t
  		= fun p cst -> ([V.u], cst) :: p |> canon
	*)

	let mk : Monomial.t list -> t
		= fun l -> canon l

	let mk2 : (V.t list * Vec.Coeff.t) list -> t
		= fun l -> canon l

	let mk_cste : t -> Vec.Coeff.t -> t
		= fun p cst -> (MonomialBasis.null, cst) :: p |> canon

	let mk2_cste : (V.t list * Vec.Coeff.t) list -> Vec.Coeff.t -> t
		= fun l cst -> (MonomialBasis.null, cst) :: l |> canon

	let mk3 : ((V.t * int) list * Vec.Coeff.t) list -> t
		= fun l ->
		List.filter (fun (_,coeff) -> not (Vec.Coeff.equal coeff Vec.Coeff.z)) l
		|> List.map Monomial.mk3
		|> mk

	let fromVar : V.t -> t
		= fun v ->
		mk2 [([v],Vec.Coeff.u)]

	let data : t -> Monomial.t list
		= fun p -> p

	let data2 : t -> (V.t list * Vec.Coeff.t) list
		= fun p -> p

	let cste : Vec.Coeff.t -> t
		= fun i ->
		[(MonomialBasis.null,i)] |> canon

	let z : t
		= cste Vec.Coeff.z

	let u : t
		= cste Vec.Coeff.u

	let negU : t
        = cste Vec.Coeff.negU

	let is_constant : t -> bool
		= fun p ->
		match p with
		| [] -> true
		| [(m,_)] -> MonomialBasis.compare m MonomialBasis.null = 0
		| (_,_) :: _ -> false

	let isZ : t -> bool
		= fun p ->
		if p = [] then true (* nécessaire? *)
		else if List.length p = 1
			then let (mono,coeff) = List.hd p in
				MonomialBasis.compare mono MonomialBasis.null = 0 && Vec.Coeff.equal coeff Vec.Coeff.z
			else false

	(* [is_affine] assumes that [p] is in canonical form. *)
	let is_affine : t -> bool
	  = fun p -> List.for_all (fun m -> Monomial.isConstant m || Monomial.isLinear m) p

	let change_variable : (MonomialBasis.t -> MonomialBasis.t option) -> t -> t
		= fun ch l ->
		List.map (Monomial.change_variable ch) l
		|> canon

	let  add : t -> t -> t
		= let rec add_rec : t -> t -> t
			= fun p1 p2 ->
			match (p1,p2) with
			| ([],poly2) -> poly2
			| (poly1,[]) -> poly1
			| ((m1,c1) :: tail1, (m2,c2) :: tail2) -> let comp = MonomialBasis.compare m1 m2 in
			if comp = 0
				then if Vec.Coeff.equal (Vec.Coeff.add c1 c2) Vec.Coeff.z
					then add_rec tail1 tail2
					else (m1,Vec.Coeff.add c1 c2)::(add_rec tail1 tail2)
				else if comp < 0 (*m1 < m2*)
					then (m1,c1)::(add_rec tail1 ((m2,c2)::tail2))
					else (m2,c2)::(add_rec ((m1,c1)::tail1) tail2)
		in fun p1 p2 ->
		add_rec p1 p2 |> canon

	let mul : t -> t -> t
		= let rec mul_rec : t -> t -> t
			= fun p1 p2 ->
			match (p1,p2) with
			| ([],_) -> []
			| (m::tail1,p2) -> List.fold_left
				add (mul_rec tail1 p2) (List.map (fun m2 -> [Monomial.mul m m2]) p2)
		in fun p1 p2 ->
		mul_rec p1 p2 |> canon

	(* XXX: naïve implem*)
	let mulc : t -> Vec.Coeff.t -> t
		= fun p c ->
		mul p (cste c)

    let div : t -> t -> t
        = fun p1 p2 ->
        if is_constant p2
        then
            let (_,c) = List.hd (data2 p2) in
            mulc p1 (Vec.Coeff.div Vec.Coeff.u c)
        else
            Pervasives.raise Div_by_non_constant

	let neg : t -> t
		= fun p ->
		mulc p Vec.Coeff.negU

	(* XXX: naïve implem *)
	let sub : t -> t -> t
		= fun p1 p2 ->
		add p1 (mul negU p2)

	let sub_monomial : t -> MonomialBasis.t -> t
		= fun p m ->
		Misc.pop
			(fun (m1,_) (m2,_) -> MonomialBasis.compare m1 m2 = 0)
			p (m,Vec.Coeff.z)

	let sum : t list -> t
		= fun l ->
		List.fold_left (fun r p -> add r p) z l

	let prod : t list -> t
		= fun l ->
		List.fold_left (fun r p -> mul r p) u l

	let pow : t -> int -> t
		= fun p i ->
		List.map (fun _ -> p) (Misc.range 0 i) |> prod

	let rec equal : t -> t -> bool
		= fun p1 p2 ->
		match (p1,p2) with
		| ([],[]) -> true
		| (_,[]) | ([],_) -> false
		| (m1::tail1 , m2::tail2) -> Monomial.equal m1 m2 && equal tail1 tail2

	let rename : t -> V.t -> V.t -> t
		= fun p v v'->
		List.map (fun (m,c) -> (MonomialBasis.rename m v v',c)) p
		|> canon

	let rec monomial_coefficient : t -> MonomialBasis.t -> Vec.Coeff.t
		= fun p m ->
		match (p,m) with
		| ([],_) -> Vec.Coeff.z
		| ((m1,c)::tail, m2) -> if MonomialBasis.compare m1 m2 = 0
			then c
			else if MonomialBasis.compare m1 m2 < 0
				then monomial_coefficient tail m
				else Vec.Coeff.z

	let monomial_coefficient_poly : t -> MonomialBasis.t -> t
		= let rec sub_monomial : MonomialBasis.t -> MonomialBasis.t -> (MonomialBasis.t * bool)
			= fun m1 m2 ->
			match (m1,m2) with
			| (_,[]) -> (m1,true)
			| ([],_) -> ([],false)
			| (v1::tail1,v2::tail2) -> if V.cmp v1 v2 = 0
				then sub_monomial tail1 tail2
				else let (l,b) = sub_monomial tail1 m2 in (v1::l,b)
		in
		let rec monomial_coefficient_poly_rec : t -> MonomialBasis.t -> t
			= fun p m ->
			match (p,m) with
			| ([],_) -> []
			| ((m1,c)::tail, m2) -> if List.length m1 >= List.length m2 && MonomialBasis.compare (Misc.sublist m1 0 (List.length m2)) m2 > 0 (* m1 > m2 *)
				then []
				else let (l,b) = sub_monomial m1 m in if b
					then add [(l,c)] (monomial_coefficient_poly_rec tail m2)
					else monomial_coefficient_poly_rec tail m2
		in fun p m ->
		monomial_coefficient_poly_rec p m |> canon

	let get_constant : t -> Vec.Coeff.t
		= fun p ->
		monomial_coefficient p MonomialBasis.null

	let rec get_affine_part : t -> V.t list -> t
		= fun p variables ->
		let res = match p with
			| [] -> []
			| (vlist,coeff) :: tail -> let q = get_affine_part tail variables in
				let vlist2 = List.filter (fun x -> List.mem x variables) vlist in
					if List.length vlist2 <= 1
						then add [(vlist,coeff)] q
						else q
		in canon res

	let get_vars : t -> V.t list
		= fun p ->
		List.map (fun (m,_) -> Misc.rem_dupl V.equal m) p
		|> List.concat
		|> Misc.rem_dupl V.equal

	let horizon : t list -> V.t
		= fun l ->
		List.map get_vars l
		|> List.concat
		|> Misc.rem_dupl V.equal
		|> V.Set.of_list
		|> V.horizon

	let eval : t -> (V.t -> Vec.Coeff.t) -> Vec.Coeff.t
			= fun p e ->
			List.fold_left
			(fun c m -> Vec.Coeff.add c (Monomial.eval m e))
			Vec.Coeff.z p

	let eval_partial : t -> (V.t -> Vec.Coeff.t option) -> t
			= fun p e ->
			List.fold_left
			(fun p m -> add p [(Monomial.eval_partial m e)])
			[] p

    let partial_derivative : V.t -> t -> t
        = fun var p ->
        List.fold_left
            (fun acc m ->
                let (m,c) = Monomial.partial_derivative var m in
                if Vec.Coeff.isZ c
                then acc
                else (m,c) :: acc)
            z p
        |> canon

    let gradient : t -> t Vec.M.t
        = fun p ->
        List.fold_left
            (fun tree var ->
                Vec.M.set z tree var (partial_derivative var p))
            Vec.M.empty
            (get_vars p)

	let toCstr : t -> (Vec.t * Vec.Coeff.t)
		= fun p ->
		if is_affine p
		then
			let vec = (List.fold_left
				(fun l (m,c) ->
					if MonomialBasis.compare m MonomialBasis.null <> 0
					then (c, List.nth (MonomialBasis.data m) 0) :: l
					else l)
				[] (List.map Monomial.data (data p)))
				|> Vec.mk
			and cste = get_constant p
			in
			(vec,cste)
		else Pervasives.invalid_arg "handelman.polyToCstr: not affine polynomial"

	let ofCstr : Vec.t -> Vec.Coeff.t -> t
		= fun vec cste ->
		let l = vec
		|> Vec.toList
			|> List.map (fun (x,n) -> Monomial.mk2 [x] n)
			|> mk
		in
		mk_cste l cste

	let of_string : string -> t
   	= fun s ->
    	PolyParser.one_prefixed_poly PolyLexer.token2 (Lexing.from_string s)
    	|> List.map (fun (vl,q) -> (List.map V.fromPos vl, Vec.Coeff.ofQ q))
    	|> canon

	module Invariant
 		= struct
  	(** This module contains an executable specification of what it means to be
	a well-formed polynomial. *)

  		let rec helper_sorted : ('a -> 'a -> bool) -> 'a list -> bool
	    = fun f ->
    	function
   		| [] | _ :: [] -> true
   		| x :: ((x' :: _) as l') -> f x x' && helper_sorted f l'

  		module Monom
    	= struct

    		let check_sorted : Monomial.t -> bool
      		= fun (l, _) -> helper_sorted (fun x x' -> V.cmp x x' <= 0) l

    		let check : Monomial.t -> bool
      		= fun (vlist,c) -> Vec.Coeff.well_formed_nonnull c && check_sorted (vlist,c)
  		end

  		(* strict negativity enforces no duplicates *)
		let check_sorted : t -> bool
    	= helper_sorted (fun m m' -> Monomial.compare m m' < 0)

  		let check : t -> bool
    		= fun p ->
    		match p with
    		| [] -> false
    		| [[], a] when Vec.Coeff.equal a Vec.Coeff.z -> true
    		| _ -> List.for_all Monom.check p && check_sorted p

  		let checkOrFail : t -> unit
    		= fun p ->
    		if not (check p)
    		then p
	 		|> to_string
	 		|> Printf.sprintf "SxPoly.Invariant.checkOrFail: %s"
	 		|> Pervasives.failwith
	end
end
