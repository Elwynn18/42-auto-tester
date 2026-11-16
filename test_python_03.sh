#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_03.sh - single-file tester for Python Module 3 (Data Quest)     #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_03.sh               -> test everything              #
#      bash ../test_python_03.sh 2 ex5         -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - Programs are run with many command-line arguments / inputs; random        #
#    outputs are checked with invariants (union, intersection, ...).           #
#  - flake8 and mypy are used when they are installed.                         #
#  - Do NOT put this file in your repository.                                  #
# **************************************************************************** #

# ------------ Relaunch in WSL if there is no python3 (Git Bash on Windows) ------------ #
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys' >/dev/null 2>&1; then
	if command -v wsl.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		MSYS_NO_PATHCONV=1 exec wsl.exe --cd "$(pwd -W)" -e bash -c \
			'exec bash "$(wslpath "$0")" "$@"' "$(cygpath -m "$0")" "$@"
	fi
	echo "Error: 'python3' not found. Run this script on Linux / WSL." >&2
	exit 1
fi

if [ -t 1 ]; then
	R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; CY=$'\e[1;36m'; BD=$'\e[1m'
	D=$'\e[2m'; N=$'\e[0m'
else
	R=''; G=''; Y=''; B=''; CY=''; BD=''; D=''; N=''
fi

# ---------------------------- Banner / disclaimer --------------------------- #
# banner <title> <directory>
banner() {
	local i logo=(
		'        :::      ::::::::'
		'      :+:      :+:    :+:'
		'    +:+ +:+         +:+'
		'  +#+  +:+       +#+'
		'+#+#+#+#+#+   +#+'
		'     #+#    #+#'
		'    ###   ########.fr'
	)
	local text=('' '' "$BD$1$N" "${D}unofficial tester, single file$N" "$D$2$N" '' '')

	printf '\n'
	for i in "${!logo[@]}"; do
		if [ -n "${text[$i]}" ]; then
			printf '  %s%-25s%s    %s\n' "$CY" "${logo[$i]}" "$N" "${text[$i]}"
		else
			printf '  %s%s%s\n' "$CY" "${logo[$i]}" "$N"
		fi
	done
}

disclaimer() {
	printf '\n%s%s%s\n' "$D" '────────────────────────────────────────────────────────────────────────────' "$N"
	printf '%sDisclaimer:%s this tester is only a helper. It can miss bugs or be wrong,\n' "$Y" "$N"
	printf 'and a full OK does not mean your project will pass. It will never replace\n'
	printf 'a peer-to-peer evaluation: understand your code and be ready to explain it.\n'
}

DIR=$(pwd)
banner "Python Module 3 tester (Data Quest)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 3 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_03.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 22 ? 22 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }

# Exercises to test
EXS=(0 1 2 3 4 5 6)
declare -A WANTED=()
for a in "$@"; do
	a=${a#ex}
	case " ${EXS[*]} " in
		*" $a "*) WANTED[$a]=1 ;;
		*) echo "Unknown exercise: '$a'. Exercises: ${EXS[*]} (or ex0 ex1 ...)" >&2; exit 1 ;;
	esac
done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# ------------------------- Python helper (pt.py) ---------------------------- #
# script <file> [args]           : runs the file as "python3 <file> <args>" from its
#                                  folder (random seeded with $PT_SEED if set)
# defs <file> <python code>      : loads the functions of the file (without running
#                                  its main code) and runs a test snippet on them
# ast <file> <calls> <imports>   : forbidden calls / imports / module attributes
# hints <file>                   : parameters and returns without type hints
# feat <file>                    : comprehensions, generator functions, for loops
# (the exception, if any, goes to $PT_EXC)
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import io
import os
import random
import runpy
import sys
import traceback
import types

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))
MAX_OUT = 2000000


def short(s, n=70):
    out = ""
    for c in s:
        if c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
        elif c == '"':
            out += '\\"'
        elif ord(c) < 32:
            out += "\\x%02x" % ord(c)
        else:
            out += c
    return out if len(out) <= n else out[:n] + "…"


def summary(e):
    loc = ""
    for fr in reversed(traceback.extract_tb(e.__traceback__)):
        if os.path.realpath(fr.filename).startswith(ROOT + os.sep):
            loc = "%s:%s" % (os.path.basename(fr.filename), fr.lineno)
            break
    m = short(str(e), 90)
    s = type(e).__name__ + (": " + m if m else "")
    return s + (" (" + loc + ")" if loc else "")


def report(text):
    path = os.environ.get("PT_EXC")
    if path:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text + "\n")


class Stop(BaseException):
    """Endless output or input reading: not catchable by 'except Exception'."""


class In(io.StringIO):
    """stdin that stops a program reading again and again after its end."""
    eof = 0

    def readline(self, *a):
        line = super().readline(*a)
        if not line:
            self.eof += 1
            if self.eof > 20:
                raise Stop("keeps asking for input after the end of the input "
                           "(infinite loop on EOFError?)")
        return line


class Out(io.TextIOBase):
    """stdout with a size limit (an infinite loop of prints stops quickly)."""

    def __init__(self, real):
        self.real = real
        self.n = 0

    @property
    def encoding(self):
        return "utf-8"

    def writable(self):
        return True

    def write(self, s):
        self.n += len(s)
        if self.n > MAX_OUT:
            raise Stop("prints more than 2 MB (infinite loop?)")
        return self.real.write(s)

    def flush(self):
        self.real.flush()


def cmd_script(path, *args):
    path = os.path.abspath(path)
    os.chdir(os.path.dirname(path))
    sys.path.insert(0, os.path.dirname(path))
    sys.argv = [os.path.basename(path)] + list(args)
    if os.environ.get("PT_SEED"):
        random.seed(int(os.environ["PT_SEED"]))
    sys.stdin = In(sys.stdin.read())
    sys.stdout = Out(sys.__stdout__)
    try:
        # relative path: sys.argv[0] is "<file>.py", as in "python3 <file>.py"
        runpy.run_path(os.path.basename(path), run_name="__main__")
    except SystemExit:
        pass
    except Stop as e:
        sys.stdout.flush()
        report(str(e))
        return 7
    except BaseException as e:
        sys.stdout.flush()
        report(summary(e))
        return 3
    sys.stdout.flush()
    return 0


SAFE_CALLS = {"list", "set", "tuple", "dict", "frozenset", "range", "str",
              "int", "float", "len", "sorted"}


def safe(stmt):
    """Top-level statements kept to load the functions without the program."""
    if isinstance(stmt, (ast.Import, ast.ImportFrom, ast.FunctionDef,
                         ast.AsyncFunctionDef, ast.ClassDef)):
        return True
    if isinstance(stmt, (ast.Assign, ast.AnnAssign)):
        for n in ast.walk(stmt):
            if isinstance(n, ast.Call) and not (isinstance(n.func, ast.Name)
                                                and n.func.id in SAFE_CALLS):
                return False
        return True
    return False


def run(f, *args, stdin=""):
    """f(*args) with this stdin → (value, printed text, exception or None)."""
    old = sys.stdin, sys.stdout
    buf = io.StringIO()
    sys.stdin, sys.stdout = In(stdin), Out(buf)
    value = exc = None
    try:
        value = f(*args)
    except Stop as e:
        exc = str(e)
    except BaseException as e:
        exc = summary(e)
    finally:
        sys.stdin, sys.stdout = old
    return value, buf.getvalue(), exc


def raises(exc):
    """'raises <exception>', or the message of a stopped endless loop."""
    return exc if exc.startswith(("keeps", "prints")) else "raises " + exc


def cmd_defs(path, code):
    path = os.path.abspath(path)
    base = os.path.basename(path)
    name = os.path.splitext(base)[0]
    sys.path.insert(0, os.path.dirname(path))
    sys.argv = [base]
    # 1. normal import (the main code is not run if it is in a main guard)
    mod = types.ModuleType(name)
    mod.__file__ = path
    sys.modules[name] = mod
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    _, _, exc = run(lambda: exec(compile(src, path, "exec"), mod.__dict__))
    if exc is not None:
        # 2. the main code needs input: load only imports / defs / constants
        mod = types.ModuleType(name)
        mod.__file__ = path
        sys.modules[name] = mod
        tree = ast.parse(src, path)
        tree.body = [s for s in tree.body if safe(s)]
        code_defs = compile(tree, path, "exec")
        _, _, exc = run(lambda: exec(code_defs, mod.__dict__))
        if exc is not None:
            report("loading the functions of %s: %s" % (base, raises(exc)))
            return 5
    env = {"m": mod, "run": run, "short": short, "raises": raises}
    try:
        exec(code, env)
    except BaseException as e:
        report("the test itself fails: " + summary(e))
        return 3
    return 0


