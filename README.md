# microyaml

A much faster, non-compliant YAML parser in (Typed) Racket.

## Performance

Benchmark file: `femboy_music_FRAGILE.yaml` (105k lines; 2.9 MB) ([source](https://quavergame.com/mapset/map/127801))

| Language   | Program               |    Speed-down @ Time |
|:-----------|:----------------------|---------------------:|
| JavaScript | js-yaml               |          1x @ 180 ms |
| **Racket** | **microyaml strings** |      **2x @ 370 ms** |
| **Racket** | **microyaml types**   |      **3x @ 481 ms** |
| .NET       | YamlDotNet            |         6x @ 1177 ms |
| Python     | yaml                  |          35x @ 6.4 s |
| Racket     | yaml                  | 23,500x @ 1h 10m 33s |

Benchmark file: `saltern.yaml` (38k lines; 719 kB) ([source](https://github.com/space-wizards/space-station-14/blob/8f1a74dcd1b8973a730ef6aeebe1f9f427886843/Resources/Maps/saltern.yml) lightly edited)

| Language   | Program               |                                                    Speed-down @ Time |
|:-----------|:----------------------|---------------------------------------------------------------------:|
| **Racket** | **microyaml types**   |                                                      **1x @ 209 ms** |
| .NET       | YamlDotNet            |                                                          4x @ 795 ms |
| Racket     | yaml                  |                                                      2,124x @ 7m 15s |
| **Racket** | **microyaml strings** | in strings mode, found explicit hash key [...] which is not a string |
| JavaScript | js-yaml               |                 YAMLException: duplicated mapping key at 349:8 [...] |
| Python     | yaml                  | ConstructorError: while constructing a mapping, found unhashable key |

## Supported features

* Inline values (strings, numbers, booleans)
* Multi-line sequences
* Multi-line mappings
* Explicit mappings
* Nesting
* Comments
* UTF-8

## Unsupported features

* List marker immediately followed by indentation
* Inline sequences (square brackets notation)
* Inline mappings (curly braces notation)
* Multi-line strings (whether arrow, pipe, implicit, or quoted notation)
* Document markers (triple dash/triple dot notation)
* Tags (exclamation mark notation)
* Anchor nodes (ampersand notation)
* Alias nodes (asterisk notation)
* Directives (percent notation)
* Escape sequences (backslash notation)
* Serialisation

## Install

Install from package server: `raco pkg install microyaml`

Install from local directory: `raco pkg install && raco setup --doc-index --only microyaml`

## Usage documentation

Install first. Then: `raco doc microyaml`
