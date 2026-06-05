# Zig DWARF Line-Table Reproduction

This is a minimal reproduction for incorrect Zig 0.16.0 debug line metadata on a generic/comptime function.

The source file has 22 lines. The generated debug metadata for `makeBox__anon_*` incorrectly points some function-entry / argument-spill instructions at source line `43`, which does not exist in `repro.zig`.

## Environment

Known failing version:

```sh
zig version
# 0.16.0
```

## Minimal Reproduction

Build the test binary without stripping debug info:

```sh
zig test repro.zig -fllvm -fno-strip --test-no-exec -femit-bin=/tmp/dwarf-bug-repro
```

Find the generated specialization:

```sh
nm -n -S -C /tmp/dwarf-bug-repro | grep 'makeBox__anon'
```

Then inspect the decoded DWARF line table:

```sh
readelf --debug-dump=decodedline /tmp/dwarf-bug-repro | grep -A8 -B4 'repro.zig'
```

Expected suspicious output:

```text
repro.zig 43 0x... x
repro.zig 43 0x... x
repro.zig 10 0x... x
```

Line `10` is valid: it is the body of `makeBox`.

Line `43` is invalid: `repro.zig` only has 22 lines.

## Stronger Proof: LLVM IR Already Contains the Bad Location

Emit LLVM IR:

```sh
zig test repro.zig -fllvm -fno-strip --test-no-exec \
  -femit-llvm-ir=/tmp/dwarf-bug-repro.ll \
  -femit-bin=/tmp/dwarf-bug-repro-ir-bin
```

Inspect the generated function and debug metadata:

```sh
ruby -ne '
  if $_ =~ /^(!\d+) = distinct !DISubprogram\(name: "makeBox__anon/
    $scope = $1
    print
  elsif defined?($scope) && $_.include?("scope: #{$scope}") && $_.match?(/line: (10|43)/)
    print
  end
' /tmp/dwarf-bug-repro.ll
```

Expected suspicious output:

```text
define internal fastcc void @repro.makeBox__anon_...
!N = distinct !DISubprogram(... line: 9, scopeLine: 43, ...)
!N = !DILocation(line: 43, column: 37, ...)
!N = !DILocalVariable(name: "value", arg: 1, ... line: 43, ...)
```

This shows the bad source line is emitted by Zig into LLVM debug metadata before DWARF consumers, coverage tools, or Codecov process the binary.

## Expected Behavior

All debug line metadata for instructions in `makeBox__anon_*` should map to real source locations in `repro.zig`.

For this file, valid lines for `makeBox` are:

- line `9`: function declaration
- line `10`: return statement

The function-entry / argument-spill instructions may reasonably map to line `9`, line `10`, or no statement location, but they should not map to a non-existent line such as `43`.

## Actual Behavior

Zig 0.16.0 emits debug metadata that maps some instructions in `makeBox__anon_*` to `repro.zig:43`.

That incorrect metadata flows into the DWARF line table. Coverage tools that trust DWARF can then attribute executed machine code to unrelated or non-existent source lines.

## Non-LLVM Check

The issue is not limited to `-fllvm`. This also reproduces with the default backend:

```sh
zig test repro.zig -fno-strip --test-no-exec -femit-bin=/tmp/dwarf-bug-repro-stage2
readelf --debug-dump=decodedline /tmp/dwarf-bug-repro-stage2 2>/tmp/dwarf-bug-readelf.err | grep -A8 -B4 'repro.zig'
```

The default backend may emit noisier DWARF, but the same kind of bad `repro.zig:43` line entry appears.

## Objdump

The issue also appears in objdump:

```sh
objdump -d --line-numbers --demangle /tmp/dwarf-bug-repro | grep -A20 -B5 'makeBox__anon'                               
```

```text
~/dwarf-bug/repro.zig:43
 11924c0:       55                      push   %rbp
 11924c1:       48 89 e5                mov    %rsp,%rbp
 11924c4:       50                      push   %rax
 11924c5:       48 89 f8                mov    %rdi,%rax
 11924c8:       48 89 55 f8             mov    %rdx,-0x8(%rbp)
```

There is no line #43 `repro.zig:43`.
