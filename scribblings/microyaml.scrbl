#lang scribble/manual

@(require (for-label typed/racket/base microyaml (only-in racket/contract/base any/c)))
@(define-syntax-rule (deftype args ...)
  @defidform[#:kind "type" args ...])

@title{microyaml}

@author[(author+email "Cadence Ember" "cadence@disroot.org" #:obfuscate? #t)]

@defmodule[microyaml]




@section{Introduction}

This library is a much faster, non-compliant YAML parser for Racket and Typed Racket. It is non-compliant because some features are not supported.



@subsection{Supported features}

@itemlist[
@item{Inline values (strings, numbers, booleans)}
@item{Multi-line sequences}
@item{Multi-line mappings}
@item{Explicit mappings}
@item{Nesting}
@item{Comments}
@item{UTF-8}
]



@subsection{Unsupported features}

@itemlist[
@item{List marker immediately followed by indentation}
@item{Inline sequences (square brackets notation)}
@item{Inline mappings (curly braces notation)}
@item{Multi-line strings (whether arrow, pipe, implicit, or quoted notation)}
@item{Document markers (triple dash/triple dot notation)}
@item{Tags (exclamation mark notation)}
@item{Anchor nodes (ampersand notation)}
@item{Alias nodes (asterisk notation)}
@item{Directives (percent notation)}
@item{Escape sequences (backslash notation)}
@item{Serialisation}
]



@subsection{Performance}

Benchmark file: `femboy_music_FRAGILE.yaml' (105k lines; 2.9 MB) (@hyperlink["https://quavergame.com/mapset/map/127801" "source"])

@codeblock0{
| Language   | Program             |    Speed-down = Time |
|------------|---------------------|----------------------|
| JavaScript | js-yaml             |          1x = 180 ms |
| Racket     | microyaml (strings) |          2x = 370 ms |
| Racket     | microyaml (types)   |          3x = 481 ms |
| .NET       | YamlDotNet          |          6x = 1.17 s |
| Python     | yaml                |         35x = 6.40 s |
| Racket     | yaml                | 23,500x = 1h 10m 33s |
}

Benchmark file: `saltern.yaml' (38k lines; 719 kB) (@hyperlink["https://github.com/space-wizards/space-station-14/blob/8f1a74dcd1b8973a730ef6aeebe1f9f427886843/Resources/Maps/saltern.yml" "source"], lightly edited)

@codeblock0{
| Language   | Program             | Speed-down = Time |
|------------|---------------------|-------------------|
| Racket     | microyaml (types)   |       1x = 209 ms |
| .NET       | YamlDotNet          |       4x = 795 ms |
| Racket     | yaml                |   2,124x = 7m 15s |
| Racket     | microyaml (strings) | in strings mode, found explicit hash key [...] which is not a string |
| JavaScript | js-yaml             | YAMLException: duplicated mapping key at 349:8 [...]                 |
| Python     | yaml                | ConstructorError: while constructing a mapping, found unhashable key |
}



@section{Provides}

microyaml allows data to be parsed in @tech{strings mode} or @tech{typed mode}. Each mode has corresponding functions to parse data in that mode.

This only refers to how data is parsed, it doesn't refer to your Racket language. (Each of the modes can be used in both Typed Racket and standard Racket.) The mode you should use depends on your use case. For example, if you want numbers to be parsed as numbers, you need to use typed mode.



@subsection{Typed mode}

@deftogether[(
@defproc[(port->yaml [in input-port?])
         yaml-value?]
@defproc[(file->yaml [file path-string?])
         yaml-value?]
)]{
Reads a port or file and parses it to a YAML document in @tech{typed mode}.
}

In @deftech{typed mode}, which is most accurate to YAML (but not spec-compliant with it), YAML values are determined by:



@defproc[(yaml-value? [v any/c])
         boolean?]{

Returns @racket[#t] only if @racket[v] is one of the following:

@itemlist[
@item{Scalar: a @racket[string?], @racket[number?], @racket[boolean?], or @racket['null]}
@item{Hash: an immutable @racket[hash?] where each key is a @racket[yaml-key?] and each value is a @racket[yaml-value?]}
@item{Sequence: an immutable @racket[list?] of @racket[yaml-value?]}
]
}

@defproc[(yaml-key? [v any/c])
         boolean?]{
Only relevant for hash keys in @tech{typed mode}. It is similar to @racket[yaml-value?], except that @racket[string?] is not allowed and @racket[symbol?] is.
}



@deftogether[(@deftype[Yaml-Value]
              @deftype[Yaml-Key]
              @deftype[Yaml-Hash]
              @deftype[Yaml-List])]{
Typed Racket definitions for @tech{typed mode} pieces of YAML.
}



@subsection{Strings mode}

@deftogether[(
@defproc[(port->yaml/string [in input-port?])
         yaml-value-string?]
@defproc[(file->yaml/string [file path-string?])
         yaml-value-string?]
)]{
Reads a port or file and parses it to a YAML document in @tech{strings mode}.
}

In @deftech{strings mode}, which is closer to @hyperlink["https://hitchdev.com/strictyaml/" "StrictYAML"] (but not spec-compliant with it), YAML values are determined by:



@defproc[(yaml-value-string? [v any/c])
         boolean?]{

Returns @racket[#t] only if @racket[v] is one of the following:

@itemlist[
@item{Scalar: just a @racket[string?]}
@item{Hash: an immutable @racket[hasheq?] where each key is a @racket[symbol?] and each value is a @racket[yaml-value-string?]}
@item{Sequence: an immutable @racket[list?] of @racket[yaml-value-string?]}
]

Since hash keys must always be @racket[symbol?] in @tech{strings mode}, hash keys defined as non-scalars using question mark syntax are not supported, and will produce an error.
}



@deftogether[(@deftype[Yaml-Value-String]
              @deftype[Yaml-Hash-String]
              @deftype[Yaml-List-String])]{
Typed Racket definitions for @tech{strings mode} pieces of YAML.
}



@section{Examples}

@(define example-yaml #<<END
message: hello world
decimal: 123.4
rational: 7/8
blank:
nested:
  hash:
    key: value
  list:
    - 5
    - 6
    - - 7.1
      - 7.2

END
)

@(require racket/string racket/sandbox scribble/example)
@(define the-top-eval (make-base-eval))
@(the-top-eval `(begin (require (except-in racket/base #%module-begin) microyaml) (define example-yaml ,example-yaml)))
@(define-syntax-rule (ex . args)
   (examples #:eval the-top-eval . args))

Example YAML file:

@codeblock0[(string-trim example-yaml)]

@ex[#:label "Typed mode:"
(define typed-output (port->yaml (open-input-string example-yaml)))
typed-output
(yaml-value? typed-output)
(yaml-value-string? typed-output)
]

@ex[#:label "Strings mode:"
(define string-output (port->yaml/string (open-input-string example-yaml)))
string-output
(yaml-value? string-output)
(yaml-value-string? string-output)
]
