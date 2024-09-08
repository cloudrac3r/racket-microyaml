; optional checking on typed/untyped interaction makes it 10x faster (shallow is only 5x faster)
#lang typed/racket/base/optional
(require racket/list)

(provide port->tokens
         file->tokens
         (struct-out token)
         Token)

(struct token
  ([type : Symbol]
   [val : Any])
  #:transparent #:type-name Token)


(define s-white '(#\  #\tab #\newline #\return))
(define ns-indicator '(#\? #\, #\[ #\] #\{ #\} #\# #\& #\* #\! #\| #\> #\% #\@))
(define not-ns-plain-first (append ns-indicator s-white))
(define not-ns-plain-rest (append '(#\: #\# #\' #\") s-white))

(: port->tokens : Input-Port -> (Listof Token))
(define (port->tokens in)
  (: keep-reading (->* ((Char -> Boolean)) ((Listof Char)) String))
  (define (keep-reading pred [result null])
    (define b (peek-char in))
    (cond [(eof-object? b) (list->string (reverse result))]
          [(pred b) (keep-reading pred (cons (cast (read-char in) Char) result))]
          [else (list->string (reverse result))]))
  (let loop ([result : (Listof Token) null]
             [bol-whitespace : (Option Integer) 0]
             [indent-stack : (Pairof Integer (Listof Integer)) '(0)])
    (define b (peek-char in))
    (define t
      (cond
        ;; base case
        [(eof-object? b)
         (token 'EOF eof)]

        ;; colon
        [(char=? b #\:)
         (read-char in)
         (token 'COLON b)]

        ;; quotes
        [(char=? b #\')
         (read-char in)
         (token 'SQUOTE b)]
        [(char=? b #\")
         (read-char in)
         (token 'DQUOTE b)]

        ;; question
        [(and (char=? b #\?) (eq? (peek-char in 1) #\ ))
         (token 'QUESTION (read-string 2 in))]

        ;; list item
        [(and (char=? b #\-) (eq? (peek-char in 1) #\ ))
         (token 'LI (read-string 2 in))]

        ;; newline
        [(or (char=? b #\newline) (eq? b #\return))
         ;; merge adjacent newlines
         (read-char in)
         (if (and (pair? result) (eq? (token-type (car result)) 'NEWLINE))
             (begin b #f)
             (token 'NEWLINE b))]

        ;; discard comments at start of line
        [(and (number? bol-whitespace) (char=? b #\#))
         (keep-reading (λ (b) (not (or (char=? b #\newline) (char=? b #\return)))))
         #f]

        ;; whitespace
        [(or (char=? b #\ ) (char=? b #\tab))
         (define ws (keep-reading (λ (b) (or (char=? b #\ ) (char=? b #\tab)))))
         (cond
           ;; read and discard comments if applicable
           [(eq? (peek-char in) #\#)
            (keep-reading (λ (b) (not (or (char=? b #\newline) (char=? b #\return)))))
            #f]
           ;; just whitespace
           [else
            (token 'WHITESPACE ws)])]

        ;; indicator symbol
        [(or (memq b ns-indicator))
         (read-char in)
         (token 'INDICATOR b)]

        ;; plain string
        [(not (memq b not-ns-plain-first))
         (define pln (keep-reading (λ (b) (not (memq b not-ns-plain-rest)))))
         (token 'PLAIN pln)]

        ;; that should be everything
        [else
         (error 'port->tokens "unreadable character: ~v" b)]))

    (cond
      [(not t)
       (loop result bol-whitespace indent-stack)]
      [else
       ;; handle whitespace, indents, outdents
       (define type (token-type t))
       (cond
         ;; end of file, fill in any missing outdents and return result
         [(eq? type 'EOF)
          (reverse
           (append (list t)
                   (map (λ (_) (token 'OUTDENT 0)) (cdr indent-stack))
                   result
                   ))]

         ;; increment whitespace at the start of a line
         [(and (number? bol-whitespace) (eq? type 'WHITESPACE) (string? (token-val t)))
          ;; whitespace token is deliberately not added at bol because we'll use indent/outdent/aligned tokens instead
          (loop result (+ bol-whitespace (string-length (token-val t))) indent-stack)]

         ;; set whitespace to 0 at the start of a line
         [(eq? type 'NEWLINE)
          (loop (cons t result) 0 indent-stack)]

         ;; non whitespace character, determine whether the indentation has changed for this line
         [(number? bol-whitespace)
          (define last-indent (car indent-stack))

          ;; list item markers and explicit key markers count as 2 additional spaces of indentation
          (define li-bol-whitespace
            (+ bol-whitespace (if (eq? type 'LI) 2 0)))

          (define-values (new-tokens new-indent-stack)
            (cond
              ;; indent
              [(li-bol-whitespace . > . last-indent)
               (values (list* t (token 'INDENT li-bol-whitespace) result)
                       ((cons li-bol-whitespace indent-stack) . ann . (Pairof Integer (Listof Integer))))]
              ;; outdent
              [(li-bol-whitespace . < . last-indent)
               ;; find the point in the indent stack where the stack's indentation is at least as low as the current whitespace
               (define new-indent-stack
                 (memf (λ ([x : Integer])
                         (cond [(x . <= . li-bol-whitespace) #t] ; found it
                               [else #f])) ; keep looking
                       (cdr indent-stack)))
               (when (or (not new-indent-stack) (null? new-indent-stack))
                 (error 'port->tokens "indent stack got emptied. was: ~v, tried to move to: ~a" indent-stack li-bol-whitespace))
               (values (append (list t)
                               (make-list (- (length indent-stack) (length new-indent-stack)) (token 'OUTDENT li-bol-whitespace))
                               result)
                       (new-indent-stack . ann . (Pairof Integer (Listof Integer))))]
              ;; same indentation as previous line
              [else
               ;; don't generate 'ALIGNED tokens, aligned is assumed
               (values (cons t result)
                       (indent-stack . ann . (Pairof Integer (Listof Integer))))]))

          (cond
            ;; explicit key tokens generate an additional indent *following them*
            ;; (we set bol-whitespace to a number and the next token will generate that indent for us)
            [(eq? type 'QUESTION)
             (define qu-bol-whitespace (+ 2 li-bol-whitespace))
             (loop new-tokens qu-bol-whitespace new-indent-stack)]
            [else
             (loop new-tokens #f new-indent-stack)])]

         ;; list in a list, need to generate a special bonus indent token for this one too
         [(and (eq? type 'LI) (eq? (token-type (car result)) 'LI))
          (define last-indent (car indent-stack))
          (define new-indent (+ 2 last-indent))
          (loop (list* t (token 'INDENT new-indent) result) #f (cons new-indent indent-stack))]

         ;; line continues, not bol-whitespace
         [else
          (loop (cons t result) bol-whitespace indent-stack)])])))

(: file->tokens : Path-String -> (Listof Token))
(define (file->tokens file-name)
  (call-with-input-file file-name (λ (in) (port->tokens in))))

(module+ test
  (require racket/pretty)
  (define v (time (file->tokens "test/easy-nested-list.yaml")))
  (for ([t v]
        [i (in-naturals)])
    (printf "~a: ~v~n" i t)))
