module Cs = Cstr.Rat.Positive
module Var = Var.Positive

module Test (Min : Min.Type) = struct
	
	module Proj_ = Proj.Proj(Min)
	module ProjBuild = Proj_.Build
	module Objective = Proj_.PLP.Objective
	module ParamCoeff = Proj_.PLP.ParamCoeff
	
	let var = Var.fromInt
	let x = var 1 and y = var 2 and z = var 3

	let le
	  = fun l b -> Cs.mk Cstr.Le (List.map (fun (a, x) -> (Scalar.Rat.mk1 a, x)) l) (Scalar.Rat.mk1 b)

	module Norm
	  = struct

		 let buildTs : T.testT
		   = let chk : string * Var.t list * Cs.t list * Tableau.Vector.t -> T.stateT -> T.stateT
		  = fun (nm, xl, l, ev) state ->
		  let av = ProjBuild.Norm.build (Var.Set.of_list xl) l in
		  T.equals nm Tableau.Vector.to_string Tableau.Vector.equal ev av state
		in
		[
		  "unbounded", [y],
		  [le [-1, x; -1, y] ~-1; le [-1, x; 1, y] 1],
		  [Q.of_ints ~-1 2; Q.of_ints ~-5 2; Q.minus_one]
		]
		|> List.map chk
		|> T.suite "build"

		 let ts : T.testT
		   = [
	 	buildTs
		   ] |> T.suite "Norm"

	end

	let buildProjConsTs : T.testT
	  = let eq : Tableau.Vector.t list -> Tableau.Vector.t list -> bool
		   = fun l l' ->
		   if List.length l <> List.length l' then false
		   else List.for_all2 Tableau.Vector.equal l l'
		 in
		 let pr : Tableau.Vector.t list -> string
		   = fun l ->
		   List.map Tableau.Vector.to_string l
		   |> String.concat "\n"
		 in
		 let chk : string * Var.t list * Cs.t list * Tableau.Vector.t list -> T.stateT -> T.stateT
		   = fun (nm, xs, l, el) state ->
		   let al = ProjBuild.buildProjCons xs l in
		   T.equals nm pr eq el al state
		 in
		 [
		   "sas12", [z], [
			    le [1, x; 1, y; 1, z] 2;
			    le [1, x; 1, y; -1, z] 2;
			    le [-3, x; -1, y; 1, z] ~-3;
			    le [-3, x; -1, y; -1, z] ~-3;
			    le [-1, x; 1, y; 2, z] 2;
			    le [-1, x; 1, y; -2, z] 2;
			    le [] 1
			  ],
		   [
		[Q.one; Q.minus_one; Q.one; Q.minus_one; Q.of_int 2; Q.of_int ~-2; Q.zero; Q.zero]
		   ]
		 ]
		 |> List.map chk
		 |> T.suite "buildProjCons"

	let buildObjTs : T.testT
	  = let chk : string * Var.t list * Cs.t list * Objective.t -> T.stateT -> T.stateT
		   = fun (nm, xs, l, eo) state ->
		   let ao = ProjBuild.buildObj false xs l in
		   T.equals nm Objective.to_string Objective.equal eo ao state
		 in
		 [
		   "sas12", [x; y], [
			    le [1, x; 1, y; 1, z] 2;
			    le [1, x; 1, y; -1, z] 2;
			    le [-3, x; -1, y; 1, z] ~-3;
			    le [-3, x; -1, y; -1, z] ~-3;
			    le [-1, x; 1, y; 2, z] 2;
			    le [-1, x; 1, y; -2, z] 2;
			    le [] 1
			    ], Objective.mk [
				   ParamCoeff.mkSparse 2 [0, Q.minus_one; 1, Q.minus_one] Q.zero;
				   ParamCoeff.mkSparse 2 [0, Q.minus_one; 1, Q.minus_one] Q.zero;
				   ParamCoeff.mkSparse 2 [0, Q.of_int 3; 1, Q.one] Q.zero;
				   ParamCoeff.mkSparse 2 [0, Q.of_int 3; 1, Q.one] Q.zero;
				   ParamCoeff.mkSparse 2 [0, Q.one; 1, Q.minus_one] Q.zero;
				   ParamCoeff.mkSparse 2 [0, Q.one; 1, Q.minus_one] Q.zero;
				   ParamCoeff.mkSparse 2 [] Q.zero
				 ] (ParamCoeff.mkSparse 2 [] Q.zero)
		 ]
		 |> List.map chk
		 |> T.suite "buildObj"

	let ts : T.testT
	  = [
	  Norm.ts;
	  buildProjConsTs;
	  buildObjTs
	] |> T.suite Min.name
end

module New2 = struct
	module Glpk = struct
		module Rat = struct
			module Min = Min.RatVec_Glpk2(Vector.Rat.Positive)
			include Test(Min)
		end

		module Float = struct
			module Min = Min.RatVec_Glpk2(Vector.Float.Positive)
			include Test(Min)
		end

		module Symbolic = struct
			module Min = Min.RatVec_Glpk2(Vector.Symbolic.Positive)
			include Test(Min)
		end
	end
	module Splx = struct
		module Rat = struct
			module Min = Min.RatVec_Splx2(Vector.Rat.Positive)
			include Test(Min)
		end

		module Float = struct
			module Min = Min.RatVec_Splx2(Vector.Float.Positive)
			include Test(Min)
		end

		module Symbolic = struct
			module Min = Min.RatVec_Splx2(Vector.Symbolic.Positive)
			include Test(Min)
		end
	end
end

let ts : T.testT
	= [
	New2.Glpk.Rat.ts;
	New2.Glpk.Float.ts;
	New2.Glpk.Symbolic.ts;
	New2.Splx.Rat.ts;
	New2.Splx.Float.ts;
	New2.Splx.Symbolic.ts;
	] 
	|> T.suite "ProjBuild"