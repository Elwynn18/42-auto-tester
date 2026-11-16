# 42 project testers

Single-file Bash testers for 42 Common Core projects and the Python modules:

| Script | Project | Run it from |
| --- | --- | --- |
| `test_libft.sh` | libft | your `Libft` folder |
| `test_gnl.sh` | get_next_line | your `get_next_line` folder |
| `test_ft_printf.sh` | ft_printf | your `ft_printf` folder |
| `test_push_swap.sh` | push_swap | your `push_swap` folder |
| `test_python_00.sh` … `test_python_10.sh` | Python Modules 0 to 10 | your module folder |
| `test_python_05bis.sh`, `test_python_06bis.sh` | Python Modules 5bis and 6bis | your module folder |

Each tester compiles or imports your code, runs it in separate processes (a crash or an infinite loop in one test does not stop the others), and prints a short report: what passed, what failed, and why.

> **Disclaimer:** these testers are only a helper. They can miss bugs or be wrong, and a full OK does not mean your project will pass. They will never replace a peer-to-peer evaluation: understand your code and be ready to explain it.

## Requirements

- **Linux or WSL** with `cc`, `make`, `ar`, `nm` and the usual shell tools (`sudo apt install build-essential` on Ubuntu).
- **Windows:** run the script from Git Bash. If `cc` is not found, it relaunches itself inside WSL.
- **Optional:** AddressSanitizer is used when your compiler supports it, to catch crashes, buffer overflows and memory leaks. Without it, the tests still run, but memory errors are not detected.
- **Optional:** `norminette`. If it is not installed, the Norm check is skipped.
- **Python testers:** `python3` 3.10 or later. `flake8` and `mypy` are optional: their checks are skipped if they are not installed (`pip install flake8 mypy`). For the modules that use packages (pydantic, pandas, numpy, matplotlib, python-dotenv), activate your venv before running the tester: it uses the `python3` of your `PATH`, and skips the tests that need a package it cannot import. The testers never install anything and never use the network.

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

