#lang info
(define collection "microyaml")
(define version "1.0")
(define deps '("base" "typed-racket-lib" "rackunit-lib"))
(define build-deps '("racket-doc" "scribble-lib" "typed-racket-doc" "sandbox-lib"))
(define scribblings '(("scribblings/microyaml.scrbl")))
(define license 'GPL-3.0-or-later)
