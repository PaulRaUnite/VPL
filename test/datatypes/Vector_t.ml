open Vpl

module VectorRtree = struct

	module Make_Tests(Coeff : Scalar.Type) = struct
		module Vec = Vector.VectorRtree(Coeff)
		let x = Vec.V.fromInt 1
		let y = Vec.V.fromInt 2
		let z = Vec.V.fromInt 3

		let nxt = Vec.V.fromInt 4

		let varPr: Vec.V.t -> string
		= fun _x ->
			let vars: (Vec.V.t * string) list
			= [x, "x"; y, "y"; z, "z"]
			in
			try
				List.assoc _x vars
			with
			| Not_found -> "v" ^ (Vec.V.to_string _x)

		let v: (int * Vec.V.t) list -> Vec.t
		= fun l -> Vec.mk (List.map (fun (i, v) -> (Coeff.mk1 i, v)) l)

		(* Vec.elim *)
		let elimInFromOnlyTs: Test.t
		 = fun () ->
			let chk (name, using, from) = fun state ->
				try
					let _ = Vec.elim y using from in
					Test.fail name "Invalid_argument not raised" state
				with
				| Invalid_argument s when s = "Vec.elim" -> Test.succeed state
				| _ -> Test.fail name "unexpected exception raised" state
			in
			let tcs = [
				"simple0", v [1, x], v [1, x; 1, y]
			] in
			Test.suite "inFromOnly" (List.map chk tcs)

		let elimNotInFromTs: Test.t
		= fun () ->
			let chk (name, using, from) = fun state ->
				let r = Vec.elim y using from in
				if Vec.equal from r then
					Test.succeed state
				else
					Test.fail name (Vec.to_string varPr r) state
			in
			let tcs = [
				"simple0", v [1, x; 1, y; 1, z], v [1, x];
				"nowhere0", v [1, x; 1, z], v [1, x]
			] in
			Test.suite "notInFrom" (List.map chk tcs)

		let elimInBothTs: Test.t
		= fun () ->
			let chk (name, using, from, expected) = fun state ->
				let r = Vec.elim y using from in
				if Vec.equal r expected then
					Test.succeed state
				else
					Test.fail name (Vec.to_string varPr r) state
			in
			let tcs = [
				"simple0", v [1, x; 1, y], v [-1, y], v [1, x]
			] in
			Test.suite "inBoth" (List.map chk tcs)

		let elimTs: Test.t
		= fun () ->
        Test.suite "elim" [elimInFromOnlyTs(); elimNotInFromTs(); elimInBothTs()]

		(* Vec.shift *)
		let shiftTs: Test.t
		= fun () ->
			(* Check that the coefficients in [vec] are to be found at the right place in [shiftedVec]. *)
			let chkCoefs (name, vec, relocTbl) = fun state ->
				let (_, shiftedVec, relocTbl1) = Vec.shift nxt vec relocTbl in
				let rec chk vec1 tbl1 =
					match vec1, tbl1 with
					| Rtree.Nil, _ -> true
					| _, Rtree.Nil -> false
					| Rtree.Sub (l, n, r), Rtree.Sub (lTbl, reloc, rTbl) ->
						let node =
							if Coeff.cmpz n = 0 then
								true
							else
								match reloc with
								| None -> false
								| Some x -> Coeff.cmp n (Vec.get shiftedVec x) = 0
						in
						node && chk l lTbl && chk r rTbl
				in
				if chk vec relocTbl1 then
					Test.succeed state
				else
					Test.fail name "difference between coefficients" state
			in
			(* Check that no more than the expected coefficients are to be found in the result.
			XXX: this way of checking is maybe overkill and redundant with [chkCoefs]. *)
			let chkNil (name, v, r) = fun state ->
				let (_, sv, nr) = Vec.shift nxt v r in
				let rec build nv v1 r1 =
					match v1, r1 with
					| Rtree.Nil, _ -> nv
					| _, Rtree.Nil -> failwith "Vec_t.shift_ts"
					| Rtree.Sub (l1, n1, r1), Rtree.Sub (l2, n2, r2) ->
						let nv1 =
							if Coeff.cmpz n1 = 0 then
								nv
							else
								match n2 with
								| None -> failwith "Vec_t.shift_ts"
								| Some x -> Rtree.set false nv x true
						in
						build (build nv1 l1 l2) r1 r2
				in
				let rec chk v1 r1 =
					match v1, r1 with
					| Rtree.Nil, Rtree.Nil -> true
					| Rtree.Nil, _ | _, Rtree.Nil -> false
					| Rtree.Sub (l1, n1, r1), Rtree.Sub (l2, n2, r2) ->
						let a =
							if Coeff.cmpz n1 = 0 then
								not n2
							else
								n2
						in
						a && chk l1 l2 && chk r1 r2
				in
				if chk sv (build Rtree.Nil v nr) then
					Test.succeed state
				else
					Test.fail name "unexpected non-nul coefficient" state
			in
			(* "Syntactic" criteria on the relocation table:
				- once set, a node does not change
				- all variables are allocated before the returned "nxt" *)
			let chkReloc (name, v, r) = fun state ->
				let (nxt1, _, nr) = Vec.shift nxt v r in
				let rec chk r nr =
					match r, nr with
					| Rtree.Nil, Rtree.Nil -> true
					| Rtree.Nil, Rtree.Sub (l, None, r) -> chk Rtree.Nil l && chk Rtree.Nil r
					| Rtree.Nil, Rtree.Sub (l, Some x, r) -> (Vec.V.cmp x nxt1 = -1) && chk Rtree.Nil l && chk Rtree.Nil r
					| Rtree.Sub _, Rtree.Nil -> false
					| Rtree.Sub (_, Some _, _), Rtree.Sub (_, None, _) -> false
					| Rtree.Sub (l1, None, r1), Rtree.Sub (l2, None, r2) -> chk l1 l2 && chk r1 r2
					| Rtree.Sub (l1, None, r1), Rtree.Sub (l2, Some x, r2) -> (Vec.V.cmp x nxt1 = -1) && chk l1 l2 && chk r1 r2
					| Rtree.Sub (l1, Some x1, r1), Rtree.Sub (l2, Some x2, r2) -> x1 = x2 && chk l1 l2 && chk r1 r2
				in
				if chk r nr then
					Test.succeed state
				else
					Test.fail name "bad relocation table" state
			in
			let x1 = nxt in
			let y1 = Vec.V.next x1 in
			let tcs = [
				"nil0", Vec.mk [], Rtree.mk None [];
				"nil1", Vec.mk [], Rtree.mk None [x, Some x1];
				"one0", Vec.mk [Coeff.u, x], Rtree.mk None [x, Some x1];
				"one1", Vec.mk [Coeff.u, x], Rtree.mk None [];
				"one2", Vec.mk [Coeff.mk1 2, x], Rtree.mk None [x, Some x1];
				"none0", Vec.mk [Coeff.u, x; Coeff.u, y], Rtree.mk None [];
				"some0", Vec.mk [Coeff.u, x; Coeff.u, y], Rtree.mk None [x, Some x1];
				"some1", Vec.mk [Coeff.u, x; Coeff.u, y], Rtree.mk None [y, Some y1];
				"all0", Vec.mk [Coeff.u, x; Coeff.u, y],
					Rtree.mk None [x, Some x1; y, Some y1]
			] in
			Test.suite "shift" [
				Test.suite "coefs" (List.map chkCoefs tcs);
				Test.suite "nil" (List.map chkNil tcs);
				Test.suite "reloc" (List.map chkReloc tcs)
			]

		(* getVars *)
		let getVarsTs: Test.t
		  =  fun () ->
          let chk (name, vars, vecs) state =
				let vars' = Vec.getVars vecs in
				if Vec.V.Set.equal (Vec.V.Set.of_list vars) vars'
				then Test.succeed state
				else Test.fail name "not equal" state
			 in
			 let x = Vec.V.XH and y = Vec.V.XO Vec.V.XH and z = Vec.V.XI Vec.V.XH and t = Vec.V.XO (Vec.V.XO Vec.V.XH) in
			 let tcs = [
			"empty0", [], [Vec.mk []];
			"empty1", [], [Vec.mk []; Vec.mk []];
			"one0", [x], [Vec.mk [Coeff.u, x]];
			"one1", [t], [Vec.mk [Coeff.u, t]];
			"one2", [z], [Vec.mk [Coeff.u, z]];
			"m0", [x; y; z], [Vec.mk [Coeff.u, x; Coeff.mk1 2, z]; Vec.mk [Coeff.u, y]]
				] in
			 Test.suite "listVars" (List.map chk tcs)

		let ts: Test.t
		=  fun () ->
        Test.suite Coeff.name [elimTs(); shiftTs(); getVarsTs()]
	end

	module Rat = struct
		include Make_Tests(Scalar.Rat)
		module Coeff = Vector.Rat.Positive.Coeff
			(* Vec.gcd *)

		let x = Vector.Rat.Positive.V.fromInt 1
		let y = Vector.Rat.Positive.V.fromInt 2
		let z = Vector.Rat.Positive.V.fromInt 3

		let gcdTs: Test.t
			= fun () ->
			let chk (name, r, v1) = fun state ->
				let r1 = Vector.Rat.Positive.gcd v1 in
				if Coeff.cmp r r1 = 0 then
					Test.succeed state
				else
					Test.fail name (Coeff.to_string r1) state
			in
			let tcs = [
				"nil0", Coeff.u, Vector.Rat.Positive.mk [];
				"u0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x];
				"u1", (Coeff.mk 2 1), Vector.Rat.Positive.mk [Coeff.mk1 2, x];
				"m0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x; Coeff.mk1 2, y];
				"m1", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 2, y];
				"m2", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 4, y];
				"f0", Coeff.mk1 2, Vector.Rat.Positive.mk [Coeff.mk 2 1, x; Coeff.mk 2 1, y];
				"f1", Coeff.mk 3 2,
					Vector.Rat.Positive.mk [Coeff.mk 2 9, x; Coeff.mk 2 3, y];

				"hole0", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 4, y; Coeff.mk1 6, z];
				"neg0", Coeff.u, Vector.Rat.Positive.mk [Coeff.negU, x]
			] in
			Test.suite "gcd" (List.map chk tcs)

		let ts: Test.t
			= fun () ->
            List.map Test.run [elimTs; shiftTs; gcdTs ; getVarsTs]
            |> Test.suite Coeff.name
	end

	module Symbolic = Make_Tests(Scalar.Symbolic)

	module Float = Make_Tests(Scalar.Float)

	module RelInt = Make_Tests(Scalar.RelInt)

	let ts : Test.t
		= fun () ->
        List.map Test.run [Rat.ts ; Symbolic.ts ; Float.ts ; RelInt.ts]
        |> Test.suite "Rtree"
