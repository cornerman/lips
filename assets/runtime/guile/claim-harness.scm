;;; The claim harness: how this runtime judges a claim and reports the verdict.
;;;
;;; Written once and shared by every program, like the adapters beside it. lips
;;; emits only the claim FORMS -- (feed-args ...), (feed-lines ...), (claim ...)
;;; -- and knows nothing about how a verdict is printed, how a failure becomes an
;;; exit code, or how a program that stops itself is observed.
(define claim-failures 0)

;;; A claim is a MACRO so the expression it judges is delayed: a program whose
;;; behaviour is to stop (die "not field=value:" "a") must be observable, and a
;;; procedure would have run it before the catch was in place. Delaying it buys
;;; two things at once: one failing claim no longer aborts every claim after it,
;;; and a stated failure becomes an ordinary value to compare against.
(define-syntax claim
  (syntax-rules ()
    ((_ name expr want)
     (claim-value name
                  (catch 'died
                         (lambda () expr)
                         (lambda (key . args) (cons 'died args)))
                  want))))

;;; So a claim over a program that stops reads:
;;;   (claim "bad argument" (parse-pair "a")
;;;          (list 'died "argument is not field=value:" "a"))

(define (claim-value name got want)
  (cond ((equal? got want) (display "ok   ") (display name) (newline))
        (else (set! claim-failures (+ claim-failures 1))
              (display "FAIL ") (display name)
              (display " got=") (write got)
              (display " want=") (write want) (newline))))

;;; The last form of a claims file: a failed claim must fail the build, so an
;;; unrun or broken claim can never read as a held one.
(define (claims-done)
  (exit claim-failures))
