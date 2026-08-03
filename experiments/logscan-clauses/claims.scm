;;; Claims over the minted core, offline: no process, no stdin, no VM, no build.
;;; The core is unchanged; only the adapter linked under it differs from the
;;; real run. That is what makes every clause testable, effectful ones included.
(load "adapter-pure.scm")
(load "adapter-effects-memory.scm")
(load "clauses.scm")

(define failures 0)

(define (claim name got want)
  (cond ((equal? got want) (display "ok   ") (display name) (newline))
        (else (set! failures (+ failures 1))
              (display "FAIL ") (display name)
              (display " got=") (write got)
              (display " want=") (write want) (newline))))

(define (run-on lines args)
  (feed-lines lines)
  (main args)
  (emitted))

(define (died-on lines args)
  (feed-lines lines)
  (catch 'died
         (lambda () (main args) 'no-failure)
         (lambda (key message subject) (list message subject))))

;; --- the whole program, end to end, in memory --------------------------------

;; @from logscan.lips:5 -- the worked example, run as the program runs it
(claim "witness prints only the matching line"
       (run-on '("{\"a\":\"1\"}" "{\"a\":\"2\"}") '("a=1"))
       '("{\"a\":\"1\"}"))

;; @from logscan.lips:3 -- unchanged means byte for byte, not re-serialized
(claim "a kept line is printed exactly as it arrived"
       (run-on '("{\"a\":\"1\",  \"b\" : \"x\"}") '("a=1"))
       '("{\"a\":\"1\",  \"b\" : \"x\"}"))

;; @from logscan.lips:6 -- an argument that is not field=value stops the program
(claim "a bad argument fails, naming it"
       (died-on '("{\"a\":\"1\"}") '("a"))
       '("argument is not field=value:" "a"))

;; @from logscan.lips:7 -- a line that is not JSON stops the program
(claim "a non-JSON line fails, naming it"
       (died-on '("oops") '("a=1"))
       '("line is not JSON:" "oops"))

;; --- single definitions ------------------------------------------------------

;; @from logscan.lips:2 -- "every field" means every one of them
(claim "an absent field never equals a given value"
       (keep? (json-parse "{\"b\":\"1\"}") (parse-spec '("a=1"))) #f)
(claim "two fields must both hold"
       (keep? (json-parse "{\"a\":\"1\",\"b\":\"x\"}") (parse-spec '("a=1" "b=y"))) #f)
(claim "a=1 a=2 can never both hold"
       (keep? (json-parse "{\"a\":\"1\"}") (parse-spec '("a=1" "a=2"))) #f)

;; @from logscan.lips:2 -- comparison is exact, the reading the words carry
(claim "text does not equal a JSON number"
       (keep? (json-parse "{\"a\":1}") (parse-spec '("a=1"))) #f)

(exit failures)
