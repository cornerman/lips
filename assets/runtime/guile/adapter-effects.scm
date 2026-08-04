;;; guile adapter, effect contracts: the imperative shell, for the real run.
(use-modules (ice-9 rdelim))

(define (read-a-line) (read-line))
(define (end-of-input? x) (eof-object? x))
(define (emit line) (display line) (newline))

(define (die message subject)
  (display message (current-error-port))
  (display " " (current-error-port))
  (display subject (current-error-port))
  (newline (current-error-port))
  (exit 1))
