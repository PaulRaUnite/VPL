module Cs = Cstr.Rat.Positive
module Poly = Poly.Make(Vector.Rat.Positive)

type t = {
    lin : Tableau.Vector.t;
    cst : Scalar.Rat.t
}

let empty : t = {
    lin = [];
    cst = Scalar.Rat.z
}

let getLin : t -> Tableau.Vector.t
    = fun c -> c.lin

let getCst : t -> Scalar.Rat.t
    = fun c -> c.cst

let equal : t -> t -> bool
    = fun c c' ->
    if not (Scalar.Rat.equal c.cst c'.cst) then false
    else if List.length c.lin <> List.length c'.lin then false
    else List.for_all2 Scalar.Rat.equal c.lin c'.lin

let pr : (int -> string) -> t -> string
    = fun paramPr c ->
    let s = List.mapi (fun i a -> (i, a)) c.lin
        |> List.filter (fun (_, a) -> not(Scalar.Rat.isZ a))
        |> List.map (fun (i, a) -> Printf.sprintf "%s * %s" (Scalar.Rat.to_string a) (paramPr i))
        |> String.concat " + "
    in
    if not (Scalar.Rat.well_formed c.cst)
    then if s = "" then "0"
        else s
    else
        let cs = Scalar.Rat.to_string c.cst in
        if s = "" then cs
        else Printf.sprintf "%s + %s" s cs

let paramDfltPr : int -> string
    = fun i -> "p" ^ Pervasives.string_of_int i

let to_string : t -> string
    = fun c -> pr paramDfltPr c

let mk : Scalar.Rat.t list -> Scalar.Rat.t -> t
    = fun l b -> {lin = l; cst = b}

let mkSparse : int -> (int * Scalar.Rat.t) list -> Scalar.Rat.t -> t
    = let rec fill : int -> int -> (int * Scalar.Rat.t) list -> Tableau.Vector.t
        = fun n i ->
        function
        | [] -> if i < n then Scalar.Rat.z :: fill n (i + 1) [] else []
        | ((x, a) :: l') as l ->
            if n <= i || x < i then Pervasives.invalid_arg "Tableau.ParamCoeff.mk"
            else if x = i then a :: fill n (i + 1) l'
            else Scalar.Rat.z :: fill n (i + 1) l
    in
    fun n l a -> {
        lin = List.sort (fun (i, _) (i', _) -> Pervasives.compare i i') l |> fill n 0;
        cst = a
    }

let mkCst : Scalar.Rat.t -> t
    = fun a -> mkSparse 0 [] a

let ofPoly : (Cs.Vec.V.t -> int) -> int -> Poly.t -> t
    = fun tr n p ->
    let (cst, lin) = List.partition (function
        | (m, _) when Poly.MonomialBasis.equal m Poly.MonomialBasis.null -> true
        | _ -> false
        ) (List.map Poly.Monomial.data (Poly.data p))
    in
    let lin' = List.map (function
        | (m, a) when Poly.MonomialBasis.to_list_expanded m |> List.length = 1 ->
            let x = Poly.MonomialBasis.to_list_expanded m |> List.hd in (tr x, a)
        | (_ , _) -> Pervasives.invalid_arg "Tableau.ParamCoeff.ofPolyQ"
        ) lin
    in
    match cst with
    | _ :: _ :: _ -> Pervasives.failwith "Tableau.ParamCoeff.ofPolyQ"
    | [] -> mkSparse n lin' Scalar.Rat.z
    | [_, cst'] -> mkSparse n lin' cst'

let toPoly : (int -> Cs.Vec.V.t) -> t -> Poly.t
    = fun tr c ->
    Poly.mk_cste (
        List.mapi (fun i a ->
            ([tr i, 1],a)
        ) c.lin |> Poly.mk_list
    ) c.cst

let to_cstr : (int -> Cs.Vec.V.t) -> Cstr_type.cmpT_extended -> t -> Cs.t
	= fun to_vpl sign c ->
	let lin = List.mapi (fun i a -> (a,to_vpl i)) c.lin in
	let cst = c.cst in
	Cstr_type.(match sign with
	| LT -> Cs.lt lin (Cs.Vec.Coeff.neg cst)
	| LE -> Cs.le lin (Cs.Vec.Coeff.neg cst)
	| GT -> Cs.lt (List.map (fun (a, x) -> (Cs.Vec.Coeff.neg a, x)) lin) cst
	| GE -> Cs.le (List.map (fun (a, x) -> (Cs.Vec.Coeff.neg a, x)) lin) cst
	| EQ -> Cs.eq lin (Cs.Vec.Coeff.neg cst)
    | NEQ -> Pervasives.invalid_arg "ParamCoeff.to_cstr: NEQ")

let add : t -> t -> t
    = fun c c' ->
    try {
        lin = List.map2 Scalar.Rat.add c.lin c'.lin;
        cst = Scalar.Rat.add c.cst c'.cst
    }
    with Invalid_argument _ -> Pervasives.invalid_arg "Tableau.ParamCoeff.add"

let mul : Scalar.Rat.t -> t -> t
    = fun a c -> {
        lin = List.map (Scalar.Rat.mul a) c.lin;
        cst = Scalar.Rat.mul a c.cst
    }

let sub : t -> t -> t
    = fun c c' ->
    add c (mul Scalar.Rat.negU c')

let is_constant : t -> bool
      = fun c -> List.for_all (Scalar.Rat.equal Scalar.Rat.z) c.lin

let is_zero : t -> bool
      = fun c -> is_constant c && Scalar.Rat.equal Scalar.Rat.z c.cst

let nParams : t -> int
      = fun c -> List.length c.lin

let eval : t -> (int -> Scalar.Rat.t) -> Scalar.Rat.t
	= fun c f ->
	List.fold_left (fun (i, v) c ->
        (i + 1, Scalar.Rat.add v (Scalar.Rat.mul c (f i)))
    ) (0, c.cst) c.lin
	|> Pervasives.snd

let eval2 : t -> (int -> Scalar.Symbolic.t) -> Scalar.Symbolic.t
	= fun c f ->
	List.fold_left (fun (i, v) c ->
        (i + 1, Scalar.Symbolic.add v (Scalar.Symbolic.mulr c (f i)))
    ) (0, c.cst |> Scalar.Symbolic.ofQ) c.lin
	|> Pervasives.snd
