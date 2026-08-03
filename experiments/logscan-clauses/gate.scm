;;; The subset gate: proof that the minted core can reach the world only
;;; through the contract set. Reads clauses.scm AS DATA (homoiconicity paying
;;; off: no parser), then checks two things and names every offender.
;;;
;;;   1. Every free identifier is a base form, a base procedure, a declared
;;;      contract, or a clause the core defines itself.
;;;   2. Every clause carries a @from provenance comment.
;;;
;;; A gate failure is a mint defect, caught before anything runs.

(load "contracts.scm")

(define core-file "clauses.scm")

(define (names-of decls) (map car decls))

(define allowed-names
  (append base-forms base-procedures
          (names-of pure-contracts) (names-of effect-contracts)))

(define (read-forms file)
  (with-input-from-file file
    (lambda ()
      (let loop ((form (read)) (acc '()))
        (if (eof-object? form) (reverse acc) (loop (read) (cons form acc)))))))

(define forms (read-forms core-file))

;; Pass 1: the names the core defines itself.
(define clause-names
  (map (lambda (form) (car (cadr form)))
       (filter (lambda (form) (and (pair? form) (eq? (car form) 'define))) forms)))

(define known (append allowed-names clause-names))

;; Pass 2: every free identifier, with lambda/let/clause parameters bound.
(define offenders '())

(define (report name) (set! offenders (cons name offenders)))

(define (walk expr bound)
  (cond ((symbol? expr)
         (if (or (memq expr bound) (memq expr known)) #t (report expr)))
        ((not (pair? expr)) #t)
        ((eq? (car expr) 'quote) #t)
        ((eq? (car expr) 'lambda)
         (walk-body (cddr expr) (append (cadr expr) bound)))
        ((or (eq? (car expr) 'let) (eq? (car expr) 'let*))
         (let ((bindings (cadr expr)))
           (for-each (lambda (b) (walk (cadr b) bound)) bindings)
           (walk-body (cddr expr) (append (map car bindings) bound))))
        (else (for-each (lambda (e) (walk e bound)) expr))))

(define (walk-body exprs bound)
  (for-each (lambda (e) (walk e bound)) exprs))

(for-each
 (lambda (form)
   (if (and (pair? form) (eq? (car form) 'define))
       (walk-body (cddr form) (cdr (cadr form)))
       (walk form '())))
 forms)

;; Pass 3: provenance. Textual, because `read` drops comments, and provenance
;; is a comment on purpose: it must survive into the file a human reads.
(define (lines-of file)
  (with-input-from-file file
    (lambda ()
      (let loop ((line (read-line)) (acc '()))
        (if (eof-object? line) (reverse acc) (loop (read-line) (cons line acc)))))))

(use-modules (ice-9 rdelim) (srfi srfi-1) (srfi srfi-13))

(define unprovenanced
  (let loop ((lines (lines-of core-file)) (previous "") (acc '()))
    (cond ((null? lines) (reverse acc))
          ((and (string-prefix? "(define" (car lines))
                (not (string-contains previous "@from")))
           (loop (cdr lines) (car lines) (cons (car lines) acc)))
          (else (loop (cdr lines) (car lines) acc)))))

(define (report-list label items)
  (display label)
  (display (length items))
  (newline)
  (for-each (lambda (i) (display "    ") (write i) (newline)) items))

(display "gate: ") (display core-file) (newline)
(display "  clauses:           ") (display (length clause-names)) (newline)
(display "  effect contracts:  ") (display (length effect-contracts))
(display "  <- the program's entire reach into the world") (newline)
(report-list "  ungrounded names:  " (reverse offenders))
(report-list "  without @from:     " unprovenanced)
(exit (+ (length offenders) (length unprovenanced)))