def bound_names(tree):
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef,
                          ast.ClassDef)):
            names.add(n.name)
        elif isinstance(n, ast.arg):
            names.add(n.arg)
        elif isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store):
            names.add(n.id)
        elif isinstance(n, ast.alias):
            names.add((n.asname or n.name).split(".")[0])
        elif isinstance(n, ast.ExceptHandler) and n.name:
            names.add(n.name)
    return names


def is_exception(name):
    obj = getattr(builtins, name, None)
    return isinstance(obj, type) and issubclass(obj, BaseException)


def cmd_ast(path, calls, imports):
    """imports: "sys.argv,math.sqrt,random.*" (module.attribute allowed)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src, path)
    except SyntaxError as e:
        print("SYNTAX %s %s" % (e.lineno, e.msg))
        return 0
    allowed = set(calls.split(","))
    mods = {}
    for item in filter(None, imports.split(",")):
        m, _, a = item.partition(".")
        mods.setdefault(m, set()).add(a or "*")
    mine = bound_names(tree)
    bnames = set(dir(builtins))
    aliases = {}

    def attr_ok(m, a):
        return "*" in mods[m] or a in mods[m]

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            name = n.func.id
            if (name in bnames and name not in mine and name not in allowed
                    and not is_exception(name)):
                print("CALL %s %s" % (name, n.lineno))
        if isinstance(n, ast.Import):
            for a in n.names:
                root = a.name.split(".")[0]
                if root not in mods:
                    print("IMPORT %s %s" % (a.name, n.lineno))
                else:
                    aliases[a.asname or root] = root
        if isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
            root = n.module.split(".")[0]
            if root not in mods:
                print("IMPORT %s %s" % (n.module, n.lineno))
            else:
                for a in n.names:
                    if not attr_ok(root, a.name):
                        print("ATTR %s.%s %s" % (root, a.name, n.lineno))
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) \
                and n.value.id in aliases \
                and not attr_ok(aliases[n.value.id], n.attr):
            print("ATTR %s.%s %s" % (aliases[n.value.id], n.attr, n.lineno))
    for s in tree.body:
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
            print("DEF %s %s" % (s.name, s.lineno))
    return 0


def cmd_hints(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    for n in ast.walk(tree):
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        print("FUNC %s %s" % (n.name, n.lineno))
        a = n.args
        params = a.posonlyargs + a.args + a.kwonlyargs
        params += [x for x in (a.vararg, a.kwarg) if x]
        miss = [p.arg for p in params
                if p.annotation is None and p.arg not in ("self", "cls")]
        if miss:
            print("PARAM %s %s %s" % (n.name, n.lineno, ",".join(miss)))
        if n.returns is None:
            print("RETURN %s %s" % (n.name, n.lineno))
    return 0


def own_nodes(fn):
    """Nodes of a function, without its nested functions / classes."""
    todo = list(ast.iter_child_nodes(fn))
    while todo:
        n = todo.pop()
        yield n
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef,
                              ast.ClassDef, ast.Lambda)):
            todo.extend(ast.iter_child_nodes(n))


def cmd_feat(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    tree = ast.parse(src, path)
    kinds = {ast.ListComp: "listcomp", ast.DictComp: "dictcomp",
             ast.SetComp: "setcomp", ast.GeneratorExp: "genexp"}
    count = dict.fromkeys(kinds.values(), 0)
    for n in ast.walk(tree):
        if type(n) in kinds:
            count[kinds[type(n)]] += 1
            # on several lines although it fits on one line (79 columns)
            if n.end_lineno != n.lineno \
                    and n.col_offset + len(ast.unparse(n)) <= 79:
                print("SPLIT %s %s" % (kinds[type(n)], n.lineno))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) \
                and any(isinstance(x, (ast.Yield, ast.YieldFrom))
                        for x in own_nodes(n)):
            print("GEN %s %s" % (n.name, n.lineno))
        if isinstance(n, (ast.For, ast.comprehension)) \
                and isinstance(n.iter, ast.Call) \
                and isinstance(n.iter.func, ast.Name):
            print("FORCALL %s" % n.iter.func.id)
    for k, v in count.items():
        print("COUNT %s %d" % (k, v))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"script": cmd_script, "defs": cmd_defs, "ast": cmd_ast,
              "hints": cmd_hints, "feat": cmd_feat}[cmd](*sys.argv[2:]))
EOF
PT="$TMP/pt.py"

# ----------------------- Output checkers (ck.py) ---------------------------- #
# ck.py <exercise> <output file> <stdin file> [program args]
# Prints one line per result:
#   KO <text>    : something the subject requires is wrong
#   WARN <text>  : differs from the subject's example (wording, format)
#   NOTE <text>  : extra explanation for a KO
#   STAT <text>  : data used by the tester (randomness, ...)
cat > "$TMP/ck.py" <<'EOF'
import ast
import math
import re
import sys
from collections import Counter

KOS = []


def short(s, n=70):
    out = ""
    for c in s:
        if c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
        elif c == '"':
            out += '\\"'
        elif ord(c) < 32:
            out += "\\x%02x" % ord(c)
        else:
            out += c
    return out if len(out) <= n else out[:n] + "…"


def say(kind, text):
    print(kind, text.replace("\n", " "))


def ko(text):
    KOS.append(text)
    say("KO", text)


def clip(line, col):
    """The part of a long line around the column col."""
    if col > 40 and len(line) > 70:
        return short("…" + line[col - 25:])
    return short(line)


def first_diff(exp, got):
    el, gl = exp.splitlines(), got.splitlines()
    i = 0
    while i < len(el) and i < len(gl) and el[i] == gl[i]:
        i += 1
    if not got:
        return 'prints nothing; expected "%s"' % short(exp)
    if i >= len(gl) and i >= len(el):
        return "only the line endings differ"
    if i >= len(gl):
        return 'output stops after line %d; expected next: "%s"' \
            % (i, short(el[i]))
    if i >= len(el):
        return 'extra output at line %d: "%s"' % (i + 1, short(gl[i]))
    c = 0
    while c < len(gl[i]) and c < len(el[i]) and gl[i][c] == el[i][c]:
        c += 1
    return 'line %d: "%s"; expected "%s"' % (i + 1, clip(gl[i], c),
                                             clip(el[i], c))


def compare(exp, got):
    """Exact output of the example: NOTE after a KO, WARN otherwise."""
    if exp != got:
        d = first_diff(exp, got)
        if KOS:
            say("NOTE", "first difference with the subject's format: " + d)
        else:
            say("WARN", "differs from the subject's example: " + d)


PH = {"SET": r"(\{.*\}|set\(\))", "LIST": r"\[.*\]", "DICT": r"\{.*\}",
      "TUPLE": r"\(.*\)", "NAME": r"\S+", "INT": r"\d+",
      "NUM": r"-?\d+(\.\d+)?"}


def shape(lines, templates):
    """Lines must look like the templates (SET, LIST, NAME... = any value)."""
    for i, t in enumerate(templates):
        rx = re.escape(t)
        for k, v in PH.items():
            rx = rx.replace(k, v)
        if i >= len(lines):
            m = 'output stops after line %d; expected a line like "%s"' \
                % (i, t)
        elif not re.fullmatch(rx, lines[i]):
            m = 'line %d: "%s"; expected a line like "%s"' \
                % (i + 1, short(lines[i]), t)
        else:
            continue
        if KOS:
            say("NOTE", "first difference with the subject's format: " + m)
        else:
            say("WARN", "format differs from the subject's example: " + m)
        return
    if len(lines) > len(templates):
        say("WARN", 'extra output at line %d: "%s"'
            % (len(templates) + 1, short(lines[len(templates)])))


def literal(line, kinds):
    """First Python value of these types displayed in the line (or None)."""
    starts = [i for i, c in enumerate(line) if c in "[({"]
    starts += [i for i in range(len(line)) if line.startswith("set()", i)]
    for i in sorted(starts):
        for j in range(len(line), i, -1):
            if line[j - 1] not in ")]}":
                continue
            try:
                v = ast.literal_eval(line[i:j])
            except (ValueError, SyntaxError, TypeError, MemoryError,
                    RecursionError):
                continue
            if isinstance(v, kinds):
                return v
    return None


def tokens(text):
    return re.findall(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", text)


def has_number(text, value, tol):
    for t in tokens(text):
        try:
            if abs(float(t) - value) <= tol + abs(value) * 1e-9:
                return True
        except OverflowError:
            pass
    return False


def word_in(word, line):
    return re.search(r"(?<!\w)" + re.escape(word) + r"(?!\w)", line)


def fmt_sets(got, exp):
    parts = []
    if exp - got:
        parts.append("missing %s" % short(repr(exp - got), 60))
    if got - exp:
        parts.append("extra %s" % short(repr(got - exp), 60))
    return ", ".join(parts)


# ---------------------------------- ex0 ------------------------------------ #
def ck_ex0(out, inp, args):
    exp = ["=== Command Quest ===", "Program name: ft_command_quest.py"]
    if not args:
        exp.append("No arguments provided!")
    else:
        exp.append("Arguments received: %d" % len(args))
        exp += ["Argument %d: %s" % (i + 1, a) for i, a in enumerate(args)]
    exp.append("Total arguments: %d" % (len(args) + 1))
    expected = "\n".join(exp) + "\n"
    if out == expected:
        return
    lines = out.splitlines()
    if "ft_command_quest.py" not in out:
        ko("the program name (ft_command_quest.py) is not displayed")
    if not args and not any("no argument" in x.lower() for x in lines):
        ko('no "No arguments provided!" message')
    pos = 0
    for i, a in enumerate(args):
        while pos < len(lines) and not (lines[pos].endswith(a)
                                        and str(i + 1) in lines[pos]):
            pos += 1
        if pos >= len(lines):
            ko('argument %d "%s" not displayed (expected "Argument %d: %s",'
               ' in order)' % (i + 1, short(a, 30), i + 1, short(a, 30)))
            break
        pos += 1
    if not any("total" in x.lower() and str(len(args) + 1) in tokens(x)
               for x in lines):
        ko('total %d not displayed (expected "Total arguments: %d")'
           % (len(args) + 1, len(args) + 1))
    compare(expected, out)


# ---------------------------------- ex1 ------------------------------------ #
USAGE1 = ("No scores provided. Usage: python3 ft_score_analytics.py "
          "<score1> <score2> ...")


def ck_ex1(out, inp, args):
    valid, invalid = [], []
    for a in args:
        try:
            valid.append(int(a))
        except ValueError:
            invalid.append(a)
    exp = ["=== Player Score Analytics ==="]
    exp += ["Invalid parameter: '%s'" % a for a in invalid]
    if not valid:
        exp.append(USAGE1)
    else:
        total = sum(valid)
        exp += ["Scores processed: %s" % valid,
                "Total players: %d" % len(valid),
                "Total score: %d" % total,
                "Average score: %s" % (total / len(valid)),
                "High score: %d" % max(valid),
                "Low score: %d" % min(valid),
                "Score range: %d" % (max(valid) - min(valid))]
    expected = "\n".join(exp) + "\n"
    if out == expected:
        return
    lines = out.splitlines()
    body = lines[1:] if lines and "===" in lines[0] else lines
    for a in invalid:
        if a.strip() and not any(a in x for x in body):
            ko("no error message for the invalid score '%s' (expected"
               " \"Invalid parameter: '%s'\")" % (short(a, 30), short(a, 30)))
    if not valid:
        if not any(re.search(r"usage|no (valid )?scores?|provided", x, re.I)
                   for x in body):
            ko('no message when there is no valid score (expected "%s")'
               % short(USAGE1, 45))
    else:
        text = "\n".join(body)
        tok = set(tokens(text))
        for what, v in (("number of scores", len(valid)),
                        ("total score", sum(valid)),
                        ("high score", max(valid)),
                        ("low score", min(valid)),
                        ("score range", max(valid) - min(valid))):
            if str(v) not in tok and not has_number(text, v, 0):
                ko("%s %d not displayed" % (what, v))
        avg = sum(valid) / len(valid)
        if not has_number(text, avg, 0.051):
            ko("average score %s not displayed" % avg)
    compare(expected, out)


# ---------------------------------- ex2 ------------------------------------ #
PROMPT2 = "Enter new coordinates as floats in format 'x,y,z': "


def parse_pos(s):
    parts = s.split(",")
    if len(parts) != 3:
        return "Invalid syntax"
    vals = []
    for p in parts:
        try:
            vals.append(float(p))
        except ValueError as e:
            return "Error on parameter '%s': %s" % (p, e)
    return tuple(vals)


def ck_ex2(out, inp, args):
    it = iter(inp.splitlines())
    errors = []
    o = ["=== Game Coordinate System ===\n\nGet a first set of coordinates\n"]

    def ask():
        while True:
            s = next(it)
            o.append(PROMPT2)
            r = parse_pos(s)
            if isinstance(r, tuple):
                return r
            o.append(r + "\n")
            errors.append((s, r))

    t1 = ask()
    d1 = math.dist(t1, (0, 0, 0))
    o.append("Got a first tuple: %s\nIt includes: X=%s, Y=%s, Z=%s\n"
             "Distance to center: %s\n\nGet a second set of coordinates\n"
             % (t1, t1[0], t1[1], t1[2], round(d1, 4)))
    t2 = ask()
    d2 = math.dist(t1, t2)
    o.append("Distance between the 2 sets of coordinates: %s\n"
             % round(d2, 4))
    expected = "".join(o)
    if out == expected:
        return
    if str(t1) not in out:
        ko("the first tuple %s is not displayed" % (t1,))
    if not has_number(out, d1, 0.051):
        ko("distance to center %s not displayed" % round(d1, 4))
    if not has_number(out, d2, 0.051):
        ko("distance between the 2 sets %s not displayed" % round(d2, 4))
    for s, r in errors:
        bad = r.partition("'")[2].partition("'")[0].strip()
        if r.startswith("Error") and bad and bad not in out:
            ko("no error message for the input \"%s\" (expected like \"%s\")"
               % (short(s, 30), short(r, 60)))
    compare(expected, out)


# ---------------------------------- ex3 ------------------------------------ #
def ck_ex3(out, inp, args):
    lines = out.splitlines()
    found = []
    for x in lines:
        v = literal(x, (set, dict))
        if isinstance(v, dict) and v:
            continue
        if v is not None:
            if isinstance(v, dict):
                say("WARN", 'an empty set is displayed as "{}" (line "%s"):'
                    ' Python displays it as "set()"' % short(x, 40))
                v = set()
            found.append(v)
    n = len(found)
    if n < 14:
        ko("only %d sets displayed; expected at least 14 (4 players, all"
           " distinct, common, 4 \"Only ... has\", 4 \"... is missing\")" % n)
        return
    if (n - 2) % 3:
        say("WARN", "%d sets displayed: could not match them with the"
            " example (players, distinct, common, only, missing):"
            " check by hand" % n)
        return
    p = (n - 2) // 3
    players, union, common = found[:p], found[p], found[p + 1]
    only, missing = found[p + 2:2 * p + 2], found[2 * p + 2:]
    u = set().union(*players)
    c = set(players[0]).intersection(*players[1:])
    if union != u:
        ko("all distinct achievements: %s (union of the %d players)"
           % (fmt_sets(union, u), p))
    if common != c:
        ko("common achievements: %s (intersection of the %d players)"
           % (fmt_sets(common, c), p))
    for i in range(p):
        others = set().union(*(players[:i] + players[i + 1:]))
        if only[i] != players[i] - others:
            ko("only player %d has: %s" % (i + 1, fmt_sets(
                only[i], players[i] - others)))
    full = [missing[i] | players[i] for i in range(p)]
    for i in range(p):
        if missing[i] & players[i]:
            ko("player %d is missing %s, which the player already has"
               % (i + 1, short(repr(missing[i] & players[i]), 60)))
        elif not missing[i] >= u - players[i]:
            ko("player %d is missing: %s" % (i + 1, fmt_sets(
                missing[i], u - players[i])))
    if not KOS and any(f != full[0] for f in full):
        ko('the "missing" sets are not computed from the same list of'
           " all achievements")
    say("STAT", "common %d" % len(common))
    shape(lines, ["=== Achievement Tracker System ===", ""]
          + ["Player NAME: SET"] * p + ["", "All distinct achievements: SET",
                                        "", "Common achievements: SET", ""]
          + ["Only NAME has: SET"] * p + [""] + ["NAME is missing: SET"] * p)


# ---------------------------------- ex4 ------------------------------------ #
ERR4 = re.compile(r"redundant|duplicat|already|valid|error|discard|ignor"
                  r"|skip|wrong|bad|fail|cannot|can't|unknown", re.I)


def ck_ex4(out, inp, args):
    inv = {}
    errs = []
    for a in args:
        parts = a.split(":")
        if len(parts) != 2:
            errs.append((a, "Error - invalid parameter '%s'" % a,
                         [a, parts[0]]))
            continue
        name, q = parts
        if name in inv:
            errs.append((a, "Redundant item '%s' - discarding" % name,
                         [name]))
            continue
        try:
            inv[name] = int(q)
        except ValueError as e:
            errs.append((a, "Quantity error for '%s': %s" % (name, e),
                         [name, a]))
    lines = out.splitlines()
    for a, m, words in errs:
        if not any(ERR4.search(x) and any(w and w in x for w in words)
                   for x in lines):
            ko('no error message for the parameter "%s" (expected like "%s")'
               % (short(a, 30), short(m, 60)))
    total = sum(inv.values())
    if not inv or total <= 0:
        return
    most = max(inv, key=lambda k: inv[k])
    least = min(inv, key=lambda k: inv[k])
    upd = dict(inv)
    upd["magic_item"] = 1
    exp = ["=== Inventory System Analysis ==="] + [m for _, m, _ in errs]
    exp += ["Got inventory: %s" % inv, "Item list: %s" % list(inv),
            "Total quantity of the %d items: %d" % (len(inv), total)]
    exp += ["Item %s represents %s%%" % (k, round(v / total * 100, 1))
            for k, v in inv.items()]
    exp += ["Item most abundant: %s with quantity %d" % (most, inv[most]),
            "Item least abundant: %s with quantity %d" % (least, inv[least]),
            "Updated inventory: %s" % upd]
    expected = "\n".join(exp) + "\n"
    if out == expected:
        return
    # (an empty inventory may be displayed first: only non-empty dicts)
    dicts = [d for d in (literal(x, (dict,)) for x in lines) if d]
    if not dicts:
        ko("the inventory dict is not displayed (expected %s)"
           % short(repr(inv), 50))
    elif dicts[0] != inv:
        ko("inventory: %s; expected %s" % (short(repr(dicts[0]), 50),
                                           short(repr(inv), 50)))
    elif list(dicts[0]) != list(inv):
        say("WARN", "inventory %s: items not in the command-line order"
            % short(repr(dicts[0]), 50))
    lists = [v for v in (literal(x, (list,)) for x in lines) if v is not None]
    if list(inv) not in lists:
        ko("the item list %s is not displayed" % short(repr(list(inv)), 50))
    if str(total) not in tokens(out):
        ko("total quantity %d not displayed" % total)
    for k, v in inv.items():
        pc = v / total * 100
        if not any(word_in(k, x) and has_number(x, pc, 0.5) for x in lines):
            ko("no percentage line for '%s' (expected %s%%)"
               % (k, round(pc, 1)))
    for what, k, kw in (("most", most, r"most|max|highest|biggest|largest"),
                        ("least", least, r"least|min|lowest|smallest|fewest")):
        cand = [x for x in lines if re.search(kw, x, re.I)]
        if not any(word_in(k, x) and str(inv[k]) in tokens(x) for x in cand):
            ko("%s abundant item: %s; expected '%s' with quantity %d"
               % (what, '"%s"' % short(cand[0], 50) if cand
                  else "not displayed", k, inv[k]))
    last = dicts[-1] if len(dicts) > 1 else None
    if last is None:
        ko("the updated inventory is not displayed")
    elif len(last) != len(inv) + 1 or any(
            last.get(k) != v for k, v in inv.items()):
        ko("updated inventory: %s; expected the inventory with one new item"
           % short(repr(last), 60))
    compare(expected, out)


# ---------------------------------- ex5 ------------------------------------ #
def ck_ex5(out, inp, args):
    lines = out.splitlines()
    ev = []
    for i, x in enumerate(lines):
        m = re.match(r"\s*Event\s+(\d+)", x)
        if m:
            ev.append((i, int(m.group(1))))
    if len(ev) != 1000:
        if not ev and len(lines) > 1000:
            say("WARN", 'the events are not displayed as "Event <n>: ...":'
                " could not count them, check by hand")
        else:
            ko('%d "Event <n>" lines; expected 1000 events' % len(ev))
    elif [n for _, n in ev] != list(range(ev[0][1], ev[0][1] + 1000)):
        say("WARN", "the events are not numbered in order")
    events = [re.sub(r"^\s*Event\s+\d+\s*:?", "", lines[i]) for i, _ in ev]
    if len(set(events)) == 1:
        ko('the %d events are all the same ("%s"): they must be random'
           % (len(events), short(events[0], 40)))
    rest = lines[ev[-1][0] + 1:] if ev else lines
    vals = [v for v in (literal(x, (list, tuple)) for x in rest)
            if v is not None]
    k = 0
    while k < len(vals) and not (
            isinstance(vals[k], list) and len(vals[k]) == 10
            and all(isinstance(t, tuple) and len(t) == 2 for t in vals[k])):
        k += 1
    if k >= len(vals):
        ko("no list of 10 events displayed after the 1000 events (expected"
           " \"Built list of 10 events: [('bob', 'run'), ...]\")")
        return
    built = vals[k]
    got = [v for v in vals[k + 1:] if isinstance(v, tuple)]
    rem = [v for v in vals[k + 1:] if isinstance(v, list)]
    if len(got) != 10:
        ko("%d events displayed from consume_event(); expected the 10 events"
           " of the list" % len(got))
    elif Counter(got) != Counter(built):
        ko("the events consumed %s are not the events of the list %s"
           % (short(repr(got), 40), short(repr(built), 40)))
    elif not rem:
        say("WARN", 'the remaining list is not displayed after each event'
            ' (the example shows "Remains in list: [...]")')
    elif len(rem) != 10:
        say("WARN", "%d remaining lists displayed; the example shows one"
            " after each of the 10 events" % len(rem))
    else:
        cur = list(built)
        for t, r in zip(got, rem):
            cur.remove(t)
            if r != cur:
                ko("after %s was consumed, the list is %s; expected %s"
                   % (t, short(repr(r), 50), short(repr(cur), 50)))
                break
    if ev and ev[0][1] != 0:
        say("WARN", "the events are numbered from %d; the example numbers"
            " them from 0" % ev[0][1])
    shape(lines, ["=== Game Data Stream Processor ==="]
          + ["Event INT: Player NAME did action NAME"] * 1000
          + ["Built list of 10 events: LIST"]
          + ["Got event from list: TUPLE", "Remains in list: LIST"] * 10)


# ---------------------------------- ex6 ------------------------------------ #
def ck_ex6(out, inp, args):
    lines = out.splitlines()
    lists = [v for v in (literal(x, (list,)) for x in lines) if v is not None]
    dicts = [v for v in (literal(x, (dict,)) for x in lines) if v is not None]
    if len(lists) < 3 or len(dicts) < 2:
        say("WARN", "found %d list(s) and %d dict(s) in the output; the"
            " example displays 3 lists and 2 dicts: check by hand"
            % (len(lists), len(dicts)))
        return
    l0, l1, l2 = lists[:3]
    if not all(isinstance(n, str) and n for n in l0):
        ko("initial list %s: expected player names" % short(repr(l0), 50))
        return
    caps = [n for n in l0 if n[:1].isupper()]
    if not caps or len(caps) == len(l0):
        ko("initial list %s: some names must be capitalized and others not"
           % short(repr(l0), 50))
    want1 = [n.capitalize() for n in l0]
    if l1 not in (want1, [n[:1].upper() + n[1:] for n in l0],
                  [n.title() for n in l0]):
        ko("all names capitalized: %s; expected %s"
           % (short(repr(l1), 50), short(repr(want1), 50)))
    want2 = [n for n in l0 if n == n.capitalize()]
    if l2 not in (want2, caps, [n for n in l0 if n.istitle()]):
        ko("capitalized names only: %s; expected %s"
           % (short(repr(l2), 50), short(repr(want2), 50)))
    scores, high = dicts[0], dicts[1]
    if set(scores) != set(l1):
        ko("score dict keys %s; expected the capitalized names %s"
           % (short(repr(list(scores)), 50), short(repr(l1), 50)))
    if not scores or not all(isinstance(v, (int, float))
                             for v in scores.values()):
        ko("score dict %s: expected numbers as values"
           % short(repr(scores), 50))
        return
    avg = sum(scores.values()) / len(scores)
    cand = [x for x in lines if "average" in x.lower()]
    if not cand:
        say("WARN", "no line with the score average (example: \"Score"
            " average is 410.11\")")
    elif not has_number(cand[0], avg, 0.051):
        ko("average: \"%s\"; expected %s"
           % (short(cand[0], 50), round(avg, 2)))
    ok = [{k: v for k, v in scores.items() if cmp(v, a)}
          for a in (avg, round(avg, 2))
          for cmp in (lambda x, y: x > y, lambda x, y: x >= y)]
    if high not in ok:
        ko("high scores: %s; expected %s (scores higher than the average"
           " %s)" % (short(repr(high), 50), short(repr(ok[0]), 50),
                     round(avg, 2)))
    say("STAT", "scores %s" % sorted(scores.values()))
    shape(lines, ["=== Game Data Alchemist ===", "",
                  "Initial list of players: LIST",
                  "New list with all names capitalized: LIST",
                  "New list of capitalized names only: LIST", "",
                  "Score dict: DICT", "Score average is NUM",
                  "High scores: DICT"])


def ck_none(out, inp, args):
    pass


if __name__ == "__main__":
    name, out_path, in_path = sys.argv[1:4]
    with open(out_path, encoding="utf-8", errors="replace") as f:
        output = f.read()
    with open(in_path, encoding="utf-8", errors="replace") as f:
        stdin = f.read()
    try:
        globals()["ck_" + name](output, stdin, sys.argv[4:])
    except Exception as e:
        say("WARN", "the tester could not analyse this output (%s: %s):"
            " check by hand" % (type(e).__name__, short(str(e), 50)))
EOF
CK="$TMP/ck.py"

# --------------------------------- Linters ---------------------------------- #
FLAKE8=(); MYPY=()
if command -v flake8 > /dev/null 2>&1; then FLAKE8=(flake8)
elif python3 -m flake8 --version > /dev/null 2>&1; then FLAKE8=(python3 -m flake8); fi
if command -v mypy > /dev/null 2>&1; then MYPY=(mypy)
elif python3 -m mypy --version > /dev/null 2>&1; then MYPY=(python3 -m mypy); fi
[ ${#FLAKE8[@]} -eq 0 ] && printf "${Y}flake8 not installed (pip install flake8): the flake8 checks are skipped.${N}\n"
[ ${#MYPY[@]} -eq 0 ] && printf "${Y}mypy not installed (pip install mypy): the mypy checks are skipped.${N}\n"

# ----------------------------- Work on a copy ------------------------------- #
WORK="$TMP/work"
mkdir -p "$WORK"
tar -C "$DIR" --exclude=.git --exclude=__pycache__ --exclude=.mypy_cache -cf - . | tar -C "$WORK" -xf -
export PT_ROOT="$WORK" PT_EXC="$TMP/exc"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err, EXC
# (10 s at most per test)
run_py() {
	local in=$1
	shift
	rm -f "$TMP/exc"
	( cd "$TMP" && exec timeout -k 1 10 python3 -I "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
	EXC=""
	[ -f "$TMP/exc" ] && EXC=$(head -1 "$TMP/exc")
}

# Results of one test line
# (after a timeout, the other tests of the same line are skipped)
# T_WARNS: differences with the subject's example ("<text><TAB><test>"), shown on a "!!" line
t_begin() { T_FAILS=(); T_WARNS=(); T_N=0; T_INFO=""; T_NOTE=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
t_end() {
	local m i=0
	if t_ok; then
		line_ok "$1" "${T_INFO:-($T_N tests)}"
	else
		line_ko "$1"
		for m in "${T_FAILS[@]}"; do
			i=$((i + 1))
			if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
			msg "$m"
		done
		[ -n "$T_NOTE" ] && note "$T_NOTE"
	fi
	[ ${#T_WARNS[@]} -eq 0 ] && return
	# the same difference in several tests is shown once
	local u=() w x dup
	for w in "${T_WARNS[@]}"; do
		dup=0
		for x in "${u[@]}"; do [ "${x%%$'\t'*}" = "${w%%$'\t'*}" ] && { dup=1; break; }; done
		[ $dup -eq 0 ] && u+=("$w")
	done
	i=0
	for w in "${u[@]:0:3}"; do
		x=${w#*$'\t'}
		m="${x:+$x: }${w%%$'\t'*}"
		if [ $i -eq 0 ]; then line_warn "$1" "$m"; else note "$m"; fi
		i=$((i + 1))
	done
	if [ ${#u[@]} -eq 1 ] && [ ${#T_WARNS[@]} -gt 1 ]; then note "(same difference in ${#T_WARNS[@]} tests)"
	elif [ ${#u[@]} -gt 3 ]; then note "… (${#u[@]} different messages)"; fi
}

# Inputs, shown on one line: "5", "3"
show_input() {
	local s="" l
	[ -z "$1" ] && { printf 'no input'; return; }
	while IFS= read -r l; do s+="\"$l\", "; done <<< "${1%$'\n'}"
	s=${s%, }
	[ ${#s} -gt 60 ] && s="${s:0:55}…"
	printf 'input %s' "$s"
}

# Command line, shown on one line: ft_x.py hello "Data Quest"
show_cmd() {
	local s=$1 a
	shift
	for a in "$@"; do
		if [[ -z $a || $a =~ [[:space:]\'\"\$\*\\] ]]; then s+=" \"$a\""; else s+=" $a"; fi
	done
	[ ${#s} -gt 70 ] && s="${s:0:65}…"
	printf '%s' "$s"
}

# t_prog <checker> <file> <stdin text> [args...]
# Runs "python3 <file> <args>" in a new process, then checks its output with
# ck.py <checker> (KO → ✗ line, WARN → "!!" line). $TMP/ck keeps the checker output.
t_prog() {
	local ck=$1 f=$2 in=$3 what kind m
	shift 3
	: > "$TMP/ck"
	[ $T_TIMEOUT -eq 1 ] && return 1
	printf '%s' "$in" > "$TMP/in"
	run_py "$TMP/in" script "$f" "$@"
	T_N=$((T_N + 1))
	what=$(show_cmd "$(basename "$f")" "$@")
	[ -n "$in" ] && what+=" with $(show_input "$in")"
	[ -n "$PT_SEED" ] && what+=" (random seed $PT_SEED)"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "$what: infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
		return 1
	fi
	if [ $RC -eq 7 ]; then t_fail "$what: $EXC"; return 1; fi
	if [ $RC -eq 3 ]; then
		case $EXC in
			EOFError*) t_fail "$what: reads more input than given ($EXC)" ;;
			*) t_fail "$what: crashes with $EXC" ;;
		esac
		return 1
	fi
	if [ $RC -ne 0 ]; then t_fail "$what: python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"; return 1; fi
	python3 -I "$CK" "$ck" "$TMP/out" "$TMP/in" "$@" > "$TMP/ck" 2>&1
	local nf=${#T_FAILS[@]}
	while read -r kind m; do
		case $kind in
			KO) t_fail "$what: $m" ;;
			WARN) T_WARNS+=("$m"$'\t'"$what") ;;
			NOTE) [ -z "$T_NOTE" ] && T_NOTE=$m ;;
		esac
	done < "$TMP/ck"
	[ ${#T_FAILS[@]} -eq "$nf" ]
}

# t_snip <file> <python code>
# Loads the functions of the file (pt.py defs) and runs a test snippet on them.
# The snippet prints KO / WARN / INFO <text> lines and "COUNT <n>" (number of tests).
t_snip() {
	local f=$1 code=$2 kind m
	[ $T_TIMEOUT -eq 1 ] && return 1
	run_py /dev/null defs "$f" "$code"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1; T_N=$((T_N + 1))
		t_fail "$(basename "$f"): infinite loop or too slow (more than 10 s) in the tested functions"
		return 1
	fi
	if [ $RC -ne 0 ]; then
		T_N=$((T_N + 1))
		t_fail "${EXC:-python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)}"
		return 1
	fi
	while read -r kind m; do
		case $kind in
			KO) t_fail "$m" ;;
			WARN) T_WARNS+=("$m"$'\t') ;;
			INFO) T_INFO=$m ;;
			COUNT) T_N=$((T_N + m)) ;;
		esac
	done < "$TMP/out"
}

# flake8_line <files...>: one line, OK / KO / skipped
flake8_line() {
	local out
	if [ ${#FLAKE8[@]} -eq 0 ]; then line_skip "flake8" "not installed"; return; fi
	out=$(cd "$WORK" && "${FLAKE8[@]}" "$@" 2>&1)
	if [ -z "$out" ]; then line_ok "flake8"
	else
		line_ko "flake8"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
	fi
}

# mypy_line <files...>
mypy_line() {
	local out
	if [ ${#MYPY[@]} -eq 0 ]; then line_skip "mypy" "not installed"; return; fi
	out=$(cd "$WORK" && "${MYPY[@]}" --cache-dir "$TMP/mypy_cache" --no-error-summary "$@" 2>&1 | grep -E 'error:')
	if [ -z "$out" ]; then line_ok "mypy"
	else
		line_ko "mypy"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
	fi
}

# hints_line <file>: every parameter and every return value has a type hint
hints_line() {
	local f=$1 base kind fn l what n=0 m=()
	base=$(basename "$f")
	while read -r kind fn l what; do
		case $kind in
			FUNC) n=$((n + 1)) ;;
			PARAM) m+=("$base:$l: def $fn(): no type hint for: ${what//,/, }") ;;
			RETURN) m+=("$base:$l: def $fn(): no return type hint (-> ...)") ;;
		esac
	done < <(python3 -I "$PT" hints "$f")
	if [ ${#m[@]} -eq 0 ]; then
		if [ $n -eq 0 ]; then line_ok "type hints" "(no function)"
		else line_ok "type hints" "($n function(s), all parameters and returns annotated)"; fi
		return
	fi
	line_ko "type hints"
	for l in "${m[@]:0:6}"; do msg "$l"; done
	[ ${#m[@]} -gt 6 ] && msg "… (${#m[@]} in total)"
	note "\"All functions and methods must include type hints\""
}

# ex_files <exercise dir> <files...> → 0 if every file exists and parses
# (prints "not done" or the syntax error otherwise)
ex_files() {
	local ex=$1 f miss="" nmiss=0 e
	shift
	for f in "$@"; do
		[ -f "$WORK/$ex/$f" ] || { miss+="$ex/$f "; nmiss=$((nmiss + 1)); }
	done
	if [ $nmiss -eq $# ]; then
		line_skip "$ex" "not done (${miss% } not found)"
		return 1
	elif [ $nmiss -gt 0 ]; then
		line_ko "files"; msg "missing: ${miss% }"
		return 1
	fi
	for f in "$@"; do
		e=$(python3 -I "$PT" ast "$WORK/$ex/$f" '*' '' | grep -m1 '^SYNTAX')
		if [ -n "$e" ]; then
			read -r _ l e <<< "$e"
			line_ko "$f"; msg "SyntaxError line $l: $e"
			return 1
		fi
	done
	return 0
}

# static_line <file> <allowed calls> <allowed imports> <tolerated> <authorized text>
# "authorized" line: builtin calls, imports and module attributes (sys.argv,
# math.sqrt...) must be in the subject's list. The "tolerated" names (calls or
# modules) only give a warning. Sets STATIC_DEFS (top-level functions).
STATIC_DEFS=()
static_line() {
	local f=$1 calls=$2 imps=$3 tol=",$4," text=$5 kind a b item tok bad=() warn=()
	STATIC_DEFS=()
	while read -r kind a b; do
		case $kind in
			DEF) STATIC_DEFS+=("$a"); continue ;;
			CALL) item="$a() (line $b)"; tok=$a ;;
			IMPORT) item="import $a (line $b)"; tok=$a ;;
			ATTR) item="$a (line $b)"; tok=${a%%.*} ;;
			*) continue ;;
		esac
		if [[ $tol == *",$tok,"* ]]; then warn+=("$item"); else bad+=("$item"); fi
	done < <(python3 -I "$PT" ast "$f" "$calls" "$imps")
	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized" "($text)"
	else
		line_ko "authorized"
		msg "forbidden: ${bad[*]}"
		note "authorized: $text"
	fi
	if [ ${#warn[@]} -gt 0 ]; then
		line_warn "authorized" "not in the authorized list: ${warn[*]}"
		note "tolerated here (type hints / small helper), but be ready to justify it"
	fi
}

# functions_line <file> <functions...>: the requested functions exist (top level)
functions_line() {
	local f=$1 fn miss=()
	shift
	for fn in "$@"; do
		[[ " ${STATIC_DEFS[*]} " == *" $fn "* ]] || miss+=("$fn")
	done
	if [ ${#miss[@]} -eq 0 ]; then line_ok "functions" "($(printf '%s() ' "$@"| sed 's/ $//'))"; return 0; fi
	line_ko "functions"
	for fn in "${miss[@]}"; do msg "$(basename "$f"): no function named $fn() (the name must match exactly)"; done
	return 1
}

# Types usable in each exercise: str, int, float (general rules) + the data
# structures already introduced (list ex0, tuple ex2, set ex3, dict ex4)
TYPES="str,int,float,list"
TOLERATED="typing,collections.abc"
nl=$'\n'

# ================================ Exercises ================================= #

# ---------------------------- ex0: command quest ---------------------------- #
if wanted 0; then
	section "ex0 - ft_command_quest"
	if ex_files ex0 ft_command_quest.py; then
		F="$WORK/ex0/ft_command_quest.py"
		flake8_line ex0/ft_command_quest.py
		mypy_line ex0/ft_command_quest.py
		hints_line "$F"
		static_line "$F" "len,print,$TYPES" sys.argv "$TOLERATED" \
			"import sys, sys.argv, len(), print(), str/int/float/list"
		t_begin
		t_prog ex0 "$F" ""
		t_prog ex0 "$F" "" hello world 42
		t_prog ex0 "$F" "" "Data Quest"
		t_prog ex0 "$F" "" 42
		t_prog ex0 "$F" "" ""
		t_prog ex0 "$F" "" same same same
		t_prog ex0 "$F" "" -1 --help "*" '$HOME' "  spaced  " "école" "🎮"
		t_prog ex0 "$F" "" ft_command_quest.py
		t_prog ex0 "$F" "" a b c d e f g h i j k l m n o p q r s t u v w x y z
		t_prog ex0 "$F" "" "line one" "" "last"
		t_end "output"
	fi
fi

# ---------------------------- ex1: score cruncher --------------------------- #
if wanted 1; then
	section "ex1 - ft_score_analytics"
	if ex_files ex1 ft_score_analytics.py; then
		F="$WORK/ex1/ft_score_analytics.py"
		flake8_line ex1/ft_score_analytics.py
		mypy_line ex1/ft_score_analytics.py
		hints_line "$F"
		static_line "$F" "len,sum,max,min,print,$TYPES" sys.argv "$TOLERATED" \
			"import sys, sys.argv, len(), sum(), max(), min(), print(), str/int/float/list"
		t_begin
		t_prog ex1 "$F" "" 1500 2300 1800 2100 1950
		t_prog ex1 "$F" ""
		t_prog ex1 "$F" "" ab ac
		t_prog ex1 "$F" "" 42
		t_prog ex1 "$F" "" 0
		t_prog ex1 "$F" "" 100 100 100
		t_prog ex1 "$F" "" 3 1 2
		t_prog ex1 "$F" "" 10 abc 20 "" 30
		t_prog ex1 "$F" "" 12abc 7 x1
		t_prog ex1 "$F" "" hello
		t_prog ex1 "$F" "" "1 2" 5
		t_prog ex1 "$F" "" 99999999999999999999 1
		t_prog ex1 "$F" "" $(seq 1 60)
		t_prog ex1 "$F" "" 7 7 abc 7 def
		t_end "output"
		# negative scores: valid int(), but the subject does not say if they are allowed
		t_begin
		t_prog ex1 "$F" "" -5 10 -20
		t_prog ex1 "$F" "" 50 -50
		if t_ok; then line_ok "negative scores" "($T_N tests, accepted as scores)"
		else
			line_warn "negative scores" "${T_FAILS[0]}"
			note "-5 is a valid int(): the subject does not say if a negative score is valid,"
			note "be ready to explain your choice"
		fi
	fi
fi

# ---------------------------- ex2: position tracker ------------------------- #
read -r -d '' SNIP2 <<'EOF'
cases = [
    ("1,2,3\n", (1.0, 2.0, 3.0)),
    ("1.0 , 2.5, 3.0\n", (1.0, 2.5, 3.0)),
    ("-1.5,0,42\n", (-1.5, 0.0, 42.0)),
    ("0,0,0\n", (0.0, 0.0, 0.0)),
    ("123456.789,-0.001,7\n", (123456.789, -0.001, 7.0)),
    (" 7 , 8 , 9 \n", (7.0, 8.0, 9.0)),
    ("hello world\n4,5,6\n", (4.0, 5.0, 6.0)),
    ("4,abc,5\n4,5,6\n", (4.0, 5.0, 6.0)),
    ("\n1,2\n1,2,3,4\n,,\na,b,c\n1;2;3\n1.5,2.5,x\n10,20,30\n",
     (10.0, 20.0, 30.0)),
]
for text, want in cases:
    shown = ", ".join('"%s"' % x for x in text.splitlines())
    if len(shown) > 60:
        shown = shown[:60] + "…"
    what = "get_player_pos() with input %s" % shown
    v, printed, e = run(m.get_player_pos, stdin=text)
    n_bad = len(text.splitlines()) - 1
    if e and e.startswith("EOFError"):
        print("KO %s: does not return after the valid line (reads more "
              "input: %s)" % (what, e))
    elif e:
        print("KO %s: %s" % (what, raises(e)))
    elif not isinstance(v, tuple):
        print("KO %s: returns %s (%s); expected the tuple %r"
              % (what, short(repr(v), 40), type(v).__name__, want))
    elif v != want:
        print("KO %s: returns %s; expected %r" % (what, short(repr(v)), want))
    elif not all(type(x) is float for x in v):
        print("WARN %s: returns %r: the coordinates should be floats"
              % (what, v))
    elif printed.count("\n") < n_bad:
        print("WARN %s: %d invalid line(s) but only %d line(s) printed: "
              "each improper input should get an error message"
              % (what, n_bad, printed.count("\n")))
print("COUNT %d" % len(cases))
EOF

if wanted 2; then
	section "ex2 - ft_coordinate_system"
	if ex_files ex2 ft_coordinate_system.py; then
		F="$WORK/ex2/ft_coordinate_system.py"
		flake8_line ex2/ft_coordinate_system.py
		mypy_line ex2/ft_coordinate_system.py
		hints_line "$F"
		static_line "$F" "input,round,print,$TYPES,tuple" math.sqrt "$TOLERATED,len" \
			"import math, math.sqrt(), input(), round(), print(), str/int/float/list/tuple"
		if functions_line "$F" get_player_pos; then
			t_begin
			t_snip "$F" "$SNIP2"
			t_end "get_player_pos()"
		fi
		t_begin
		t_prog ex2 "$F" "hello world${nl}1.0 , 2.5, 3.0${nl}4,abc,5${nl}4,5,6$nl"
		t_prog ex2 "$F" "0,0,0${nl}0,0,0$nl"
		t_prog ex2 "$F" "3,4,0${nl}0,0,0$nl"
		t_prog ex2 "$F" "-1,-2,-2${nl}1,2,2$nl"
		t_prog ex2 "$F" "1.5,2.5,3.5${nl}1.5,2.5,3.5$nl"
		t_prog ex2 "$F" "100,200,300${nl}-100,-200,-300$nl"
		t_prog ex2 "$F" "1,2${nl}1,2,3,4${nl}1,2,3${nl}x,1,2${nl}10,20,30$nl"
		t_prog ex2 "$F" "${nl},,${nl}1,1,1${nl}2,2,2$nl"
		t_prog ex2 "$F" "0.1,0.2,0.3${nl}hello${nl}1;2;3${nl}-0.5,7,10$nl"
		t_end "program"
	fi
fi

# --------------------------- ex3: achievement hunter ------------------------ #
read -r -d '' SNIP3 <<'EOF'
import inspect
f = m.gen_player_achievements
need = [p for p in inspect.signature(f).parameters.values()
        if p.default is p.empty and p.kind in (p.POSITIONAL_ONLY,
                                               p.POSITIONAL_OR_KEYWORD)]
res = []
if need:
    print("WARN gen_player_achievements%s needs arguments: the subject calls "
          "it without any; its results are not tested" % inspect.signature(f))
else:
    for _ in range(300):
        v, printed, e = run(f)
        if e:
            print("KO gen_player_achievements() " + raises(e))
            break
        if not isinstance(v, set):
            print("KO gen_player_achievements() returns %s (%s); expected a "
                  "set" % (short(repr(v), 40), type(v).__name__))
            break
        res.append(v)
if len(res) == 300:
    allv = set().union(*res)
    sizes = sorted(set(len(s) for s in res))
    if any(not isinstance(x, str) for x in allv):
        print("WARN gen_player_achievements() returns %s: achievements "
              "should be names (str)" % short(repr(res[0]), 40))
    if len(set(frozenset(s) for s in res)) == 1:
        print("KO 300 calls of gen_player_achievements() always return %s: "
              "the achievements must be picked randomly" % short(repr(res[0])))
    elif len(sizes) == 1:
        print("KO 300 calls of gen_player_achievements() always return %d "
              "achievements: \"Choose a random number of achievements\""
              % sizes[0])
    print("INFO (300 calls: %d different achievements, %d to %d per player)"
          % (len(allv), sizes[0], sizes[-1]))
print("COUNT 300")
EOF

if wanted 3; then
	section "ex3 - ft_achievement_tracker"
	if ex_files ex3 ft_achievement_tracker.py; then
		F="$WORK/ex3/ft_achievement_tracker.py"
		flake8_line ex3/ft_achievement_tracker.py
		mypy_line ex3/ft_achievement_tracker.py
		hints_line "$F"
		static_line "$F" "len,print,$TYPES,tuple,set" "random.*" "$TOLERATED" \
			"len(), print(), import random, random.*, set() and its methods, str/int/float/list/tuple"
		if functions_line "$F" gen_player_achievements; then
			t_begin
			t_snip "$F" "$SNIP3"
			t_end "gen_player_achie…()"
		fi
		t_begin
		n_empty=0; outs=()
		for seed in 1 2 3 4 5 6 7 8 9 10; do
			PT_SEED=$seed t_prog ex3 "$F" ""
			grep -q '^STAT common 0$' "$TMP/ck" && n_empty=$((n_empty + 1))
			outs+=("$(md5sum < "$TMP/out")")
		done
		T_INFO="($T_N runs: union, intersection, differences checked)"
		t_end "program"
		if t_ok; then
			if [ "$(printf '%s\n' "${outs[@]}" | sort -u | wc -l)" -eq 1 ]; then
				line_warn "random" "the 10 runs (different random seeds) give the same output"
			elif [ $n_empty -eq 10 ]; then
				line_warn "random" "\"Common achievements\" is empty in all the 10 runs"
				note "subject: adjust the numbers so that all the requested sets are likely to be non-empty"
			else
				line_ok "random" "(different outputs, common achievements found in $((10 - n_empty))/10 runs)"
			fi
		fi
	fi
fi

# ---------------------------- ex4: inventory master ------------------------- #
if wanted 4; then
	section "ex4 - ft_inventory_system"
	if ex_files ex4 ft_inventory_system.py; then
		F="$WORK/ex4/ft_inventory_system.py"
		flake8_line ex4/ft_inventory_system.py
		mypy_line ex4/ft_inventory_system.py
		hints_line "$F"
		static_line "$F" "len,print,sum,list,round,$TYPES,tuple,set,dict" sys.argv "$TOLERATED" \
			"import sys, sys.argv, len(), print(), sum(), list(), round(), dict methods, str/int/float"
		t_begin
		t_prog ex4 "$F" "" sword:1 potion:5 shield:2 armor:3 helmet:1 sword:2 hello key:value
		t_prog ex4 "$F" "" potion:3
		t_prog ex4 "$F" "" bow:1 arrow:1 quiver:1
		t_prog ex4 "$F" "" sword:10 shield:10 potion:1 tonic:1
		t_prog ex4 "$F" "" gem:100 coin:999 gem:5 coin:1
		t_prog ex4 "$F" "" key:value lock:3
		t_prog ex4 "$F" "" apple:2 banana
		t_prog ex4 "$F" "" rope:b:c herb:4
		t_prog ex4 "$F" "" torch: lamp:6
		t_prog ex4 "$F" "" map:7 compass:2 map:7 ring:x boots dagger:12
		t_prog ex4 "$F" "" $(for i in $(seq 1 30); do printf 'item%d:%d ' "$i" "$i"; done)
		t_prog ex4 "$F" "" crystal:123456789 dust:1
		t_end "output"
		# Edge cases: the behaviour is free, but the program must not crash
		t_begin
		for c in "" "hello world" "x:0" "x:0 y:0" "x:-3 y:3" "x:-3 y:5" ":5 a:1" "x:+5" "x: 5" "a:1 a:1 a:1" ":" "::"; do
			read -r -a A <<< "$c"
			t_prog none "$F" "" "${A[@]}"
		done
		T_INFO="($T_N tests: no argument, invalid only, zero / negative quantities...)"
		t_ok || T_NOTE="\"Your functions should handle exceptions gracefully to avoid crashes\" (total of 0 → division by zero?)"
		t_end "no crash"
	fi
fi

# ----------------------------- ex5: stream wizard --------------------------- #
read -r -d '' SNIP5 <<'EOF'
import types
from collections import Counter
v, printed, e = run(m.gen_event)
if e:
    print("KO gen_event() " + raises(e))
elif not isinstance(v, types.GeneratorType):
    print("KO gen_event() returns %s; expected a generator (yield)"
          % short(repr(v), 40))
else:
    evs = []
    for i in range(5000):
        x, printed, e = run(next, v)
        if e:
            print("KO next() on gen_event() raises %s after %d events: it "
                  "must be endless" % (e, len(evs)))
            break
        evs.append(x)
    bad = [x for x in evs if not (isinstance(x, tuple) and len(x) == 2
                                  and all(isinstance(y, str) for y in x))]
    if bad:
        print("KO next(gen_event()) returns %s; expected a tuple "
              "(name, action)" % short(repr(bad[0]), 40))
    elif len(evs) == 5000:
        names, acts = set(x[0] for x in evs), set(x[1] for x in evs)
        if len(names) < 2 or len(acts) < 2:
            print("KO 5000 events from gen_event() use %d player(s) and %d "
                  "action(s): they must be picked randomly from lists"
                  % (len(names), len(acts)))
        print("INFO (5000 events: %d players, %d actions; consume_event "
              "checked on 50 lists)" % (len(names), len(acts)))
base = [("alice", "run"), ("bob", "eat"), ("alice", "run"), ("dylan", "swim"),
        ("charlie", "move"), ("bob", "sleep"), ("dylan", "grab"),
        ("alice", "use"), ("charlie", "climb"), ("bob", "release")]
lst = list(base)
v, printed, e = run(m.consume_event, lst)
if e:
    print("KO consume_event(<list of 10 events>) " + raises(e))
elif not isinstance(v, types.GeneratorType):
    print("KO consume_event(<list of 10 events>) returns %s; expected a "
          "generator (yield)" % short(repr(v), 40))
else:
    got = []
    err = False
    for k in range(11):
        x, printed, e = run(next, v)
        if e and e.startswith("StopIteration"):
            break
        err = True
        if e:
            print("KO next() on consume_event(<list of 10>) " + raises(e))
            break
        got.append(x)
        if len(lst) != len(base) - len(got):
            print("KO consume_event(<list of 10>): after %d event(s) yielded,"
                  " the list has %d elements; expected %d (each event yielded"
                  " must be removed from the list)"
                  % (len(got), len(lst), len(base) - len(got)))
            break
        if Counter(lst) + Counter(got) != Counter(base):
            print("KO consume_event(<list of 10>): yields %r but this event "
                  "was not the one removed from the list" % (x,))
            break
        err = False
    if not err and len(got) != 10:
        print("KO consume_event(<list of 10 events>) yields %d events; "
              "expected 10 (until the list is empty)" % len(got))
    orders = set()
    for _ in range(50):
        lst = list(base)
        v, printed, e = run(lambda: list(m.consume_event(lst)))
        if e:
            break
        orders.add(tuple(v))
    if len(orders) == 1:
        print("KO 50 calls of consume_event() on the same list always yield "
              "the events in the same order: they must be picked randomly")
v, printed, e = run(lambda: list(m.consume_event([])))
if e:
    print("KO consume_event([]) " + raises(e))
elif v != []:
    print("KO consume_event([]) yields %s; expected nothing" % short(repr(v)))
print("COUNT 5")
EOF

if wanted 5; then
	section "ex5 - ft_data_stream"
	if ex_files ex5 ft_data_stream.py; then
		F="$WORK/ex5/ft_data_stream.py"
		flake8_line ex5/ft_data_stream.py
		mypy_line ex5/ft_data_stream.py
		hints_line "$F"
		static_line "$F" "next,range,len,print,$TYPES,tuple,set,dict" "typing.Generator,random.*" \
			"typing,collections.abc" \
			"next(), range(), len(), print(), import typing, typing.Generator, import random, random.*"
		if functions_line "$F" gen_event consume_event; then
			FEAT=$(python3 -I "$PT" feat "$F")
			t_begin
			for fn in gen_event consume_event; do
				T_N=$((T_N + 1))
				grep -q "^GEN $fn " <<< "$FEAT" || t_fail "$fn() does not use yield: it must be a generator function"
			done
			T_N=$((T_N + 1))
			grep -q '^FORCALL consume_event$' <<< "$FEAT" \
				|| t_fail "consume_event() is not used directly in a for loop (for event in consume_event(events): ...)"
			t_end "generators (yield)"
			t_begin
			t_snip "$F" "$SNIP5"
			t_end "gen/consume_event"
		fi
		t_begin
		for seed in 1 2 3; do
			PT_SEED=$seed t_prog ex5 "$F" ""
		done
		T_INFO="($T_N runs: 1000 events, list of 10, each event consumed once)"
		t_end "program"
	fi
fi

# ----------------------------- ex6: data alchemist -------------------------- #
if wanted 6; then
	section "ex6 - ft_data_alchemist"
	if ex_files ex6 ft_data_alchemist.py; then
		F="$WORK/ex6/ft_data_alchemist.py"
		flake8_line ex6/ft_data_alchemist.py
		mypy_line ex6/ft_data_alchemist.py
		hints_line "$F"
		static_line "$F" "print,len,sum,round,$TYPES,tuple,set,dict" "random.*" "$TOLERATED" \
			"import random, random.*, print(), len(), sum(), round(), str/int/float/list/tuple/set/dict"
		FEAT=$(python3 -I "$PT" feat "$F")
		nlc=$(sed -n 's/^COUNT listcomp //p' <<< "$FEAT"); ndc=$(sed -n 's/^COUNT dictcomp //p' <<< "$FEAT")
		t_begin
		T_N=2
		[ "${nlc:-0}" -lt 2 ] && t_fail "$nlc list comprehension(s); the subject asks for 2 (all names capitalized, capitalized names only)"
		[ "${ndc:-0}" -lt 2 ] && t_fail "$ndc dict comprehension(s); the subject asks for 2 (score dict, high scores)"
		T_INFO="($nlc list and $ndc dict comprehensions)"
		t_end "comprehensions"
		if grep -q '^SPLIT' <<< "$FEAT"; then
			line_warn "single line" "comprehension on several lines line(s) $(sed -n 's/^SPLIT [a-z]* //p' <<< "$FEAT" | tr '\n' ' ')"
			note "subject: \"Each comprehension should be on a single line (unless it exceeds the line size)\""
		fi
		t_begin
		scores=()
		for seed in 1 2 3 4 5 6 7 8; do
			PT_SEED=$seed t_prog ex6 "$F" ""
			scores+=("$(grep -m1 '^STAT scores' "$TMP/ck")")
		done
		T_INFO="($T_N runs: capitalized lists, score dict, average, high scores)"
		t_end "program"
		if t_ok && [ "$(printf '%s\n' "${scores[@]}" | sort -u | wc -l)" -eq 1 ] && [ -n "${scores[0]}" ]; then
			line_warn "random" "the 8 runs (different random seeds) give the same scores: they should be random"
		fi
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/ft_command_quest.py]=1 [ex1/ft_score_analytics.py]=1
		[ex2/ft_coordinate_system.py]=1 [ex3/ft_achievement_tracker.py]=1
		[ex4/ft_inventory_system.py]=1 [ex5/ft_data_stream.py]=1
		[ex6/ft_data_alchemist.py]=1
	)
	extra=""
	while IFS= read -r f; do
		f=${f#./}
		[ -n "${EXPECTED[$f]}" ] || extra+="$f "
	done < <(cd "$DIR" && find ./ex[0-9]* -type f ! -path '*/__pycache__/*' ! -path '*/.mypy_cache/*' 2>/dev/null | sort)
	if [ -z "$extra" ]; then line_ok "files" "(only the requested files)"
	else
		line_warn "files" "files that are not requested (\"return only the files requested\"):"
		note "$extra"
	fi
	if [ -n "$(cd "$DIR" && find . -name __pycache__ -o -name .mypy_cache 2>/dev/null | head -1)" ]; then
		line_warn "caches" "__pycache__ / .mypy_cache folders found: do not push them"
	fi
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
