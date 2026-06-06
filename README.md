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
awk '/makeBox__anon/{found=1} found{print; if(/^$/) found=0}' /tmp/dwarf-bug-repro.ll
```

Yields something like:

```text
...
!104934 = distinct !DISubprogram(name: "makeBox__anon_43217", linkageName: "repro.makeBox__anon_43217", scope: !104913, file: !104913, line: 9, type: !104935, scopeLine: 43, flags: DIFlagStaticMember, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !32)
!104935 = !DISubroutineType(types: !104936)
!104936 = !{!59, !104937, !875, !104925}
!104937 = !DIDerivedType(tag: DW_TAG_pointer_type, name: "*repro.Boxed(repro.Plain)", scope: !32, baseType: !104922, size: 64, align: 64)
!104938 = !DILocation(line: 43, column: 37, scope: !104934)
!104939 = !DILocalVariable(name: "value", arg: 1, scope: !104934, file: !104913, line: 43, type: !104925)
!104940 = !DILocation(line: 10, column: 5, scope: !104934)
```

 Notice:

```text
!104938 = !DILocation(line: 43, column: 37, scope: !104934)
!104939 = !DILocalVariable(name: "value", arg: 1, scope: !104934, file: !104913, line: 43, type: !104925)
```

There is no line#43.

Changing the code to `value2` instead of `value` does not appear to impact line #, column #, or scope.

## Further Evidence from llvm-dwarfdump

```bash
llvm-dwarfdump --debug-line /tmp/dwarf-bug-repro | grep -B 1 -A 4 'repro.zig'
```

```text
file_names[ 93]:
           name: "repro.zig"
      dir_index: 0
       mod_time: 0x00000000
         length: 0x00000000
```

Take `93` (should be the same on a different computer) and add it to the command:

```bash
llvm-dwarfdump --debug-line /tmp/dwarf-bug-repro | grep -E '^0x[0-9a-f]+\s+[0-9]+\s+[0-9]+\s+93'
```

This is the format:

```text
Address            Line   Column File   ISA Discriminator OpIndex Flags
------------------ ------ ------ ------ --- ------------- ------- -------------
```

Output:

```text
0x0000000001192430     18      0     93   0             0       0  is_stmt
0x000000000119243f     19      5     93   0             0       0  is_stmt prologue_end
0x0000000001192457     20     26     93   0             0       0  is_stmt
0x0000000001192470     21     38     93   0             0       0  is_stmt
0x000000000119247c     21     27     93   0             0       0 
0x000000000119248e      0     27     93   0             0       0 
0x0000000001192492     21      5     93   0             0       0 
0x0000000001192496     21      5     93   0             0       0 
0x000000000119249a     21      5     93   0             0       0 
0x000000000119249c     21      5     93   0             0       0  epilogue_begin
0x00000000011924a2      0      5     93   0             0       0 
0x00000000011924a6     21      5     93   0             0       0  epilogue_begin
0x00000000011924ae      0      5     93   0             0       0 
0x00000000011924b2     21      5     93   0             0       0 
0x00000000011924c0     43      0     93   0             0       0  is_stmt
0x00000000011924c8     43     37     93   0             0       0  is_stmt prologue_end
0x00000000011924cc     10      5     93   0             0       0  is_stmt
0x00000000011924cf     10      5     93   0             0       0  epilogue_begin
0x00000000011924d5     10      5     93   0             0       0  end_sequence
0x00000000011a86a0      9      0     93   0             0       0  is_stmt
0x00000000011a8723     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a874a     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a876d     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a878c     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a885d     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a8860      0      5     93   0             0       0 
0x00000000011a88c4     10      5     93   0             0       0  is_stmt epilogue_begin
0x00000000011a88c7     10      5     93   0             0       0  is_stmt end_sequence
```

Notice these two #43 lines:

```
0x00000000011924c0     43      0     93   0             0       0  is_stmt
0x00000000011924c8     43     37     93   0             0       0  is_stmt prologue_end
```

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
