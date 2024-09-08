; optional checking on typed-untyped interaction makes it 4x faster (shallow doesn't help)
#lang typed/racket/base/optional
(require racket/format
         racket/list
         racket/match
         racket/port
         racket/string)
(require "lex-yaml.rkt")

(provide
 port->yaml
 port->yaml/string
 file->yaml
 file->yaml/string
 Yaml-Hash-String
 Yaml-List-String
 Yaml-Value-String
 Yaml-Hash
 Yaml-List
 Yaml-Key
 Yaml-Value
 yaml-key?
 yaml-value?
 yaml-value-string?)


;; in this parser there is no backtracking and all necessary lookahead is done by the should-? functions

(define-type Yaml-Hash-String (Immutable-HashTable Symbol Yaml-Value-String))
(define-type Yaml-List-String (Listof Yaml-Value-String))
(define-type Yaml-Value-String (U String Yaml-Hash-String Yaml-List-String))

(define-type Yaml-Hash (Immutable-HashTable Yaml-Key Yaml-Value))
(define-type Yaml-List (Listof Yaml-Value))
(define-type Yaml-Key (U Symbol Number Boolean Yaml-Hash Yaml-List 'null))
(define-type Yaml-Value (U String Number Boolean Yaml-Hash Yaml-List 'null))

(define-predicate yaml-key? Yaml-Key)
(define-predicate yaml-value? Yaml-Value)
(define-predicate yaml-value-string? Yaml-Value-String)

(: read-typed-value : String -> (U String Number Boolean))
(define (read-typed-value str)
  (match str
    ;; https://yaml.org/type/bool.html
    [(or "y" "yes" "true" "on") #t]
    [(or "n" "no" "false" "off") #f]
    [_ (or (string->number str) str)]))

(define yaml-trace? (make-parameter #f))

(define-syntax-rule (create-tokens->yaml fn-name Hash-Type List-Type Key-Type Value-Type null-value hash-creator value-converter-fn forbid-non-string-keys?)
  (begin
    (: fn-name : (Vectorof Token) -> Value-Type)
    (define (fn-name v)
      (: trace : Symbol Any Natural -> Any)
      (define (trace fn mode i)
        (define vi (vector-ref v i))
        (when (yaml-trace?)
          (printf "TRACE: ~a / ~a -- #~a = ~v~n" (~a #:width 16 fn) (~a #:width 6 mode) i vi))
        (void))

      (define-syntax-rule (trace-value fn mode i body (... ...))
        (begin
          (trace fn mode i)
          (define result (let () body (... ...)))
          (when (yaml-trace?)
            (printf "TRACE RESULT:   -> ~a~n" result))
          result))

      (: error-handler : Symbol Any Natural -> Nothing)
      (define (error-handler fn mode i)
        (define vi (vector-ref v i))
        (define tokens-stack
          (with-output-to-string
            (λ ()
              (for ([j (in-range (max 0 (- i 12))
                                 (min (vector-length v) (+ i 7)))])
                (if (= i j)
                    (display "-> ")
                    (display "   "))
                (printf "#~a = ~v~n" j (vector-ref v j))))))
        (define how-did-we-get-here
          (string-join
           (reverse
            (cons
             (~a fn)
             (takef ((inst map String (Pairof (Option Symbol) Any))
                     (λ ([m : (Pairof (Option Symbol) Any)]) (~a (car m)))
                     (cdr (continuation-mark-set->context (current-continuation-marks))))
                    (λ ([m : String]) (string-prefix? m "read-")))))
           " -> "))
        (error fn "in mode ~a, can't read token #~a = ~v~nast trace: ~a~ntokens:~n~a" mode i vi how-did-we-get-here tokens-stack))

      (: read-hash (->* (Natural) (Symbol Hash-Type) (Values Natural Hash-Type)))
      (define (read-hash i [mode 'hash] [table (ann (hash-creator) Hash-Type)])
        (trace 'read-hash mode i)
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          [(should-read-hash-line? i)
           (define-values (i* key value) (read-hash-line i))
           (read-hash i* 'hash (hash-set table key value))]
          [else
           (values i table)]))

      (: should-read-indented-hash? : Natural -> Boolean)
      (define (should-read-indented-hash? i)
        (define vi (vector-ref v i))
        (cond
          [(eq? (token-type vi) 'EOF) #f]
          [else (and (eq? (token-type (vector-ref v i)) 'INDENT)
                     (should-read-hash-line? (add1 i)))]))

      (: read-indented-hash (->* (Natural) (Symbol Hash-Type) (Values Natural Hash-Type)))
      (define (read-indented-hash i [mode 'indent] [h : Hash-Type (hash-creator)])
        (trace 'read-indented-hash mode i)
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          [(and (eq? mode 'indent) (eq? type 'INDENT))
           (read-indented-hash (add1 i) 'hash h)]
          [(and (eq? mode 'hash) (should-read-hash-line? i))
           (define-values (i* value) (read-hash i))
           (read-indented-hash i* 'outdent value)]
          [(and (eq? mode 'outdent) (eq? type 'OUTDENT))
           (values (add1 i) h)]
          [else
           (error-handler 'read-indented-hash mode i)]))

      (: should-read-hash-line? : Natural -> Boolean)
      (define (should-read-hash-line? i)
        (trace-value
         'should-read-hash-line? '|| i
         (define vi (vector-ref v i))
         (cond
           [(eq? (token-type vi) 'EOF) #f]
           [(eq? (token-type vi) 'OUTDENT) #f]
           [(eq? (token-type vi) 'QUESTION) #t]
           [(eq? (token-type (vector-ref v (add1 i))) 'WHITESPACE) (should-read-hash-line? (add1 i))]
           [(eq? (token-type (vector-ref v (add1 i))) 'COLON) #t]
           [else #f])))

      (: read-hash-line (->* (Natural) (Symbol Key-Type Value-Type) (Values Natural Key-Type Value-Type)))
      (define (read-hash-line i [mode 'key] [key '||] [value ""])
        (trace 'read-hash-line mode i)
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          [(and (memq mode '(colon value question)) (eq? type 'WHITESPACE))
           (read-hash-line (add1 i) mode key value)]
          ;; 1 - implicit key
          [(and (eq? mode 'key) (eq? type 'PLAIN))
           (read-hash-line (add1 i) 'colon (string->symbol (cast (token-val vi) String)) value)]
          ;; 1 - explicit key
          [(and (eq? mode 'key) (eq? type 'QUESTION))
           (read-hash-line (add1 i) 'question key value)]
          [(eq? mode 'question)
           (define-values (i* key) (read-value i))
           (define typed-key
             (cond [(string? key) (string->symbol key)]
                   [(symbol? key) key]
                   [forbid-non-string-keys? (error 'read-hash-line "in strings mode, found explicit hash key ~v, which is not a string" key)]
                   [else key]))
           (read-hash-line i* 'colon typed-key value)]
          ;; 2
          [(and (eq? mode 'colon) (eq? type 'COLON))
           (read-hash-line (add1 i) 'value key value)]
          ;; 3
          [(eq? mode 'value)
           (define-values (i* value) (read-value i))
           (values i* key value)]
          [else
           (error-handler 'read-hash-line mode i)]))

      (: should-read-list? : Natural -> Boolean)
      (define (should-read-list? i)
        (and (eq? (token-type (vector-ref v i)) 'INDENT)
             (should-read-list-line? (add1 i))))

      (: read-list (->* (Natural) (Symbol List-Type) (Values Natural List-Type)))
      (define (read-list i [mode 'indent] [ls (ann null List-Type)])
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          [(and (eq? mode 'indent) (eq? type 'INDENT))
           (read-list (add1 i) 'list-line ls)]
          [(and (eq? mode 'list-line) (should-read-list-line? i))
           (define-values (i* value) (read-list-line i))
           (read-list i* 'list-line (cons value ls))]
          [(and (eq? mode 'list-line) (eq? type 'OUTDENT))
           (values (add1 i) (reverse ls))]
          [else
           (error-handler 'read-list mode i)]))

      (: should-read-list-line? : Natural -> Boolean)
      (define (should-read-list-line? i)
        (eq? (token-type (vector-ref v i)) 'LI))

      (: read-list-line (->* (Natural) (Symbol) (Values Natural Value-Type)))
      (define (read-list-line i [mode 'li])
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          [(and (eq? mode 'li) (eq? type 'LI))
           (read-value (add1 i))]
          [else
           (error-handler 'read-list-line mode i)]))

      (: read-value (->* (Natural) (Symbol String) (Values Natural Value-Type)))
      (define (read-value i [mode 'value] [buffer ""])
        (trace 'read-value mode i)
        (define vi (vector-ref v i))
        (define type (token-type vi))
        (cond
          ;; is value an indented list?
          [(and (eq? mode 'value) (eq? type 'NEWLINE) (should-read-list? (add1 i)))
           (read-list (add1 i))]
          ;; is value an indented hash?
          [(and (eq? mode 'value) (eq? type 'NEWLINE) (should-read-indented-hash? (add1 i)))
           (read-indented-hash (add1 i))]
          ;; is value an explicit key that's a hash?
          [(and (eq? mode 'value) (should-read-indented-hash? i))
           (read-indented-hash i)]
          ;; is value an explicit key that's a list?
          [(and (eq? mode 'value) (should-read-list? i))
           (read-list i)]
          ;; is value just a newline with no actual value?
          [(and (eq? mode 'value) (eq? type 'NEWLINE))
           (values (add1 i) null-value)]
          ;; is value a hash?
          [(and (eq? mode 'value) (should-read-hash-line? i))
           (read-hash i)]
          ;; is value []?
          [(and (eq? mode 'value) (eq? type 'INDICATOR))
           (read-value (add1 i) 'indicator buffer)]
          [(and (eq? mode 'indicator) (eq? type 'INDICATOR))
           (read-value (add1 i) 'indicator-end buffer)]
          ;; quoted/unquoted string continuation with whitespace
          [(and (eq? mode 'value*) (memq type '(PLAIN WHITESPACE INDICATOR COLON LI SQUOTE DQUOTE)))
           (read-value (add1 i) mode (~a buffer (token-val vi)))]
          [(and (eq? mode 'sq-str) (memq type '(PLAIN WHITESPACE INDICATOR COLON LI DQUOTE)))
           (read-value (add1 i) mode (~a buffer (token-val vi)))]
          [(and (eq? mode 'dq-str) (memq type '(PLAIN WHITESPACE INDICATOR COLON LI SQUOTE)))
           (read-value (add1 i) mode (~a buffer (token-val vi)))]
          ;; start of unquoted string
          [(and (eq? mode 'value) (eq? type 'PLAIN))
           (read-value (add1 i) 'value* (~a buffer (token-val vi)))]
          ;; quoted string
          [(and (eq? mode 'value) (eq? type 'SQUOTE))
           (read-value (add1 i) 'sq-str buffer)]
          [(and (eq? mode 'sq-str) (eq? type 'SQUOTE))
           (read-value (add1 i) 'str-end buffer)]
          [(and (eq? mode 'value) (eq? type 'DQUOTE))
           (read-value (add1 i) 'dq-str buffer)]
          [(and (eq? mode 'dq-str) (eq? type 'DQUOTE))
           (read-value (add1 i) 'str-end buffer)]
          ;; end of value
          [(and (eq? mode 'value*) (eq? type 'NEWLINE))
           (values (add1 i) (value-converter-fn buffer))]
          [(and (eq? mode 'str-end) (eq? type 'NEWLINE))
           (values (add1 i) buffer)] ;; don't convert type of quoted strings
          [(and (eq? mode 'indicator-end) (eq? type 'NEWLINE))
           (values (add1 i) null)]
          [else
           (error-handler 'read-value mode i)]))

      (: read-root : Natural -> Value-Type)
      (define (read-root i)
        (cond
          [(eq? (token-type (vector-ref v i)) 'NEWLINE)
           (read-root (add1 i))]
          [(eq? (token-type (vector-ref v (add1 i))) 'LI)
           (define-values (i* value) (read-list i))
           value]
          [(eq? (token-type (vector-ref v (add1 i))) 'COLON)
           (define-values (i* value) (read-hash i))
           value]
          [else
           (define-values (i* value) (read-value i))
           value]))

      (read-root 0))))

(create-tokens->yaml tokens->yaml/string Yaml-Hash-String Yaml-List-String Symbol Yaml-Value-String "" hasheq values #t)
(create-tokens->yaml tokens->yaml Yaml-Hash Yaml-List Yaml-Key Yaml-Value 'null hash read-typed-value #f)

(: port->yaml : Input-Port -> Yaml-Value)
(define (port->yaml in)
  (tokens->yaml (list->vector (port->tokens in))))

(: port->yaml/string : Input-Port -> Yaml-Value)
(define (port->yaml/string in)
  (tokens->yaml/string (list->vector (port->tokens in))))

(: file->yaml : Path-String -> Yaml-Value)
(define (file->yaml file-name)
  (tokens->yaml (list->vector (file->tokens file-name))))

(: file->yaml/string : Path-String -> Yaml-Value-String)
(define (file->yaml/string file-name)
  (tokens->yaml/string (list->vector (file->tokens file-name))))

(module+ test
  (require racket/pretty
           profile)
  (yaml-trace? #f)
  (define v (time (file->tokens "test/explicit-key.yaml" #;(build-path "/var/home/cadence/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/Quaver/Songs/" "14859 - 863" "108618.qua"))))
  (define y (time (tokens->yaml (list->vector v))))
  (pretty-print y))
