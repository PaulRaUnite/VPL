(** {!module:Pol} treats equalities and inequalities differently.
This module is the data structure that hosts the inequalities of a polyhedron.
It represents only sets of inequalities with {b nonempty interior}, meaning that these sets must be feasible and they should not contain any implicit equality.

{e Remarks.} It can be used only with variables of {!module:Var.Positive} (because of {!module:Splx}).
*)

module Cs = Cstr.Rat
module Vec = Cs.Vec

module Debug = Opt.Debug

type 'c t = 'c Cons.t list

let list x = x

let isTop (s : 'c t) = (s = [])

(** The certificates are the constraints that must be added to obtain the associated result.*)
type 'c prop_t =
| Empty of 'c
| Trivial
| Implied of 'c
| Check of 'c Cons.t

type 'c rel_t =
| NoIncl
| Incl of 'c list

type 'c simpl_t =
| SimplMin of 'c t
| SimplBot of 'c

module Stat = struct

	let n_lp : int ref = ref 0

	let size_lp : int ref = ref 0

	let reset : unit -> unit
		= fun () ->
		n_lp := 0;
		size_lp := 0

	let incr_size : int -> unit
		= fun size ->
		size_lp := !size_lp + size

	let incr : unit -> unit
		= fun () ->
		n_lp := !n_lp + 1

	let base_n_cstr : int ref = ref 0
end

let nil : 'c t = []

let to_string: (Var.t -> string) -> 'c t -> string
= fun varPr s -> List.fold_left (fun str c -> str ^ (Cons.to_string varPr c) ^ "\n") "" s

let to_string_ext: 'c Factory.t -> (Var.t -> string) -> 'c t -> string
= fun factory varPr s ->
	List.fold_left (fun str c -> str ^ (Cons.to_string_ext factory varPr c) ^ "\n") "" s

let equal s1 s2 =
	let incl l1 = List.for_all
		(fun (c2,_) ->
		List.exists (fun (c1,_) -> Cs.inclSyn c1 c2) l1)
	in
	incl s1 s2 && incl s2 s1

exception CertSyn

let certSyn: 'c Factory.t -> 'c Cons.t -> Cs.t -> 'c
	= fun factory (c1,cert1) c2 ->
	let v1 = Cs.get_v c1 in
	let v2 = Cs.get_v c2 in
	match Vec.isomorph v2 v1 with
	| Some r -> (* v2 = r.v1 *)
		begin
		let cert =
			let cste = Scalar.Rat.sub
				(Cs.get_c c2)
				(Scalar.Rat.mul r (Cs.get_c c1))
			in
            if Cs.get_typ c2 = Cstr_type.Lt && Scalar.Rat.equal r Scalar.Rat.u && Scalar.Rat.equal cste Scalar.Rat.z
            then cert1
			else if Scalar.Rat.lt cste Scalar.Rat.z
			then factory.Factory.mul r cert1
			else
                let cste_cert = factory.Factory.triv (Cs.get_typ c2) cste
				in
				factory.Factory.mul r cert1
				|> factory.Factory.add cste_cert
		in
		match Cs.get_typ c1, Cs.get_typ c2 with
		| Cstr_type.Lt, Cstr_type.Le -> factory.Factory.to_le cert
		| _,_ -> cert
		end
	| None -> Pervasives.raise CertSyn

let synIncl : 'c1 Factory.t -> 'c1 EqSet.t -> 'c1 t -> Cs.t -> 'c1 prop_t
	= fun factory es s c ->
	match Cs.tellProp c with
	| Cs.Trivial -> Trivial
	| Cs.Contrad -> Empty (factory.Factory.top)
	| Cs.Nothing -> begin
		let (cstr1, cons1) = EqSet.filter2 factory es c in
		let cert1 = try certSyn factory cons1 c
			with CertSyn -> Cons.get_cert cons1
		in
		match Cs.tellProp cstr1 with
		| Cs.Trivial -> Implied cert1
		| Cs.Contrad -> Empty cert1
		| Cs.Nothing ->
		try
			let consI = List.find (fun (cstr2,_) -> Cs.incl cstr2 cstr1) s in
			Implied (factory.Factory.add cert1 (certSyn factory consI cstr1))
		with Not_found ->
			Check (cstr1,cert1)
		end

(* the coefficient whose id is -1 is the constraint to compute*)
let mkCert : 'c Factory.t -> 'c Cons.t list -> Cs.t -> (int * Scalar.Rat.t) list -> 'c
	= fun factory conss cstr combination ->
	try
		let a0 = List.assoc (-1) combination in
		let combination' = List.fold_left
			(fun res (i,a) ->
				if i = -1
				then res
				else (i,Scalar.Rat.div a a0) :: res)
			[] combination
		in
		let cons = Cons.linear_combination_cons factory conss combination'
		in
		certSyn factory cons cstr
	with
		Not_found -> Pervasives.failwith "IneqSet.mkCert"

let incl: 'c1 Factory.t -> Var.t -> 'c1 EqSet.t -> 'c1 t ->  'c2 t -> 'c1 rel_t
	= fun factory nxt es s1 s2 ->
	let rec _isIncl : 'c1 list -> Splx.t Splx.mayUnsatT option -> 'c2 t -> 'c1 rel_t
		= fun certs optSx ->
		function
		| [] -> Incl certs
		| c::t ->
			match synIncl factory es s1 (Cons.get_c c) with
			| Empty _ -> NoIncl
			| Trivial -> failwith "IneqSet.incl"
			| Implied c -> _isIncl (c::certs) optSx t
			| Check c1 ->
				let sx =
					match optSx with
					| Some sx -> sx
					| None -> Splx.mk nxt (List.mapi (fun i (c,_) -> i,c) s1)
				in
				let c1' = Cs.compl (Cons.get_c c1) in
				match Splx.checkFromAdd (Splx.addAcc sx (-1, c1')) with
				| Splx.IsOk _ -> NoIncl
				| Splx.IsUnsat w ->
					let cert = mkCert factory s1 (Cons.get_c c1) w
						|> factory.Factory.add (Cons.get_cert c1)
					in
					_isIncl (cert::certs) (Some sx) t
	in
	_isIncl [] None s2

type 'c satChkT = Sat of Splx.t | Unsat of 'c

(** [chkFeasibility nvar s] checks whether [s] is satisfiable and returns a
simplex object with a satisfied state if it is. If it is not satisfiable, then
a linear combination of the input constraints is returned. [nvar] is used for
fresh variable generation. *)
let chkFeasibility: 'c Factory.t -> Var.t -> 'c t -> 'c satChkT
= fun factory nvar s ->
	let cs = List.mapi (fun i c -> (i, Cons.get_c c)) s in
	match Splx.checkFromAdd (Splx.mk nvar cs) with
	| Splx.IsOk sx -> Sat sx
	| Splx.IsUnsat w -> Unsat (Cons.linear_combination_cert factory s w)

let rename factory s fromX toY = List.map (Cons.rename factory fromX toY) s

let pick : Var.t option Rtree.t -> 'c t -> Var.t option
	= fun msk s ->
	let update v n p m =
		match Scalar.Rat.cmpz n with
		| 0 -> (v, p, m)
		| n when n < 0 -> (v, p + 1, m)
		| _ -> (v, p, m + 1)
	in
	let rec build m cnt ve =
		match m, cnt, ve with
		| Rtree.Nil, _, _ -> Rtree.Nil
		| _, rt, Rtree.Nil -> rt
		| Rtree.Sub (l1, n1, r1), Rtree.Nil, Rtree.Sub (l2, n2, r2) ->
			let l = build l1 Rtree.Nil l2 in
			let r = build r1 Rtree.Nil r2 in
			let n =
				if n1 = None then
					(None, 0, 0)
				else
					update n1 n2 0 0
			in
			Rtree.Sub (l, n, r)

		| Rtree.Sub (l1,n1,r1), Rtree.Sub (l2,n2,r2), Rtree.Sub (l3,n3,r3) ->
			let l = build l1 l2 l3 in
			let r = build r1 r2 r3 in
			let n =
				if n1 = None then
					n2
				else
					let (_, p, m) = n2 in
					update n1 n3 p m
			in
			Rtree.Sub (l, n, r)
	in
	let scores = List.fold_left (fun a c -> build msk a (Cs.get_v (Cons.get_c c)))
		Rtree.Nil s
	in
	let (optv, _) =
		let choose (best, sc) (v, p, m) =
			if v = None || p = 0 && m = 0 then
				(best, sc)
			else
				let nsc = p * m - (p + m) in
				if best = None then
					(v, nsc)
				else
					if nsc < sc then
						(v, nsc)
					else
						(best, sc)
		in
		Rtree.fold (fun _ -> choose) (None, -1) scores
	in
	optv

let trim : 'c t -> Splx.t -> 'c t * Splx.t
	= fun s0 sx0 ->
	let check : int -> 'c Cons.t -> ('c t * Splx.t) -> ('c t * Splx.t)
		= fun i c (s, sx) ->
		let sx1 = Splx.compl sx i in
		match Splx.check sx1 with
		| Splx.IsOk _ -> c::s, sx
		| Splx.IsUnsat _ -> s, Splx.forget sx i
	in
	(* XXX: Why is this fold_right? *)
	List.fold_right2 check (Misc.range 0 (List.length s0)) s0 ([], sx0)

let trimSet : Var.t -> 'c t -> 'c t
	= fun nxt s ->
	let cl = List.mapi (fun i c -> i, Cons.get_c c) s in
	match Splx.checkFromAdd (Splx.mk nxt cl) with
	| Splx.IsUnsat _ -> Pervasives.failwith "IneqSet.trimSet"
	| Splx.IsOk sx -> Pervasives.fst (trim s sx)

let simpl: 'c Factory.t -> Var.t -> 'c EqSet.t -> 'c t -> 'c simpl_t
	= fun factory nxt es s ->
	let rec filter s1
		= function
		| [] ->
			let cl = List.mapi (fun i c -> i, Cons.get_c c) s1 in
			(match Splx.checkFromAdd (Splx.mk nxt cl) with
			| Splx.IsOk sx -> SimplMin (Pervasives.fst (trim s1 sx))
			| Splx.IsUnsat w -> SimplBot (Cons.linear_combination_cert factory s w))
		| h::t ->
			match synIncl factory es s1 (Cons.get_c h) with
			| Trivial | Implied _ -> filter s1 t
			| Empty f -> SimplBot f
			| Check h1 ->
			filter (h1::(List.filter (fun c -> not (Cons.implies h1 c)) s1)) t
	in
	filter [] (List.rev s)

(* XXX: À revoir?
Cette fonction n'est utilisée que dans la projection?
A priori, si synIncl renvoie Check c, c n'aura pas été réécrit car il vient d'une contrainte déjà présente dans le polyèdre.*)
let synAdd : 'c Factory.t -> 'c EqSet.t -> 'c t -> 'c Cons.t -> 'c t
	= fun factory es s cons ->
	match synIncl factory es s (Cons.get_c cons) with
	| Trivial | Implied _ -> s
	| Empty _ -> failwith "IneqSet.synAdd"
	| Check _ ->
		cons::(List.filter (fun c2 -> not (Cons.implies cons c2)) s)

let subst: 'c Factory.t -> Var.t -> 'c EqSet.t -> Var.t -> 'c Cons.t -> 'c t -> 'c t
	= fun factory nxt es x e s ->
	let gen s c =
		let c1 =
			if Scalar.Rat.cmpz (Vec.get (Cs.get_v (Cons.get_c c)) x) = 0
			then c
			else Cons.elimc factory x e c
		in
		synAdd factory es s c1
	in
	let s' = (List.fold_left gen nil s) in
	trimSet nxt s'


(* XXX: le new_horizon renvoyé devrait être la nouvelle next variable *)
let pProj : 'c Factory.t -> Var.t -> 'c t -> Flags.scalar -> 'c t
	= fun factory x s scalar_type ->
	Proj.proj factory scalar_type [x] s
		|> Pervasives.fst

let fmElim: 'c Factory.t -> Var.t -> 'c EqSet.t -> Var.t ->  'c t -> 'c t
	= fun factory nxt es x s ->
	let (pos, z, neg) = List.fold_left (fun (p, z, n) c ->
		match Scalar.Rat.cmpz (Vec.get (Cs.get_v (Cons.get_c c)) x) with
		| 0 -> (p, c::z, n)
		| a when a < 0 -> (c::p, z, n)
		| _ -> (p, z, c::n)) ([], [], []) s
	in
	let zs = List.rev z in
	let add : 'c Factory.t -> 'c t -> 'c Cons.t -> 'c t
	  = fun factory s c ->
	  synAdd factory es s c
	in
	let apply factory s0 c = List.fold_left
		(fun s c1 -> add factory s (Cons.elimc factory x c c1)) s0 neg
	in
    List.fold_left (apply factory) zs pos
	|> trimSet nxt

let pProjM : 'c Factory.t -> Var.t list -> 'c t -> Flags.scalar -> 'c t
	= fun factory xs s scalar_type ->
	Proj.proj factory scalar_type xs s
		|> Pervasives.fst

let fmElimM: 'c Factory.t -> Var.t -> 'c EqSet.t -> Var.t option Rtree.t -> 'c t -> 'c t
= fun factory nxt es msk s ->
	let rec elim s1 =
		match pick msk s1 with
		| None -> s1
		| Some x ->
			let s2 = fmElim factory nxt es x s1 in
			elim s2
	in
	elim s

let joinSetup_1: 'c2 Factory.t -> Var.t -> Var.t option Rtree.t -> Var.t -> 'c1 t
	-> Var.t * Var.t option Rtree.t * (('c1,'c2) Cons.discr_t) Cons.t list
	= fun factory2 nxt relocTbl alpha s ->
	let apply (nxt1, relocTbl1, s1) c =
		let (nxt2, relocTbl2, c1) = Cons.joinSetup_1 factory2 nxt1 relocTbl1 alpha c in
		(nxt2, relocTbl2, c1::s1)
	in
	List.fold_left apply (nxt, relocTbl, nil) s

let joinSetup_2: 'c1 Factory.t -> Var.t -> Var.t option Rtree.t -> Var.t -> 'c2 t
	-> Var.t * Var.t option Rtree.t * (('c1,'c2) Cons.discr_t) Cons.t list
	= fun factory1 nxt relocTbl alpha s ->
	let apply (nxt1, relocTbl1, s1) c =
		let (nxt2, relocTbl2, c1) = Cons.joinSetup_2 factory1 nxt1 relocTbl1 alpha c in
		(nxt2, relocTbl2, c1::s1)
	in
	List.fold_left apply (nxt, relocTbl, nil) s

let minkowskiSetup_1: 'c2 Factory.t -> Var.t -> Var.t option Rtree.t -> 'c1 t
	-> Var.t * Var.t option Rtree.t * (('c1,'c2) Cons.discr_t) Cons.t list
	= fun factory2 nxt relocTbl s ->
	let apply (nxt1, relocTbl1, s1) c =
		let (nxt2, relocTbl2, c1) = Cons.minkowskiSetup_1 factory2 nxt1 relocTbl1 c in
		(nxt2, relocTbl2, c1::s1)
	in
	List.fold_left apply (nxt, relocTbl, nil) s

let minkowskiSetup_2: 'c1 Factory.t -> Var.t -> Var.t option Rtree.t -> 'c2 t
	-> Var.t * Var.t option Rtree.t * (('c1,'c2) Cons.discr_t) Cons.t list
	= fun factory1 nxt relocTbl s ->
	let apply (nxt1, relocTbl1, s1) c =
		let (nxt2, relocTbl2, c1) = Cons.minkowskiSetup_2 factory1 nxt1 relocTbl1 c in
		(nxt2, relocTbl2, c1::s1)
	in
	List.fold_left apply (nxt, relocTbl, nil) s


(** [isRed sx conss i] checks whether the constraint identified by [i] is redundant in
the constraint set represented by [sx]. *)
let isRed: Splx.t -> int -> bool
	= fun sx i ->
	Stat.incr ();
	Stat.incr_size !Stat.base_n_cstr;
	let sx' = Splx.compl sx i in
	match Splx.check sx' with
	| Splx.IsOk _ -> false
	| Splx.IsUnsat _ -> true

module RmRedAux = struct

    let glpk: 'c Cons.t list -> Scalar.Symbolic.t Rtree.t -> 'c t
        = fun s point ->
        let point = Rtree.map Cstr.Rat.Vec.ofSymbolic point in
		let cstrs = List.map Cons.get_c s in
		let l = Min.Rat_Glpk.minimize point cstrs in
		let s' = List.filter
			(fun (cstr,_) -> List.exists (fun (cstr',_) -> Cstr.Rat.equalSyn cstr cstr') l)
			s
		in
		s'

	let classic : Splx.t -> (int * 'c Cons.t) list -> 'c t
		= fun sx conss ->
		let classic: Splx.t * 'c t -> (int * 'c Cons.t) -> Splx.t * 'c t
			= fun (sx, s) (i,cons) ->
			if isRed sx i
			then begin
				Stat.base_n_cstr := !Stat.base_n_cstr - 1;
				(Splx.forget sx i, s)
			end
			else (sx, cons::s)
		in
		List.fold_left classic (sx, []) conss
		|> Pervasives.snd

end

(** [rmRed s sx] removes all the redundancy from [s]. The simplex object [sx] is
assumed to be in a statisfied state (it has been returned by [Splx.check]) and
to represent [s]. The returned simplex object is [sx] with all the redundant
bounds [Splx.forgot]ten. The returned certificate list contains a certificate
for all the removed constraints. *)
let rmRedAux : 'c t -> Splx.t -> Scalar.Symbolic.t Rtree.t -> 'c t
	= let rmRedAux'
		= fun s sx point ->
		if List.length s <= 1
		then s
		else
			match !Flags.min with
			| Flags.Raytracing ->
				RmRedAux.glpk s point
			| Flags.Classic -> begin
				Stat.base_n_cstr := List.length s;
				let conss = List.mapi (fun i c -> (i,c)) s in
				RmRedAux.classic sx conss
				end
			| _ -> Pervasives.invalid_arg "IneqSet.rmRedAux"
	in
	fun s sx ->
	Heuristic.apply_min
		(List.map Cons.get_c s)
		(rmRedAux' s sx)

(** [isIncl s c] checks whether [c] is implied by [s] on syntactic grounds.*)
let inclSyn: 'c t -> 'c Cons.t -> bool
	= fun s c ->
	match List.filter (fun c' -> Cons.implies c' c) s with
	| [] -> false
	| [_] -> true
	| _ -> failwith "IneqSet.addM"

(** [rmSynRed2 s l] removes syntactically redundant constraints from the union
of [s] and [l].*)
let rmRedSyn: 'c t -> 'c Cons.t list -> 'c t
	= let rm1: 'c t -> 'c Cons.t -> ' t
		= fun s c ->
		if inclSyn s c
		then s
		else
			let (_, s2) = List.partition (fun c' -> Cons.implies c c') s in
			c::s2
	in
	fun s l -> List.fold_left rm1 [] (s @ l)

(* precondition :
	- s @ l has non empty interior
	- l contains no trivial constraints
*)

let addM: Var.t -> 'c t -> 'c Cons.t list -> Scalar.Symbolic.t Rtree.t -> 'c t
	= fun nvar s conss point ->
	let s2 = rmRedSyn s conss in
	if List.length s2 <= 1
	then s2
	else
		let ilist = List.mapi (fun i c -> (i, Cons.get_c c)) s2 in
		match Splx.checkFromAdd (Splx.mk nvar ilist) with
		| Splx.IsUnsat _ -> Pervasives.failwith "IneqSet.addM: unexpected unsat set"
		| Splx.IsOk sx -> rmRedAux s2 sx point

(*
(*TEST FOR EFFICIENCY : *)
let addM: Var.t -> 'c t -> 'c Cons.t list -> Scalar.Symbolic.t Rtree.t -> 'c t
	= fun nvar s conss point ->
	let apply : Flags.min_method -> 'c t
		= fun min ->
		let s' = s @ conss in
		if List.length s' <= 1
		then s'
		else
			match min with
			| Flags.Raytracing (Flags.Splx)->
				RmRedAux.splx s' point
			| Flags.Raytracing (Flags.Glpk)->
				RmRedAux.glpk s'
			| Flags.Classic -> begin
				let s2 = rmRedSyn s conss in
				let ilist = List.mapi (fun i c -> (i, Cons.get_c c)) s2 in
				match Splx.checkFromAdd (Splx.mk nvar ilist) with
				| Splx.IsUnsat _ -> Pervasives.failwith "IneqSet.addM: unexpected unsat set"
				| Splx.IsOk sx -> begin
					Stat.base_n_cstr := List.length s2;
					let conss = List.mapi (fun i c -> (i,c)) s2 in
					RmRedAux.classic sx conss
					end
				end
			| _ -> Pervasives.invalid_arg "IneqSet.rmRedAux"
	in
	match !Flags.min with
	| Flags.MHeuristic -> apply (Heuristic.min (List.map Cons.get_c (s @ conss)))
	| m -> apply m
*)


(** Returns the partition into regions of the given polyhedron, according to the given normalization point.
    Certificates are lost during the process: frontiers of regions have no certificate.
*)
let get_regions_from_point : 'c Factory.t -> 'c t -> Vec.t -> ('c t * Vector.Symbolic.t) list
    = fun factory p point ->
    let regions = PoltoPLP.minimize_and_plp factory point p in
    List.map
        (fun (reg,cons) ->
            let ineqs = List.map
                (fun cstr -> cstr, factory.top)
                ((Cons.get_c cons) :: PoltoPLP.PLP.Region.get_cstrs reg)
            and point = Vector.Symbolic.ofRat reg.PoltoPLP.PLP.Region.point
            in
            (ineqs, point)
        ) regions.PoltoPLP.mapping

let satisfy : 'c t -> Vec.t -> bool
    = fun ineqs point ->
    List.for_all
        (fun cons -> Cons.get_c cons |> Cs.satisfy point)
        ineqs
