;;; The minted part: one definition per thing the program says.
;;; Every clause names the program line that caused it. Nothing else is here.

;; @from logscan.lips:1 @from logscan.lips:2
(define (main args)
  (scan (parse-spec args)))

;; @from logscan.lips:2 @from logscan.lips:5
(define (parse-spec args)
  (cond ((null? args) '())
        (else (cons (parse-pair (car args)) (parse-spec (cdr args))))))

;; @from logscan.lips:2 @from logscan.lips:5 @from logscan.lips:6
(define (parse-pair arg)
  (or (string-cut arg #\=)
      (die "argument is not field=value:" arg)))

;; @from logscan.lips:1
(define (scan spec)
  (scan-line (read-a-line) spec))

;; @from logscan.lips:1 @from logscan.lips:3
(define (scan-line line spec)
  (cond ((end-of-input? line) 'done)
        ((keep? (record-of line) spec) (emit line) (scan spec))
        (else (scan spec))))

;; @from logscan.lips:1 @from logscan.lips:7
(define (record-of line)
  (or (json-parse line)
      (die "line is not JSON:" line)))

;; @from logscan.lips:2
(define (keep? record spec)
  (cond ((null? spec) #t)
        ((field-equals? record (field-name (car spec)) (field-value (car spec)))
         (keep? record (cdr spec)))
        (else #f)))

;; @from logscan.lips:2
(define (field-equals? record name value)
  (equal? (field-of record name) value))
