;;; The contract set: every name the minted core may reach the world through.
;;; Declaration only. What provides each name is an adapter, chosen per runtime
;;; and linked by name, exactly as ${pkgs.<path>} names a package realize binds.
;;;
;;; This file is data. `gate.scm` reads it, and a name the core uses that is not
;;; here (or defined by the core itself) is a gate failure, not a link error.

;; Pure contracts: no effect, but not in the base notation, so a runtime must
;; provide them. R7RS-small has neither JSON nor string search.
(define pure-contracts
  '((json-parse  1 "text -> record, or #f when the text is not JSON")
    (string-cut  2 "text char -> (before . after) at the first char, or #f")
    (field-of    2 "record name -> the field's value, or #f when absent")
    (field-name  1 "pair -> its name")
    (field-value 1 "pair -> its value")))

;; Effect contracts: THE PROGRAM'S ENTIRE REACH INTO THE WORLD. Four names.
;; A reviewer reads this list instead of auditing the implementation.
(define effect-contracts
  '((read-a-line  0 "-> the next input line, or the end-of-input value")
    (end-of-input? 1 "x -> whether x is the end-of-input value")
    (emit         1 "line -> writes it to the output, followed by a newline")
    (die          2 "message subject -> stops the program, naming the subject")))

;; The base notation: R7RS-small core forms and pure procedures, present on
;; every runtime, carrying no authority. Listed so the gate can tell a base
;; call from an ungrounded one.
(define base-forms
  '(define cond else or and if quote let* let letrec lambda))

(define base-procedures
  '(cons car cdr null? equal? not eq? pair? string? number? boolean? list))
