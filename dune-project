(lang dune 2.1)

(generate_opam_files true)

(source
 (github PaulRaUnite/VPL))

(authors
 "Sylvain Boulmé <Sylvain.Boulme@univ-grenoble-alpes.fr>"
 "Alexis Fouilhé <a@Alexis-Fouilhe.fr>"
 "Alexandre Maréchal <Alex.Marechal@univ-grenoble-alpes.fr>"
 "David Monniaux <David.Monniaux@univ-grenoble-alpes.fr>"
 "Michaël Périn <Michael.Perin@univ-grenoble-alpes.fr>"
 "Hang Yu <Hang.Yu@univ-grenoble-alpes.fr>")

(maintainers "Alexandre Maréchal <Alex.Marechal@univ-grenoble-alpes.fr>")

(homepage "https://github.com/PaulRaUnite/VPL")

(license LGPL-3.0)

(name vpl-core)

(version 0.6)

(package
 (name vpl-core)
 (synopsis "Coq-certified library for computing with convex polyhedra")
 (description "Coq-certified library for computing with convex polyhedra")
 (depends
  (ocaml
   (>= 4.08))
  base-unix
  dune
  zarith))