end

module VectorMap = struct

	module Make_Tests(Coeff : Scalar.Type)(V : Var.Type) = struct
		module Vec = Vector.VectorMap(Coeff)(V)
		let x = Vec.V.fromInt 1
		let y = Vec.V.fromInt 2
		let z = Vec.V.fromInt 3
		let t = Vec.V.fromInt 3

		let nxt = Vec.V.fromInt 4

		let varPr: Vec.V.t -> string
		= fun _x ->
			let vars: (Vec.V.t * string) list
			= [x, "x"; y, "y"; z, "z"]
			in
			try
				List.assoc _x vars
			with
			| Not_found -> "v" ^ (Vec.V.to_string _x)

		let v: (int * Vec.V.t) list -> Vec.t
		= fun l -> Vec.mk (List.map (fun (i, v) -> (Coeff.mk1 i, v)) l)

		(* Vec.elim *)
		let elimInFromOnlyTs: Test.t
		= fun () ->
			let chk (name, using, from) = fun state ->
				try
					let _ = Vec.elim y using from in
					Test.fail name "Invalid_argument not raised" state
				with
				| Invalid_argument s when s = "Vec.elim" -> Test.succeed state
				| _ -> Test.fail name "unexpected exception raised" state
			in
			let tcs = [
				"simple0", v [1, x], v [1, x; 1, y]
			] in
			Test.suite "inFromOnly" (List.map chk tcs)

		let elimNotInFromTs: Test.t
		= fun () ->
			let chk (name, using, from) = fun state ->
				let r = Vec.elim y using from in
				if Vec.equal from r then
					Test.succeed state
				else
					Test.fail name (Vec.to_string varPr r) state
			in
			let tcs = [
				"simple0", v [1, x; 1, y; 1, z], v [1, x];
				"nowhere0", v [1, x; 1, z], v [1, x]
			] in
			Test.suite "notInFrom" (List.map chk tcs)

		let elimInBothTs: Test.t
		= fun () ->
			let chk (name, using, from, expected) = fun state ->
				let r = Vec.elim y using from in
				if Vec.equal r expected then
					Test.succeed state
				else
					Test.fail name (Vec.to_string varPr r) state
			in
			let tcs = [
				"simple0", v [1, x; 1, y], v [-1, y], v [1, x]
			] in
			Test.suite "inBoth" (List.map chk tcs)

		let elimTs: Test.t
		= fun () ->
        Test.suite "elim" [elimInFromOnlyTs(); elimNotInFromTs(); elimInBothTs()]

		(* getVars *)
		let getVarsTs: Test.t
		= fun () ->
            let chk (name, vars, vecs) state =
				let vars' = Vec.getVars vecs in
				if Vec.V.Set.equal (Vec.V.Set.of_list vars) vars'
				then Test.succeed state
				else Test.fail name "not equal" state
			 in
			 (*let x = Vec.V.XH and y = Vec.V.XO Vec.V.XH and z = Vec.V.XI Vec.V.XH and t = Vec.V.XO (Vec.V.XO Vec.V.XH) in*)
			 let tcs = [
			"empty0", [], [Vec.mk []];
			"empty1", [], [Vec.mk []; Vec.mk []];
			"one0", [x], [Vec.mk [Coeff.u, x]];
			"one1", [t], [Vec.mk [Coeff.u, t]];
			"one2", [z], [Vec.mk [Coeff.u, z]];
			"m0", [x; y; z], [Vec.mk [Coeff.u, x; Coeff.mk1 2, z]; Vec.mk [Coeff.u, y]]
				] in
			 Test.suite "listVars" (List.map chk tcs)

		let ts: Test.t
		= fun () ->
        Test.suite Coeff.name [elimTs(); getVarsTs()]
	end

	module Rat = struct
		module Int = struct
			include Make_Tests(Scalar.Rat)(Var.Int)
			module Coeff = Vector.Rat.Positive.Coeff
				(* Vec.gcd *)

			let x = Vector.Rat.Positive.V.fromInt 1
			let y = Vector.Rat.Positive.V.fromInt 2
			let z = Vector.Rat.Positive.V.fromInt 3

			let gcdTs: Test.t
				= fun () ->
				let chk (name, r, v1) = fun state ->
					let r1 = Vector.Rat.Positive.gcd v1 in
					if Coeff.cmp r r1 = 0 then
						Test.succeed state
					else
						Test.fail name (Coeff.to_string r1) state
				in
				let tcs = [
					"nil0", Coeff.u, Vector.Rat.Positive.mk [];
					"u0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x];
					"u1", (Coeff.mk 2 1), Vector.Rat.Positive.mk [Coeff.mk1 2, x];
					"m0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x; Coeff.mk1 2, y];
					"m1", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 2, y];
					"m2", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 4, y];
					"f0", Coeff.mk1 2, Vector.Rat.Positive.mk [Coeff.mk 2 1, x; Coeff.mk 2 1, y];
					"f1", Coeff.mk 3 2,
						Vector.Rat.Positive.mk [Coeff.mk 2 9, x; Coeff.mk 2 3, y];

					"hole0", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 4, y; Coeff.mk1 6, z];
					"neg0", Coeff.u, Vector.Rat.Positive.mk [Coeff.negU, x]
				] in
				Test.suite "gcd" (List.map chk tcs)

			let ts: Test.t
				= fun () ->
                Test.suite Var.Int.name [elimTs(); gcdTs(); getVarsTs()]
		end

		module String = struct
			include Make_Tests(Scalar.Rat)(Var.String)
			module Coeff = Vector.Rat.Positive.Coeff
				(* Vec.gcd *)

			let x = Vector.Rat.Positive.V.fromInt 1
			let y = Vector.Rat.Positive.V.fromInt 2
			let z = Vector.Rat.Positive.V.fromInt 3

			let gcdTs: Test.t
				= fun () ->
				let chk (name, r, v1) = fun state ->
					let r1 = Vector.Rat.Positive.gcd v1 in
					if Coeff.cmp r r1 = 0 then
						Test.succeed state
					else
						Test.fail name (Coeff.to_string r1) state
				in
				let tcs = [
					"nil0", Coeff.u, Vector.Rat.Positive.mk [];
					"u0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x];
					"u1", (Coeff.mk 2 1), Vector.Rat.Positive.mk [Coeff.mk1 2, x];
					"m0", Coeff.u, Vector.Rat.Positive.mk [Coeff.u, x; Coeff.mk1 2, y];
					"m1", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 2, y];
					"m2", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 2, x; Coeff.mk1 4, y];
					"f0", Coeff.mk1 2, Vector.Rat.Positive.mk [Coeff.mk 2 1, x; Coeff.mk 2 1, y];
					"f1", Coeff.mk 3 2,
						Vector.Rat.Positive.mk [Coeff.mk 2 9, x; Coeff.mk 2 3, y];

					"hole0", Coeff.mk 2 1, Vector.Rat.Positive.mk [Coeff.mk1 4, y; Coeff.mk1 6, z];
					"neg0", Coeff.u, Vector.Rat.Positive.mk [Coeff.negU, x]
				] in
				Test.suite "gcd" (List.map chk tcs)

			let ts: Test.t
				= fun () ->
                Test.suite Var.String.name [elimTs(); gcdTs (); getVarsTs()]
		end

		let ts: Test.t
			= fun () ->
            Test.suite "Rat" [Int.ts(); String.ts()]
	end

	module Symbolic = struct
		module Int = Make_Tests(Scalar.Symbolic)(Var.Int)
		module String = Make_Tests(Scalar.Symbolic)(Var.String)

		let ts: Test.t
			= fun() ->
            Test.suite "Symbolic" [Int.ts(); String.ts()]
	end

	module Float = struct
		module Int = Make_Tests(Scalar.Float)(Var.Int)
		module String = Make_Tests(Scalar.Float)(Var.String)

		let ts: Test.t
			= fun () ->
            Test.suite "Float" [Int.ts(); String.ts()]
	end

	module RelInt = struct
		module Int = Make_Tests(Scalar.RelInt)(Var.Int)
		module String = Make_Tests(Scalar.RelInt)(Var.String)

		let ts: Test.t
			= fun () ->
            Test.suite "RelInt" [Int.ts (); String.ts ()]
	end

	let ts : Test.t
		= fun () ->
        List.map Test.run [Rat.ts ; Symbolic.ts ; Float.ts ; RelInt.ts]
        |> Test.suite "IntMap"
end

let ts : Test.t
	= fun () ->
    Test.suite "Vector" [VectorRtree.ts() ; VectorMap.ts()]
