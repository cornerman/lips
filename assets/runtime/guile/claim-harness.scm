;;; The claim harness: how this runtime judges a claim and reports the verdict.
;;;
;;; Written once and shared by every program, like the adapters beside it. lips
;;; emits only the claim FORMS -- (feed-lines ...) and (claim ...) -- and knows
;;; nothing about how a verdict is printed or how a failure becomes an exit code.
(define claim-failures 0)

(define (claim name got want)
  (cond ((equal? got want) (display "ok   ") (display name) (newline))
        (else (set! claim-failures (+ claim-failures 1))
              (display "FAIL ") (display name)
              (display " got=") (write got)
              (display " want=") (write want) (newline))))

;;; The last form of a claims file: a failed claim must fail the build, so an
;;; unrun or broken claim can never read as a held one.
(define (claims-done)
  (exit claim-failures))
