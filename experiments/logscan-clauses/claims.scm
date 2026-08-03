;;; Check (b): a claim over ONE definition, offline, with no VM, no process and
;;; no built binary. The witness in logscan.lips:5 becomes two claims on keep?.
(load "runtime.scm")
(load "clauses.scm")

(define failures 0)

(define (claim name got want)
  (cond ((equal? got want) (display "ok   ") (display name) (newline))
        (else (set! failures (+ failures 1))
              (display "FAIL ") (display name)
              (display " got=") (write got)
              (display " want=") (write want) (newline))))

;; @from logscan.lips:5 -- the worked example, read as two claims on keep?
(claim "witness keeps {\"a\":\"1\"} under a=1"
       (keep? (json-parse "{\"a\":\"1\"}") (parse-spec '("a=1"))) #t)
(claim "witness drops {\"a\":\"2\"} under a=1"
       (keep? (json-parse "{\"a\":\"2\"}") (parse-spec '("a=1"))) #f)

;; @from logscan.lips:2 -- "every field" means every one of them
(claim "an absent field never equals a given value"
       (keep? (json-parse "{\"b\":\"1\"}") (parse-spec '("a=1"))) #f)
(claim "two fields must both hold"
       (keep? (json-parse "{\"a\":\"1\",\"b\":\"x\"}") (parse-spec '("a=1" "b=y"))) #f)

;; @from logscan.lips:2 -- one field named twice is still "every field"
(claim "a=1 a=2 can never both hold"
       (keep? (json-parse "{\"a\":\"1\"}") (parse-spec '("a=1" "a=2"))) #f)

(exit failures)
