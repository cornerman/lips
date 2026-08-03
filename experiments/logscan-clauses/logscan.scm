#!/usr/bin/env guile
!#
;;; The real run: link the guile adapters, then the minted core.
(load "adapter-pure.scm")
(load "adapter-effects-guile.scm")
(load "clauses.scm")
(main (cdr (command-line)))
