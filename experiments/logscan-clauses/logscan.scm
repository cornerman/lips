#!/usr/bin/env guile
!#
;;; logscan -- what realize would emit: the runtime vocabulary, then the
;;; minted clauses, then the entry point. Assembled, never hand-edited.
(load "runtime.scm")
(load "clauses.scm")
(main (cdr (command-line)))
