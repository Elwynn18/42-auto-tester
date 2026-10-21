# 42 project testers

Single-file Bash testers for four 42 Common Core projects:

| Script | Project | Run it from |
| --- | --- | --- |
| `test_libft.sh` | libft | your `Libft` folder |
| `test_gnl.sh` | get_next_line | your `get_next_line` folder |
| `test_ft_printf.sh` | ft_printf | your `ft_printf` folder |
| `test_push_swap.sh` | push_swap | your `push_swap` folder |

Each tester compiles your code, runs it in separate programs (a crash in one test does not stop the others), and prints a short report: what passed, what failed, and why.

> **Disclaimer:** these testers are only a helper. They can miss bugs or be wrong, and a full OK does not mean your project will pass. They will never replace a peer-to-peer evaluation: understand your code and be ready to explain it.

## Requirements

- **Linux or WSL** with `cc`, `make`, `ar`, `nm` and the usual shell tools (`sudo apt install build-essential` on Ubuntu).
- **Windows:** run the script from Git Bash. If `cc` is not found, it relaunches itself inside WSL.
- **Optional:** AddressSanitizer is used when your compiler supports it, to catch crashes, buffer overflows and memory leaks. Without it, the tests still run, but memory errors are not detected.
- **Optional:** `norminette`. If it is not installed, the Norm check is skipped.

## Quick start

Put the scripts next to your project folders, then run them from inside the project:

```
piscine/
├── Libft/
├── get_next_line/
├── test_libft.sh
└── test_gnl.sh
```

```sh
cd Libft
bash ../test_libft.sh
```

Any path to the script works (`bash ~/testers/test_libft.sh`). The tester works on a copy in `/tmp`, so it never modifies your files.

**Do not put these scripts in your repository.**

## The testers

### libft — `test_libft.sh`

```sh
bash ../test_libft.sh               # test everything
bash ../test_libft.sh split itoa    # test only these functions (with or without "ft_")
```

- **Makefile:** `make`, content of `libft.a`, relink, `clean`, `fclean`, `re`, `-Wall -Wextra -Werror`.
- **Submission:** README first line, files that are not in the subject, norminette.
- **Parts 1, 2 and 3:** each function is compiled and tested on its own, so one broken file does not block the others. For each function:
  - compiles with `-Wall -Wextra -Werror`;
  - prototype in `libft.h` matches the subject;
  - no forbidden external function, no global variable, no non-static helper;
  - results compared with the real libc function, including edge cases;
  - `malloc` failures simulated, to check NULL returns and leaks.

When you pass function names, only those functions are tested (the Makefile and Submission sections are skipped).

`ft_lstsize` may return `int` (older subjects) or `unsigned int` (recent subjects): both are accepted.

### get_next_line — `test_gnl.sh`

```sh
bash ../test_gnl.sh              # test everything
bash ../test_gnl.sh 1 42         # only these BUFFER_SIZE values
```

- **Submission:** required files only, README, prototype, no libft, compiles with `-Wall -Wextra -Werror` both with and without `-D BUFFER_SIZE`, only `read`, `malloc` and `free` used, no global variable, norminette.
- **Mandatory part:** run with `BUFFER_SIZE` = 1, 2, 3, 5, 10, 42, 100, 1000, 9999 and 10000000. It tests:
  - files (empty, no final newline, very long lines, lines around `BUFFER_SIZE`);
  - stdin, pipes, and a pipe that is still open;
  - invalid fds, `read()` errors and `malloc()` failures;
  - memory leaks.
- **Bonus:** a single static variable, and several fds read in turn (including stdin).

When you pass BUFFER_SIZE values, the Submission section is skipped.

### ft_printf — `test_ft_printf.sh`

```sh
bash ../test_ft_printf.sh             # test everything
bash ../test_ft_printf.sh d x p       # only these conversions
bash ../test_ft_printf.sh bonus       # only the bonus
```

Groups you can pass: `c s p d i u x X % mix`, `mandatory`, `bonus`, `width - 0 . '#' + ' ' combo` (or by name: `minus zero precision hash plus space`).

- **Makefile:** `make`, `libftprintf.a`, relink, `clean`, `fclean`, `re`, `bonus`, required rules, flags, `cc`, no `libtool`.
- **Submission:** README, prototype in `ft_printf.h`, only `malloc`, `free` and `write` used, no global variable, norminette.
- **Mandatory part and bonus:** every conversion and flag is compared with the real `printf`, both the output **and** the return value.

Your library is built with your own Makefile. If `make` fails, the tester compiles your sources itself so the tests can still run.

### push_swap — `test_push_swap.sh`

```sh
bash ../test_push_swap.sh               # test everything
bash ../test_push_swap.sh sort perf     # only these parts
```

Parts: `makefile submission errors sort perf bench bonus`.

The output of `push_swap` is checked by a checker built into the script, so `checker_linux` is not needed.

- **makefile:** `make`, relink, `clean`, `fclean`, `re`, `bonus`, rules, flags.
- **submission:** README (with both logins), allowed functions, no global variable, norminette.
- **errors:** non-integers, int overflow, duplicates, no argument.
- **sort:** default mode and `--simple`, `--medium`, `--complex`, `--adaptive`. Every permutation of 3 to 5 numbers, plus random, sorted, reverse and nearly sorted inputs up to 500 numbers.
- **perf:** number of operations for 3, 5, 100 and 500 numbers.
- **bench:** the `--bench` report on stderr (disorder, operation counts, strategy).
- **bonus:** your `checker` (OK / KO / Error, invalid operations), also run on the output of your own `push_swap`.

When a large input fails, its arguments are saved to `/tmp/push_swap_ko_N.txt`, and the report shows how to replay it.

## Reading the report

```
== Part 1 ==
  ft_strlen          OK (5 tests)
  ft_strlcat         KO
      ✗ ft_strlcat(dst = "abc", "hello", 0) → returns 0, dst "abc"; expected 5, dst "abc"
      ✗ memory error (global-buffer-overflow) in ft_strlcat.c:28 (ft_strlcat)
  ft_lstsize         -- not done

Result: 31 OK, 9 KO, 8 not done
```

- **OK:** every test of this line passed.
- **KO:** at least one test failed. The `✗` lines show the failing call, what you returned, what was expected, and where a crash or leak happened in your code (`file.c:line`).
- **`--`:** skipped (function not written, tool not installed, …).
- **`!!`** (push_swap only): a warning to check by hand.

The exit status is `0` when there is no KO, `1` otherwise.

## Subjects

The tests follow these subject versions (the PDFs are kept locally and ignored by git):

| Project | Subject version |
| --- | --- |
| libft | 19.3 |
| get_next_line | 14.3 |
| ft_printf | 12.1 |
| push_swap | 1.2 |

If your subject is a different version and a check disagrees with it, trust your subject, and report the difference so the tester can be fixed.