- **Submission:** required files only, no Makefile (the subject says "Makefile: No"), README, prototype, no libft, compiles with `-Wall -Wextra -Werror` both with and without `-D BUFFER_SIZE`, only `read`, `malloc` and `free` used, no global variable, norminette.
- **Mandatory part:** run with `BUFFER_SIZE` = 1, 2, 3, 5, 10, 42, 100, 1000, 9999 and 10000000. It tests:
  - files (empty, no final newline, very long lines, lines around `BUFFER_SIZE`, 1000 empty lines);
  - stdin, pipes, and a pipe that is still open;
  - invalid fds, a file read through fd 1023, and `read()` errors;
  - `malloc()` failures: each allocation of a call fails in turn (1st line, 2nd line, last line, call after the last line);
  - short reads: `read()` returns fewer bytes than asked, which is allowed (pipes, terminals);
  - every `read()` call must ask for exactly `BUFFER_SIZE` bytes (KO otherwise, even for `read(fd, NULL, 0)`);
  - reading only what is needed: once a `\n` is found, `get_next_line` must stop calling `read()` (the subject forbids reading the whole file first);
  - memory leaks, and a warning when blocks are still allocated after `get_next_line` returned NULL (valgrind's "still reachable").
- **`BUFFER_SIZE=0` and `BUFFER_SIZE=-1`:** must compile and return NULL, without crashing or looping.
- **Bonus:** a single static variable, several fds read in turn (including stdin), 200 fds open at the same time, and a `read()` error on one fd that must not change the lines of the other fds.

When you pass BUFFER_SIZE values, the Submission section and the `BUFFER_SIZE` <= 0 tests are skipped.

### ft_printf — `test_ft_printf.sh`

```sh
bash ../test_ft_printf.sh             # test everything
bash ../test_ft_printf.sh d x p       # only these conversions
bash ../test_ft_printf.sh bonus       # only the bonus
```

Groups you can pass: `c s p d i u x X % mix fuzz robust`, `mandatory`, `bonus`, `width - 0 . '#' + ' ' combo bfuzz` (or by name: `minus zero precision hash plus space`).

- **Makefile:** `make`, `libftprintf.a`, relink, `clean`, `fclean`, `re`, `bonus`, required rules, flags, `cc`, no `libtool`.
- **Submission:** README, prototype in `ft_printf.h`, only `malloc`, `free` and `write` used, no global variable, norminette.
- **Mandatory part and bonus:** every conversion and flag is compared with the real `printf`, both the output **and** the return value, including:
  - huge widths and precisions (`%50000c`, `%.5000u`), to catch fixed-size buffers;
  - flags that must not carry over to the next conversion (`%-5d%d`);
  - 27 arguments in one call, a 20000-character format, every byte from 1 to 255;
  - nothing kept in a buffer between two calls.
- **Random formats (`fuzz`, `bfuzz`):** 3000 random formats with the mandatory conversions, and 8000 with random flags, width and precision (only combinations that `printf` defines). Each failure shows the exact call, so you can replay it.
- **Robustness (`robust`):**
  - formats that are undefined behaviour (`"abc%"`, `"%-5"`, `"%k"`, …): the output is not checked, but `ft_printf` must not crash, loop, or read past the end of the format;
  - each `malloc` of a call fails in turn: no crash, no leak;
  - `write()` fails (stdout closed, `/dev/full`) and `ft_printf(NULL)`: no crash or infinite loop.

  When `write()` or `malloc()` fails, `printf` returns -1. If your `ft_printf` returns something else, or crashes on `ft_printf(NULL)`, you get a warning (`!!`), not a KO: the subject does not require it.

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
- **errors:** non-integers, int overflow (also values that wrap around in 32 or 64 bits), duplicates (`0 -0`, `42 042`, …), no argument, and an error hidden at the end of 500 numbers.
- **sort:** default mode and `--simple`, `--medium`, `--complex`, `--adaptive`. Every permutation of 3 to 5 numbers (and of 6 numbers in default mode), plus random, sorted, reverse, nearly sorted, rotated and almost sorted inputs, sizes from 1 to 1000 (7, 8, 11, 99, 101, 255, 256, 501, …), and values over the whole int range with `-2147483648` and `2147483647` in the same input.
- **perf:** number of operations for 3, 5, 100 and 500 numbers.
- **bench:** the `--bench` report on stderr (disorder, operation counts, strategy).
- **bonus:** your `checker` (OK / KO / Error, invalid operations), operations on empty or one-element stacks (they must do nothing), 200000 operations on stdin, and the output of your own `push_swap`.

When a large input fails, its arguments are saved to `/tmp/push_swap_ko_N.txt`, and the report shows how to replay it.

## The Python testers

```sh
cd python_module_03            # the folder that contains ex0/, ex1/, ...
bash ../test_python_03.sh      # test everything
bash ../test_python_03.sh 2 ex5   # only these exercises
```

Common to every Python tester:

- **Each test runs in its own `python3` process** with a 10 s timeout. After an infinite loop, the other tests of the same line are skipped.
- **Every file:** exists and parses, `flake8`, `mypy` when the subject asks for type hints, a type hint on every parameter and return when they are required, and only the authorized functions and imports. The lists come from the "Authorized" line of each exercise and are applied strictly. Exception classes are always accepted.
- **Structure:** code outside functions, and `if __name__ == "__main__":` blocks, are checked against what the subject asks: forbidden in Module 0, required in some later exercises.
- **Behaviour:** every example of the subject is replayed, with many edge cases on top: empty input, boundaries, large values, unicode, invalid input that must be handled, and exceptions that must be raised or caught.
- **KO vs `!!`:** a KO is given only for what the subject requires: names, values, behaviour, exceptions, and texts it imposes. When the subject only shows an *example* output whose wording is free, the essential content is checked (numbers, names, key words), and a different wording only gives a `!!` warning.
- **Submission:** files that are not requested and `__pycache__` / `.mypy_cache` folders give a warning.
- **Random output** is checked with rules that always hold, not with exact values.

### Module 0 (Growing Code) — `test_python_00.sh`

- **Every exercise:** only the requested function (no code outside it, no `if __name__` block, no extra function), only the authorized functions (e.g. `str()` is not in the ex2 list).
- **ex1 to ex5:** the prompts (`Enter length: `, …) and the output are compared exactly, with many inputs. The limits are tested: 60 / 61 days, 2 / 3 days.
- **ex6:** the iterative version must use a loop, and the recursive version must call itself and use no loop (`for`, `while` or comprehension). Both are tested from 0 to 500 days.
- **ex7:** the signature `(seed_type: str, quantity: int, unit: str) -> None`, mypy, every unit, and unknown units (`Unknown unit type`). If your capital letter is not the same as with `str.capitalize()` on words like `"cherry tomato"`, you get a warning.

### Module 1 (Code Cultivation) — `test_python_01.sh`

- **ex0:** main block required, and importing the file prints nothing.
- **ex1 to ex3:** the classes are imported and tested directly: `show()`, `grow()` and `age()`, independent instances, and the constructor on many values.
- **ex4:** getters and setters. Negative values are rejected and leave the value unchanged. Values are stored in protected attributes (`_height`, not public, not `__height`).
- **ex5:** `Flower`, `Tree` and `Vegetable` inherit from `Plant` and use `super()`; `bloom()`, `produce_shade()` and the nutritional value are tested.
- **ex6:** the static method and the class method, the nested statistics class with protected counters (checked after sequences of calls), and `Seed` inheriting from `Flower`.
- **Free names:** attribute names and the names of the ex6 methods are free. The tester finds them by their values and behaviour.

### Module 2 (Garden Guardian) — `test_python_02.sh`

- **ex0 / ex1:** `input_temperature()` must return an `int` for valid strings, raise for invalid ones, and accept 0 to 40 in ex1 (limits included). The test function must survive every error.
- **ex2:** `garden_operations(0..3)` must raise `ValueError`, `ZeroDivisionError`, `FileNotFoundError` and `TypeError`; the other values must not raise.
- **ex3:** the custom exception hierarchy, checked with `issubclass` and real `except` clauses, and the default and given messages.
- **ex4:**
  - `water_plant()` succeeds or raises `PlantError`;
  - there is a `try` / `except` / `finally`;
  - the system is closed after an error, even when an unexpected `RuntimeError` is raised.

### Module 3 (Data Quest) — `test_python_03.sh`

- **ex0, ex1, ex4:** the programs are run with many `sys.argv` combinations: none, one, many, empty, invalid, duplicates, huge numbers.
- **Checked values:**
  - ex1: count, total, average, max and min;
  - ex4: the inventory dict, the percentages, the most and least abundant items.
- **ex2:** `get_player_pos()` is tested with retries and invalid input, and must return a tuple. Both distances are checked.
- **ex3:** sets over 300 calls and 10 random seeds: union, intersection, differences.
- **ex5:** `yield` is required, `gen_event()` must be endless (5000 `next()` calls), and `consume_event()` must empty the list.
- **ex6:** at least 2 list comprehensions and 2 dict comprehensions, with values checked over 8 seeds.
- **Endless programs:** a program that keeps reading after the end of input, or prints endlessly, is stopped with a clear message.

### Module 4 (Data Archivist) — `test_python_04.sh`

- **ex0 to ex2:** the programs are run on test files created in `/tmp`:
  - the subject example, empty, unicode, no final newline and 1.3 MB files;
  - missing files, `chmod 000` files (skipped as root), directories and binary files.
- **Checked behaviour:**
  - the content is shown exactly, errors give no crash and show the `[Errno N]` message;
  - every opened file is closed;
  - no `with` is allowed before ex3.
- **ex1 / ex2:** a `#` at the end of each line, on screen and in the saved file. Saving is tested to new, existing, unicode, sub-folder, missing and read-only paths. In ex2, errors must go to **stderr**, never stdout.
- **ex3:** `secure_archive()` reads and writes exactly, handles errors, closes its files and uses `with open(...)`.

### Modules 5, 7 and 6bis (Code Nexus, DataDeck) — `test_python_05.sh`, `test_python_07.sh`, `test_python_06bis.sh`

Module 6bis is Module 5 (ex0–ex2, files at the root) plus Module 7 (`ex3/` and `ex4/` packages), so the same tests are used. Run `test_python_07.sh` and `test_python_06bis.sh` from your repository root.

- **Abstract classes:**
  - ABCs cannot be instantiated;
  - every abstract method is overridden, with signatures compared with the subject;
  - mypy, with the `ingest()` `[arg-type]` error that the subject asks for accepted.
- **Data processors:**
  - `validate()` on about 40 inputs;
  - `ingest()` raises on invalid data and stores nothing;
  - `output()` gives `(rank, str)` tuples, oldest first, with the rank continuing across calls;
  - instances are independent.
- **Stream and pipeline:**
  - routing goes through each processor's `validate()` / `ingest()`, and statistics are checked;
  - streams of 3000 elements;
  - `ExportPlugin` is a Protocol, the CSV output is checked, and the JSON output is checked with `json.loads`.
- **Creatures:**
  - packages expose only the factories;
  - `describe()` / `attack()` return strings;
  - `transform()` / `revert()` keep their state per instance;
  - capabilities are not `Creature` classes.
- **Strategies and battle:**
  - `is_valid()` on every creature, `act()` messages in order, and an exception on invalid pairs;
  - every opponent fights every other once in `battle()`;
  - in 6bis, strategies must check the capability with `isinstance`, never the concrete family.

### Modules 6, 8 and 5bis (The Codex, The Matrix) — `test_python_06.sh`, `test_python_08.sh`, `test_python_05bis.sh`

Module 5bis is Module 8 (venv, packages, `.env`) plus Module 6 (the `alchemy` package), so the same tests are used. Run the testers from the root of the module.

- **Packages (6, 5bis):**
  - what `import alchemy` exposes, and what it must not expose (`create_earth`);
  - the import style of each script (absolute, relative, `from … import`), checked on the code;
  - the potions and `lead_to_gold()` must really call the element functions (they are replaced by fakes to check);
  - the light grimoire works whatever module is imported first, and the dark pair must fail with a circular `ImportError`;
  - `sys.path` is never modified, and `eval()` / `exec()` are not used.
- **`construct.py` (8, 5bis):** run outside any venv, then inside venvs created offline in `/tmp` (`python3 -m venv --without-pip`), activated or not. The venv name must not be written in the code.
- **`loading.py` (8, 5bis):**
  - `requirements.txt` and `pyproject.toml` are parsed, and every imported package must be declared;
  - without the packages, the program must print a clear message, not a traceback;
  - with the packages, the versions are shown.
- **`oracle.py` (8, 5bis):**
  - `.env.example` lists the variables, and `.gitignore` ignores `.env` (checked with `git check-ignore`);
  - no secret is written in the code;
  - runs with no configuration, partial configuration, a `.env` file, environment variables that win over `.env`, and dev vs production.
- **Committed files:** a venv or a `.env` file committed in git is a KO.

### Module 9 (Cosmic Data) — `test_python_09.sh`

Pydantic 2 must be importable by the `python3` on your `PATH`: activate your venv first. If it is missing, the runtime tests are skipped, not failed.

- **No Pydantic v1 API:** `@validator`, `@root_validator` and `Field(regex=...)` are KO. `@model_validator(mode='after')` is required in ex1 and ex2.
- **Models:**
  - class names, field names and enum values;
  - every length and range limit, tested just inside and just outside;
  - defaults, optional fields (left out or `None`), required fields and wrong types.
- **ex1 rules:** the ID starts with "AC"; physical contact must be verified; telepathy needs at least 3 witnesses; a signal above 7.0 needs a message.
- **ex2 rules:**
  - the ID starts with "M", and at least one commander or captain is required;
  - for missions longer than 365 days, 50% of the crew needs 5 or more years of experience;
  - every crew member is active;
  - nested crew: an invalid member makes the mission fail.

### Module 10 (FuncMage) — `test_python_10.sh`

- **ex0:** lambdas with `sorted` / `filter` / `map` / `max` / `min`, with no nested `def`. Lists must not be modified, and the subject examples, empty lists and ties are tested.
- **ex1:** each function returns a function, spells are not cast when the function is created, and spells are cast once, in order.
- **ex2:** real closures (`__closure__`), and counters and accumulators that are independent and keep their state. `global` is KO.
- **ex3:** `reduce`, `partial`, `lru_cache` (`cache_info()` shows a hit, fib up to 300), `singledispatch`, and `operator`.
- **ex4:** `functools.wraps` (`__name__`, `__doc__`, `__wrapped__`), the exact timing output, the `power_validator` limits, the number of calls of `retry_spell`, and `@staticmethod`.

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
- **`!!`** (not for libft): a warning to check by hand. It is not counted as a KO.

The exit status is `0` when there is no KO, `1` otherwise.

## Subjects

The tests follow these subject versions (the PDFs are kept locally and ignored by git):

| Project | Subject version |
| --- | --- |
| libft | 19.3 |
| get_next_line | 14.3 |
| ft_printf | 12.1 |
| push_swap | 1.2 |
| Python Module 0 — Growing Code | 3.0 |
| Python Module 1 — Code Cultivation | 3.2 |
| Python Module 2 — Garden Guardian | 3.0 |
| Python Module 3 — Data Quest | 3.1 |
| Python Module 4 — Data Archivist | 3.0 |
| Python Module 5 — Code Nexus | 3.1 |
| Python Module 5bis — The Codex | 1.0 |
| Python Module 6 — The Codex | 2.0 |
| Python Module 6bis — Code Nexus | 1.0 |
| Python Module 7 — DataDeck | 3.0 |
| Python Module 8 — The Matrix | 3.2 |
| Python Module 9 — Cosmic Data | 3.0 |
| Python Module 10 — FuncMage | 3.2 |

If your subject is a different version and a check disagrees with it, trust your subject, and report the difference so the tester can be fixed.
