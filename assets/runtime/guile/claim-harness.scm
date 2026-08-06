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
;;;
;;; EVERY error is caught, not only a stated stop. An unexpected one (car of an
;;; empty list) is this claim's failure and must read as one; catching only 'died
;;; let it abort the whole file, so every claim after it went unjudged while the
;;; build reported the first failure it happened to reach.
(define-syntax claim
  (syntax-rules ()
    ((_ name expr want)
     (claim-value name
                  (catch #t
                         (lambda () expr)
                         (lambda (key . args)
                           (if (eq? key 'died)
                               (cons 'died args)
                               (cons 'error (cons key args)))))
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
;;;
;;; ONE or ZERO, never the count: an exit status is masked to its low byte, so
;;; exactly 256 failing claims would have exited 0 and the build would have
;;; passed. What the caller needs is held or not held; the count is on stdout.
(define (claims-done)
  (exit (if (zero? claim-failures) 0 1)))
