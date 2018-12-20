open Poly_type

module type Type = Type

(** Exception raised when trying to divide a polynomial by a non-constant value *)
exception Div_by_non_constant

module Make (Vec: Vector.Type with module M = Rtree and module V = Var.Positive) = struct
	module Vec = Vec
	module Coeff = Vec.Coeff
	module V = Vec.V

	type exp = int (* >= 0*)

	module MonomialBasis = struct

		type t = (V.t * exp) list

        let null : t = []

        let is_null : t -> bool
            = fun m ->
            m = []

		let to_string_param : t -> string -> string
			= fun m s ->
			String.concat ""
				(List.map
					(fun (v,e) ->
					match e with
					| 0 | 1 -> V.to_string' s v
					| _ -> Printf.sprintf "%s^%i" (V.to_string' s v) e)
					m)

		let to_string : t -> string
			= fun m ->
			to_string_param m "x"

		let rec compare : t -> t -> int
			= fun m1 m2 ->
			match m1, m2 with
			| [], [] -> 0
			| [], _ :: _ -> -1
 		 	| _ :: _, [] -> 1
 		 	| (x1,e1) :: m1', (x2,e2) :: m2' ->
     		   	let i = V.cmp x1 x2 in
     		    	if i = 0
     		    	then
     		    		let j = Pervasives.compare e1 e2 in
     		    		if j = 0
    		     		then compare m1' m2'
    		     		else j
    		     	else i

		let equal : t -> t -> bool
			= fun m1 m2 ->
			compare m1 m2 = 0

		let rename : t -> V.t -> V.t -> t
			= fun m v v' ->
			List.map (fun (var,e) ->
                if V.equal var v
                then (v',e)
                else (var,e)
            ) m

		let eval : t -> (V.t -> Coeff.t) -> Coeff.t
			= fun m f_eval ->
			List.fold_left (fun c (v,e) ->
                Coeff.mul c (Coeff.pow (f_eval v) e)
            ) Coeff.u m

        let isLinear : t -> bool
            = fun m ->
            List.length m = 0
            || (List.length m = 1 && Pervasives.snd (List.hd m) <= 1)

		let well_formed : t -> bool
			= fun m ->
			List.for_all (fun (v,e) ->
                V.cmp v V.u >= 0 && e >= 0
            ) m

		let mk : (V.t * exp) list -> t
			= fun l ->
			if well_formed l
            then List.fast_sort (fun (v1,_) (v2,_) -> V.cmp v1 v2) l
			else Pervasives.invalid_arg ("SxPoly.Poly.MonomialBasis.mk")

		let mk_list : V.t list -> t
			= fun l ->
			List.fast_sort V.cmp l
			|> List.fold_left
				(fun res v ->
					let (v',e') = List.hd res in
					if V.equal v v'
					then (v',e'+1) :: List.tl res
					else (v,1)::res)
				[]
			|> List.rev
			|> fun l -> if well_formed l
				then l
				else Pervasives.invalid_arg ("SxPoly.Poly.MonomialBasis.mk_list")

		let data : t -> (V.t * exp) list
			= fun m -> m

		let data_list : t -> V.t list
			= fun m ->
			List.fold_left
				(fun res (v,e) ->
					res
					@
					List.map
						(fun _ -> v)
						(Misc.range 0 e))
				[] m

        let change_variable : (t -> t option) -> t -> t
			= fun ch m ->
			match ch m with
			| Some m' -> m'
			| None -> m

        let partial_derivative : V.t -> t -> t
            = fun var m ->
            (* Fold right to maintain order *)
            List.fold_right (fun (v,e) acc ->
                if V.equal v var
                then if e > 1
                    then (v,e-1) :: acc
                    else acc
                else (v,e) :: acc
            ) m []
	end

	module Monomial = struct

		type t = (MonomialBasis.t * Coeff.t)

        let null : t = (MonomialBasis.null, Coeff.z)

        let is_null : t -> bool
            = fun (m,c) ->
            MonomialBasis.is_null m
            && Coeff.isZ c

		let to_string : t -> string
			= fun m -> let (vlist, c) = m in
			match vlist with
			| [] -> Coeff.to_string c
			| _ -> if Coeff.equal c (Coeff.of_int 1)
				then MonomialBasis.to_string vlist
				else if Coeff.lt c (Coeff.of_int 0)
					then String.concat "" ["(";Coeff.to_string c;")*";MonomialBasis.to_string vlist]
					else String.concat "" [Coeff.to_string c ; "*" ; MonomialBasis.to_string vlist]

		let compare : t -> t -> int
			= fun (m1,_) (m2,_) ->
			MonomialBasis.compare m1 m2

		let equal : t -> t -> bool
			= fun (m1,c1) (m2,c2) ->
			MonomialBasis.compare m1 m2 = 0 && Coeff.equal c1 c2

		let canonO : t -> t option
			= fun (m, a) ->
  			if not (Coeff.well_formed_nonnull a)
  			then None
 			else Some (MonomialBasis.mk m, a)

		let canon : t -> t
		  = fun m ->
		  match canonO m with
		  | Some m' -> m'
		  | None -> Pervasives.invalid_arg ("SxPoly.SxPoly.Monomial.canon : " ^ (to_string m))

		let mk : MonomialBasis.t -> Coeff.t -> t
	  		= fun m a -> canon (m, a)

		let mk2 : (V.t * exp) list -> Coeff.t -> t
	  		= fun m a -> canon (MonomialBasis.mk m, a)

	  	let mk_list : V.t list -> Coeff.t -> t
	  		= fun m a -> canon (MonomialBasis.mk_list m, a)

		let data : t -> MonomialBasis.t * Coeff.t
			= fun (m,c) -> (m,c)

		let data_list : t -> V.t list * Coeff.t
			= fun (m,c) ->
			(MonomialBasis.data_list m, c)

        let mul : t -> t -> t
            = let rec mul_list l1 l2 =
            match l1,l2 with
            | [],[] -> []
            | [],x | x,[] -> x
            | ((v1,e1) as m1)::t1, ((v2,e2) as m2)::t2 ->
            (* we keep the variables in a sorted order *)
            let c = V.cmp v1 v2 in
            if c = 0
            then (v1,(e1 + e2))::(mul_list t1 t2)
            else if c < 0
                then m1::(mul_list t1 l2)
                else m2::(mul_list l1 t2)
        in
        fun (m1, c1) (m2, c2) ->
        let coeff = Coeff.mul c1 c2 in
        if Coeff.isZ coeff
        then null
        else (mul_list m1 m2), coeff

		let isConstant : t -> bool
            = fun (m,_) ->
            MonomialBasis.is_null m

		let isLinear : t -> bool
            = fun (m,c) ->
            MonomialBasis.isLinear m

		let eval : t -> (V.t -> Coeff.t) -> Coeff.t
			= fun (m,c) e ->
			if isConstant (m,c)
			then c
			else Coeff.mul (MonomialBasis.eval m e) c

		let eval_partial : t -> (V.t -> Coeff.t option) -> t
			= fun (m,c) f_eval ->
			List.fold_left (fun (m',c') (v,e) ->
                match (f_eval v) with
				| Some c2 -> mul (m',c') (MonomialBasis.null, c2)
				| None -> mul (m',c') ([v,e], Coeff.u)
			) ([], c) m

	end

	type t = Monomial.t list

	let (compare : t -> t -> int)
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
	 			then collapseDups ((Pervasives.fst m, Coeff.add (Pervasives.snd m) (Pervasives.snd m')) :: p')
	 			else m :: collapseDups p
    		in
    		let fixConstant
     		 = fun p ->
      			let (cst, m) = List.partition (fun (m, _) -> MonomialBasis.compare m MonomialBasis.null = 0) p in
     	 			([], List.fold_left (fun n (_, a) -> Coeff.add n a) Coeff.z cst) :: m
    		in
    		fun p ->
    		fixConstant p
    		|> List.filter (fun (_, a) -> Coeff.well_formed_nonnull a)
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
				if Coeff.equal a Coeff.z
				then false
				else if Coeff.well_formed_nonnull a
					then true
					else
						to_string p
						|> Printf.sprintf "SxPoly.canon: Coeff.well_formed_nonnull on %s"
						|> Pervasives.failwith)
			|> function _ :: _ as p' -> p' | [] -> [[], Coeff.z]


	let mk : Monomial.t list -> t
		= fun l -> canon l

	let mk2 : ((V.t * exp) list * Coeff.t) list -> t
		= fun l -> canon l

	let mk_list : (V.t list * Coeff.t) list -> t
		= fun l ->
		List.map
			(fun (vars,c) -> Monomial.mk_list vars c)
			l
		|> canon

	let mk_cste : t -> Coeff.t -> t
		= fun p cst -> (MonomialBasis.null, cst) :: p |> canon

	let mk2_cste : ((V.t * exp) list * Coeff.t) list -> Coeff.t -> t
		= fun l cst -> (MonomialBasis.null, cst) :: l |> canon

	let mk2_cste_list : (V.t list * Coeff.t) list -> Coeff.t -> t
		= fun l cst ->
		(MonomialBasis.null, cst)
		::
		List.map
			(fun (vars,c) -> Monomial.mk_list vars c)
			l
		|> canon

	let data : t -> Monomial.t list
		= fun p -> p

	let data2 : t -> ((V.t * exp) list * Coeff.t) list
		= fun p -> p

	let data_list : t -> (V.t list * Coeff.t) list
		= fun p ->
		List.map Monomial.data_list p

	let (cste : Coeff.t -> t)
		= fun i ->
		[(MonomialBasis.null,i)] |> canon

	let (z : t)
		= cste Coeff.z

	let (u : t)
		= cste Coeff.u

	let (negU : t) = cste Coeff.negU

	let rec(is_constant : t -> bool)
		= fun p ->
		match p with
		| [] -> true
		| [(m,coeff)] -> MonomialBasis.compare m MonomialBasis.null = 0
		| (m,coeff) :: tail -> false

	let rec(isZ : t -> bool)
		= fun p ->
		if p = [] then true (* nécessaire? *)
		else if List.length p = 1
			then let (mono,coeff) = List.hd p in
				MonomialBasis.compare mono MonomialBasis.null = 0 && Coeff.equal coeff Coeff.z
			else false

	(* [is_affine] assumes that [p] is in canonical form. *)
	let is_affine : t -> bool
	  = fun p -> List.for_all (fun m -> Monomial.isConstant m || Monomial.isLinear m) p

	let rec(add : t -> t -> t)
		= let rec(add_rec : t -> t -> t)
			= fun p1 p2 ->
			match (p1,p2) with
			| ([],poly2) -> poly2
			| (poly1,[]) -> poly1
			| ((m1,c1) :: tail1, (m2,c2) :: tail2) ->
				let comp = MonomialBasis.compare m1 m2 in
				if comp = 0
				then if Coeff.equal (Coeff.add c1 c2) Coeff.z
					then add_rec tail1 tail2
					else (m1,Coeff.add c1 c2)::(add_rec tail1 tail2)
				else if comp < 0 (*m1 < m2*)
					then (m1,c1)::(add_rec tail1 ((m2,c2)::tail2))
					else (m2,c2)::(add_rec ((m1,c1)::tail1) tail2)
		in fun p1 p2 ->
		add_rec p1 p2 |> canon

	let rec(mul : t -> t -> t)
		= let rec(mul_rec : t -> t -> t)
			= fun p1 p2 ->
			match (p1,p2) with
			| ([],_) -> []
			| (m::tail1,p2) -> List.fold_left
				add (mul_rec tail1 p2) (List.map (fun m2 -> [Monomial.mul m m2]) p2)
		in fun p1 p2 ->
		mul_rec p1 p2 |> canon

	(* XXX: naïve implem*)
	let (mulc : t -> Coeff.t -> t)
		= fun p c ->
		mul p (cste c)

	let (neg : t -> t)
		= fun p ->
		mulc p Coeff.negU

	(* XXX: naïve implem *)
	let (sub : t -> t -> t)
		= fun p1 p2 ->
		add p1 (mul negU p2)

	let (sum : t list -> t)
		= fun l ->
		List.fold_left (fun r p -> add r p) z l

	let (prod : t list -> t)
		= fun l ->
		List.fold_left (fun r p -> mul r p) u l

	let (pow : t -> int -> t)
		= fun p i ->
		List.map (fun _ -> p) (Misc.range 0 i) |> prod

	let (equal : t -> t -> bool)
		= fun p1 p2 ->
		List.length p1 <> List.length p2
		&&
		List.for_all2 Monomial.equal p1 p2

	let (rename : t -> V.t -> V.t -> t)
		= fun p v v'->
		List.map (fun (m,c) -> (MonomialBasis.rename m v v',c)) p
		|> canon

	let rec(monomial_coefficient : t -> MonomialBasis.t -> Coeff.t)
		= fun p m ->
		match (p,m) with
		| ([],_) -> Coeff.z
		| ((m1,c)::tail, m2) -> if MonomialBasis.compare m1 m2 = 0
			then c
			else if MonomialBasis.compare m1 m2 < 0
				then monomial_coefficient tail m
				else Coeff.z
(*
	let rec(sub_monomial : MonomialBasis.t -> MonomialBasis.t -> (MonomialBasis.t * bool))
	= fun m1 m2 ->
	match (m1,m2) with
	| (_,[]) -> (m1,true)
	| ([],_) -> ([],false)
	| (v1::tail1,v2::tail2) -> if V.cmp v1 v2 = 0
		then sub_monomial tail1 tail2
		else let (l,b) = sub_monomial tail1 m2 in (v1::l,b)

	let (monomial_coefficient_poly : t -> MonomialBasis.t -> t)
		= let rec(monomial_coefficient_poly_rec : t -> MonomialBasis.t -> t)
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

	let (get_constant : t -> Coeff.t)
		= fun p ->
		monomial_coefficient p MonomialBasis.null

	let rec(get_affine_part : t -> V.t list -> t)
		= fun p variables ->
		let res = match p with
			| [] -> []
			| (vlist,coeff) :: tail -> let q = get_affine_part tail variables in
				let vlist2 = List.filter (fun x -> List.mem x variables) vlist in
					if List.length vlist2 <= 1
						then add [(vlist,coeff)] q
						else q
		in canon res

	let (get_vars : t -> V.t list)
		= fun p ->
		List.map (fun (m,c) -> Misc.rem_dupl V.equal m) p
		|> List.concat
		|> Misc.rem_dupl V.equal

	let (eval : t -> (V.t -> Coeff.t) -> Coeff.t)
			= fun p e ->
			List.fold_left
			(fun c m -> Coeff.add c (Monomial.eval m e))
			Coeff.z p

	let (eval_partial : t -> (V.t -> Coeff.t option) -> t)
			= fun p e ->
			List.fold_left
			(fun p m -> add p [(Monomial.eval_partial m e)])
			[] p

	let toCstr : t -> (Vec.t * Coeff.t)
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

	let ofCstr : Vec.t -> Coeff.t -> t
		= fun vec cste ->
		let l = vec
		|> Vec.toList
			|> List.map (fun (x,n) -> Monomial.mk2 [x] n)
			|> mk
		in
		mk_cste l cste
    *)

	let of_string : string -> t
   	    = fun s ->
    	PolyParser.one_prefixed_poly PolyLexer.token2 (Lexing.from_string s)
    	|> List.map (fun (vl,q) -> (List.map V.fromPos vl, Vec.Coeff.ofQ q))
        |> mk_list

	module Invariant = struct

  		let rec helper_sorted : ('a -> 'a -> bool) -> 'a list -> bool
	       = fun f ->
        	function
       		| [] | _ :: [] -> true
       		| x1 :: ((x2 :: _) as l') -> f x1 x2 && helper_sorted f l'

  		module Monom = struct

    		let check_sorted : Monomial.t -> bool
      		    = fun (l, _) ->
                helper_sorted (fun (x,_) (x',_) -> V.cmp x x' <= 0) l

    		let check : Monomial.t -> bool
      		    = fun (vlist,c) ->
                Coeff.well_formed_nonnull c && check_sorted (vlist,c)
  		end

  		(* strict negativity enforces no duplicates *)
		let check_sorted : t -> bool
    	   = helper_sorted (fun m m' -> Monomial.compare m m' < 0)

  		let check : t -> bool
    		= fun p ->
    		match p with
    		| [] -> false
    		| [[], a] when Coeff.equal a Coeff.z -> true
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
