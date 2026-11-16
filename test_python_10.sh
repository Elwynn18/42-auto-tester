#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_10.sh - single-file tester for Python Module 10 (FuncMage)      #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_10.sh               -> test everything              #
#      bash ../test_python_10.sh 2 ex3         -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
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
banner "Python Module 10 tester (FuncMage)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 10 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_10.XXXXXX)
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
EXS=(0 1 2 3 4)
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
# info <file>         : facts about the code, one per line, tab separated
#                       (functions, lambdas, loops, calls, decorators, imports,
#                       type hints, code outside functions, eval/exec/open/global)
# exec <file> <code>  : imports the file as `m` (its output is hidden), then runs
#                       the test code, which reports in $PT_RES with fail() /
#                       warn() / note() / count()
cat > "$TMP/pt.py" <<'EOF'
import ast
import contextlib
import copy  # noqa: F401 (used by the test code)
import functools  # noqa: F401
import importlib.util
import inspect  # noqa: F401
import io
import os
import re  # noqa: F401
import sys
import time  # noqa: F401
import traceback

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))
FUNCS = (ast.FunctionDef, ast.AsyncFunctionDef)


def short(s, n=70):
    out = ""
    for c in s:
        if c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
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


def load(path):
    path = os.path.abspath(path)
    sys.path.insert(0, os.path.dirname(path))
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# ------------------------------- info mode -------------------------------- #
def out(*fields):
    print("\t".join(short(str(f), 400) for f in fields))


def names_in(node):
    """Names and attribute names used in a node."""
    s = set()
    for n in ast.walk(node):
        if isinstance(n, ast.Name):
            s.add(n.id)
        elif isinstance(n, ast.Attribute):
            s.add(n.attr)
    return s


def called_in(node):
    s = set()
    for n in ast.walk(node):
        if isinstance(n, ast.Call):
            if isinstance(n.func, ast.Name):
                s.add(n.func.id)
            elif isinstance(n.func, ast.Attribute):
                s.add(n.func.attr)
    return s


def missing_hints(fn):
    a = fn.args
    miss = [x.arg for x in a.posonlyargs + a.args + a.kwonlyargs
            if x.annotation is None and x.arg not in ("self", "cls")]
    for x, star in ((a.vararg, "*"), (a.kwarg, "**")):
        if x is not None and x.annotation is None:
            miss.append(star + x.arg)
    if fn.returns is None:
        miss.append("the return value")
    return miss


def fn_facts(name, fn):
    walk = list(ast.walk(fn))
    lam = sum(isinstance(n, ast.Lambda) for n in walk)
    loops = sum(isinstance(n, (ast.For, ast.While, ast.AsyncFor, ast.comprehension))
                for n in walk)
    nested = [n.name for n in walk if isinstance(n, FUNCS) and n is not fn]
    out("FUNC", name, lam, loops, ",".join(nested) or "-",
        ",".join(sorted(called_in(fn))) or "-", ",".join(sorted(names_in(fn))) or "-")
    for d in fn.decorator_list:
        out("DECO", name, ast.unparse(d))
    miss = missing_hints(fn)
    if miss:
        out("HINT", fn.lineno, name, ", ".join(miss))
    for n in walk:
        if isinstance(n, FUNCS) and n is not fn:
            miss = missing_hints(n)
            if miss:
                out("NHINT", n.lineno, name + " > " + n.name, ", ".join(miss))


def is_main_guard(node):
    return (isinstance(node, ast.If) and isinstance(node.test, ast.Compare)
            and "__name__" in ast.dump(node.test))


def is_alias(s):
    """Type alias (X = Callable[...]) or dunder (__all__ = ...)."""
    if isinstance(s, ast.AnnAssign):
        return "TypeAlias" in ast.unparse(s.annotation)
    if isinstance(s, ast.Assign):
        if all(isinstance(t, ast.Name) and t.id.startswith("__") for t in s.targets):
            return True
        return isinstance(s.value, ast.Subscript)
    return type(s).__name__ == "TypeAlias"


def is_std(name):
    names = getattr(sys, "stdlib_module_names", None)
    return 1 if names is None or name.split(".")[0] in names \
        or name == "__future__" else 0


def cmd_info(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src, path)
    except SyntaxError as e:
        out("SYNTAX", e.lineno, e.msg)
        return 0
    for s in tree.body:
        if isinstance(s, FUNCS):
            out("DEF", s.name, s.lineno)
            fn_facts(s.name, s)
            inner = set(map(id, ast.walk(s)))
            if any(isinstance(n, ast.Name) and n.id == s.name and id(n) not in inner
                   for n in ast.walk(tree)):
                out("USED", s.name)
        elif isinstance(s, ast.ClassDef):
            out("CLASS", s.name, s.lineno)
            for b in s.body:
                if isinstance(b, FUNCS):
                    out("DEF", s.name + "." + b.name, b.lineno)
                    fn_facts(s.name + "." + b.name, b)
        elif isinstance(s, (ast.Import, ast.ImportFrom)):
            continue
        elif isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant) \
                and isinstance(s.value.value, str):
            continue
        elif is_main_guard(s):
            out("MAIN", s.lineno)
        elif is_alias(s):
            continue
        elif isinstance(s, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            out("VAR", s.lineno, short(ast.unparse(s).split("\n")[0], 50))
        else:
            out("TOP", s.lineno, short(ast.unparse(s).split("\n")[0], 50))
    mods = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) \
                and n.func.id in ("eval", "exec", "open"):
            out("BAD", n.lineno, n.func.id + "()")
        elif isinstance(n, ast.Global):
            out("BAD", n.lineno, "global " + ", ".join(n.names))
        elif isinstance(n, ast.Import):
            for a in n.names:
                out("IMPORT", n.lineno, a.name, "-", is_std(a.name))
                mods[a.asname or a.name.split(".")[0]] = a.name.split(".")[0]
        elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
            out("IMPORT", n.lineno, n.module, ",".join(a.name for a in n.names),
                is_std(n.module))
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) \
                and n.value.id in mods:
            out("ATTR", n.lineno, mods[n.value.id] + "." + n.attr)
    return 0


# ------------------------------- exec mode -------------------------------- #
RES = None


def emit(kind, text):
    RES.write("%s %s\n" % (kind, short(str(text), 400)))
    RES.flush()


def fail(text):
    emit("F", text)


def warn(text):
    emit("W", text)


def note(text):
    emit("I", text)


def count(n=1):
    emit("N", n)


def R(x, n=60):
    try:
        return short(repr(x), n)
    except Exception:
        return "<%s>" % type(x).__name__


def cap(f, *a, **k):
    """Calls f(*a, **k), its output captured -> (result, output, exception)."""
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            r = f(*a, **k)
    except (Exception, SystemExit) as e:
        return None, buf.getvalue(), e
    return r, buf.getvalue(), None


def expect(what, f, args, exp, kw=None):
    """One test: f(*args, **kw) must return exp (same value, same type)."""
    count()
    r, _, e = cap(f, *args, **(kw or {}))
    if e is not None:
        fail("%s raises %s; expected %s" % (what, summary(e), R(exp)))
        return False
    if r != exp or type(r) is not type(exp):
        fail("%s returned %s; expected %s" % (what, R(r), R(exp)))
        return False
    return True


def cmd_exec(path, code):
    global RES
    RES = open(os.environ["PT_RES"], "a", encoding="utf-8")
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            mod = load(path)
    except BaseException as e:
        fail("importing %s raises %s" % (os.path.basename(path), summary(e)))
        return 5
    env = dict(globals())
    env["m"] = mod
    try:
        exec(compile(code, "<test>", "exec"), env)
    except BaseException as e:
        fail(summary(e))
        return 3
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"info": cmd_info, "exec": cmd_exec}[cmd](*sys.argv[2:]))
EOF
PT="$TMP/pt.py"

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
export PT_ROOT="$WORK" PT_RES="$TMP/res"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err
# (10 s at most per test)
run_py() {
	local in=$1
	shift
	( cd "$TMP" && exec timeout -k 1 10 python3 -I "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
}

# run_script <exercise dir> <file> → RC, $TMP/out, $TMP/err
# Runs "python3 <file>" in the exercise folder, like the subject does (10 s at most).
run_script() {
	( cd "$WORK/$1" && exec timeout -k 1 10 python3 "$2" ) < /dev/null > "$TMP/out" 2> "$TMP/err"
	RC=$?
}

# Results of one test line
# (after a timeout, the other tests of the same line are skipped)
t_begin() { T_FAILS=(); T_WARNS=(); T_N=0; T_INFO=""; T_NOTE=""; T_TIMEOUT=0; T_SKIP=""; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
t_end() {
	local m i=0
	if t_ok; then
		if [ -n "$T_SKIP" ]; then
			line_skip "$1" "$T_SKIP"
		elif [ ${#T_WARNS[@]} -gt 0 ]; then
			line_warn "$1" "${T_WARNS[0]}"
			for m in "${T_WARNS[@]:1:3}"; do note "$m"; done
		else
			line_ok "$1" "${T_INFO:-($T_N tests${T_NOTE:+, $T_NOTE})}"
		fi
		return
	fi
	line_ko "$1"
	for m in "${T_FAILS[@]}"; do
		i=$((i + 1))
		if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
		msg "$m"
	done
	[ ${#T_WARNS[@]} -gt 0 ] && note "also: ${T_WARNS[0]}"
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# t_py <file> <what is tested> <python test code>
# Runs the test code in a new python3 process, with the file imported as `m`.
# The code reports with fail() / warn() / note() / count() (see pt.py).
# "<what>" is the tested function ("name()") or class: the line is skipped when
# fp_static did not find it.
t_py() {
	local f=$1 what=$2 code=$3 l
	[ $T_TIMEOUT -eq 1 ] && return 1
	if [[ $what != import* ]] && [[ "$DEFS" != *" ${what%()} "* ]]; then
		T_SKIP="not tested: no ${what%()}$([[ $what == *"()" ]] && echo "()") (see structure)"
		return 1
	fi
	: > "$TMP/res"
	run_py /dev/null exec "$f" "$code"
	while IFS= read -r l; do
		case ${l%% *} in
			F) t_fail "${l#F }" ;;
			W) T_WARNS+=("${l#W }") ;;
			I) T_NOTE=${l#I } ;;
			N) T_N=$((T_N + ${l#N })) ;;
		esac
	done < "$TMP/res"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "$what: infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
	elif [ $RC -ne 0 ] && [ $RC -ne 3 ] && [ $RC -ne 5 ]; then
		t_fail "$what: python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"
	fi
	t_ok
}

# import_ok <file>: one "import" line, only when importing the file fails
# (the runtime tests of the exercise are then skipped)
import_ok() {
	t_begin
	t_py "$1" "import $(basename "$1")" "pass"
	t_ok && return 0
	t_end "import"
	line_skip "runtime tests" "skipped: the file cannot be imported"
	return 1
}

# py_code: reads a test code from stdin into $CODE
py_code() { CODE=$(cat); }

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
		e=$(python3 -I "$PT" info "$WORK/$ex/$f" | grep -m1 '^SYNTAX')
		if [ -n "$e" ]; then
			IFS=$'\t' read -r _ l e <<< "$e"
			line_ko "$f"; msg "SyntaxError line $l: $e"
			return 1
		fi
	done
	return 0
}

# fp_static <exercise dir> <file> <functools/operator: none|all|wraps> <required names...>
# Reads the facts of "pt.py info" (FN_* arrays, DEFS, USED) and prints three
# lines: "structure", "authorized" and "type hints".
declare -A FN_LAM=() FN_LOOPS=() FN_NESTED=() FN_CALLS=() FN_REFS=() FN_DECO=()
fp_static() {
	local ex=$1 base=$2 pol=$3 kind a b c d e f x m
	local struct=() swarn=() bad=() hko=() hwarn=()
	shift 3
	DEFS=" "; USED=" "
	FN_LAM=(); FN_LOOPS=(); FN_NESTED=(); FN_CALLS=(); FN_REFS=(); FN_DECO=()
	while IFS=$'\t' read -r kind a b c d e f; do
		case $kind in
			DEF|CLASS) DEFS+="$a " ;;
			FUNC) FN_LAM[$a]=$b; FN_LOOPS[$a]=$c; FN_NESTED[$a]=$d; FN_CALLS[$a]=",$e,"; FN_REFS[$a]=",$f," ;;
			DECO) FN_DECO[$a]+="$b;" ;;
			USED) USED+="$a " ;;
			TOP) swarn+=("$base:$a: code outside functions, run on import: $b") ;;
			VAR) swarn+=("$base:$a: global variable: $b (\"Global variables\" are forbidden)") ;;
			BAD) bad+=("$b (line $a)") ;;
			IMPORT)
				if [ "$d" = 0 ]; then bad+=("import $b (line $a): external library")
				else
					case ${b%%.*} in
						functools)
							if [ "$pol" = none ]; then bad+=("import functools (line $a): not authorized in this exercise")
							elif [ "$pol" = wraps ] && [ "$c" != - ]; then
								for x in ${c//,/ }; do
									[ "$x" = wraps ] || bad+=("from functools import $x (line $a): only functools.wraps is authorized")
								done
							fi ;;
						operator)
							[ "$pol" = all ] || bad+=("import operator (line $a): not authorized in this exercise") ;;
						typing)
							[[ ",$c," == *,Callable,* ]] && hwarn+=("$base:$a: Callable imported from typing (subject: \"When using Callable as a type hint, use collections.abc\")") ;;
					esac
				fi ;;
			ATTR)
				case $b in
					functools.wraps) ;;
					functools.*) [ "$pol" = wraps ] && bad+=("$b (line $a): only functools.wraps is authorized") ;;
					typing.Callable) hwarn+=("$base:$a: typing.Callable (subject: \"When using Callable as a type hint, use collections.abc\")") ;;
				esac ;;
			HINT) hko+=("$base:$a: $b(): no type hint for $c") ;;
			NHINT) hwarn+=("$base:$a: $b(): no type hint for $c") ;;
		esac
	done < <(python3 -I "$PT" info "$WORK/$ex/$base")
	for x in "$@"; do
		[[ "$DEFS" == *" $x "* ]] && continue
		if [[ $x == *.* ]]; then struct+=("$base: no method ${x#*.}() in class ${x%%.*} (the name must match exactly)")
		elif [[ $x == [A-Z]* ]]; then struct+=("$base: no class $x (the name must match exactly)")
		else struct+=("$base: no function $x() (the name must match exactly)"); fi
	done
	if [ ${#struct[@]} -gt 0 ]; then
		line_ko "structure"; for m in "${struct[@]}"; do msg "$m"; done
		for m in "${swarn[@]:0:2}"; do note "$m"; done
	elif [ ${#swarn[@]} -gt 0 ]; then
		line_warn "structure" "${swarn[0]}"
		for m in "${swarn[@]:1:2}"; do note "$m"; done
		note "(put the demonstration in functions / under if __name__ == \"__main__\":)"
	else
		line_ok "structure" "($# names found)"
	fi
	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized"
	else
		line_ko "authorized"
		for m in "${bad[@]:0:6}"; do msg "forbidden: $m"; done
		case $pol in
			none) note "functools and operator are not authorized in this exercise; eval(), exec(), file I/O, global variables and external libraries never are" ;;
			wraps) note "only functools.wraps (and staticmethod) here; eval(), exec(), file I/O, global variables and external libraries are forbidden" ;;
			*) note "eval(), exec(), file I/O, global variables and external libraries are forbidden" ;;
		esac
	fi
	if [ ${#hko[@]} -gt 0 ]; then
		line_ko "type hints"; for m in "${hko[@]:0:6}"; do msg "$m"; done
		note "subject: \"Use type hints for all function signatures and return types\""
	elif [ ${#hwarn[@]} -gt 0 ]; then
		line_warn "type hints" "${hwarn[0]}"
		for m in "${hwarn[@]:1:3}"; do note "$m"; done
	else
		line_ok "type hints"
	fi
}

# has <list ",a,b,"> <name>: the name is in the list
has() { [[ $1 == *",$2,"* ]]; }

# demo_line <exercise dir> <file> <words...>
# Runs the program like the subject does: it must work and print a demonstration
# (warning when one of the words of the subject's example output is missing).
demo_line() {
	local ex=$1 f=$2 k miss=()
	shift 2
	t_begin
	run_script "$ex" "$f"
	T_N=1
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		t_fail "python3 $f: infinite loop or too slow (more than 10 s)"
	elif [ $RC -ne 0 ]; then
		t_fail "python3 $f exits with status $RC: $(grep -E '^[A-Za-z]*(Error|Exception)' "$TMP/err" | tail -1 | cut -c1-100)"
	elif [ ! -s "$TMP/out" ]; then
		t_fail "python3 $f prints nothing; expected a demonstration (see the subject's example output)"
	else
		for k in "$@"; do grep -qiF -- "$k" "$TMP/out" || miss+=("\"$k\""); done
		[ ${#miss[@]} -gt 0 ] && T_WARNS+=("python3 $f: no ${miss[*]} in the output (compare with the subject's example output)")
		T_INFO="(python3 $f: $(wc -l < "$TMP/out") lines printed)"
	fi
	t_end "program"
}

# ================================ Exercises ================================= #

# ----------------------------- ex0: lambda spells --------------------------- #
if wanted 0; then
	section "ex0 - lambda_spells"
	if ex_files ex0 lambda_spells.py; then
		F="$WORK/ex0/lambda_spells.py"
		flake8_line ex0/lambda_spells.py
		fp_static ex0 lambda_spells.py none artifact_sorter power_filter spell_transformer mage_stats
		mypy_line ex0/lambda_spells.py

		# lambdas: each function uses its builtin with a lambda, no def inside
		t_begin
		for x in artifact_sorter:sorted power_filter:filter spell_transformer:map mage_stats:max,min; do
			fn=${x%%:*}
			[ -n "${FN_LAM[$fn]+set}" ] || continue
			T_N=$((T_N + 1))
			[ "${FN_LAM[$fn]}" -gt 0 ] || t_fail "$fn(): no lambda (subject: \"you must use lambda expressions for all transformations\")"
			need=${x#*:}
			for c in ${need//,/ }; do
				has "${FN_CALLS[$fn]}" "$c" || t_fail "$fn(): $c() is not used (subject: use $c() with a lambda)"
			done
			[ "${FN_NESTED[$fn]}" = - ] || t_fail "$fn(): nested function(s) defined with def: ${FN_NESTED[$fn]//,/, } (use lambdas)"
			[ "${FN_LOOPS[$fn]}" -gt 0 ] && T_WARNS+=("$fn(): uses a loop or a comprehension, the subject wants map / filter / sorted / min / max with lambdas")
		done
		for d in $DEFS; do
			case $d in
				artifact_sorter|power_filter|spell_transformer|mage_stats|main|*.*) ;;
				*) T_WARNS+=("extra function $d() defined with def: \"Do not use the 'def' keyword to create named functions for simple operations\"") ;;
			esac
		done
		t_end "lambdas"

		if import_ok "$F"; then
			# ---- artifact_sorter
			py_code <<'EOF'
def art(name, power, kind="relic"):
    return {"name": name, "power": power, "type": kind}


def names(lst):
    try:
        return short("[" + ", ".join("%s (%s)" % (x["name"], x["power"])
                                     for x in lst) + "]", 90)
    except Exception:
        return R(lst)


cases = [
    [art("Crystal Orb", 85, "orb"), art("Fire Staff", 92, "staff")],
    [],
    [art("Lone Wand", 10)],
    [art("A", 1), art("B", 2), art("C", 3), art("D", 4)],
    [art("D", 4), art("C", 3), art("B", 2), art("A", 1)],
    [art("X", 50), art("Y", 50), art("Z", 50)],
    [art("Tie 1", 30), art("Big", 99), art("Tie 2", 30), art("Low", 1)],
    [art("Neg", -5), art("Zero", 0), art("Huge", 10 ** 12), art("Mid", 7)],
    [art("Ring %d" % i, (i * 37) % 101) for i in range(60)],
]
for arts in cases:
    what = "artifact_sorter(%s)" % names(arts)
    before = copy.deepcopy(arts)
    exp = sorted(before, key=lambda a: a["power"], reverse=True)
    count()
    r, _, e = cap(m.artifact_sorter, arts)
    if e is not None:
        fail("%s raises %s" % (what, summary(e)))
        continue
    if arts != before:
        fail("%s modifies the list it receives (sorted() returns a new list)" % what)
    if not isinstance(r, list):
        fail("%s returned %s; expected a list" % (what, R(r)))
    elif r != exp:
        try:
            same = sorted(map(repr, r)) == sorted(map(repr, before))
            same = same and all(r[i]["power"] >= r[i + 1]["power"]
                                for i in range(len(r) - 1))
        except Exception:
            same = False
        if not same:
            fail("%s returned %s; expected %s (power descending)"
                 % (what, names(r), names(exp)))
EOF
			t_begin
			t_py "$F" "artifact_sorter()" "$CODE"
			t_end "artifact_sorter"

			# ---- power_filter
			py_code <<'EOF'
def mage(name, power, element):
    return {"name": name, "power": power, "element": element}


mages = [mage("Alex", 50, "fire"), mage("Jordan", 30, "ice"),
         mage("Riley", 80, "lightning"), mage("Sam", 30, "earth"),
         mage("Kai", 0, "water")]
solo = mage("Solo", 10, "air")


def names(lst):
    try:
        return short("[" + ", ".join("%s (%s)" % (x["name"], x["power"])
                                     for x in lst) + "]", 90)
    except Exception:
        return R(lst)


for lst, mp in [(mages, p) for p in (0, 1, 29, 30, 31, 50, 79, 80, 81, 1000, -10)] \
        + [([], 10), ([solo], 10), ([solo], 11)]:
    before = copy.deepcopy(lst)
    exp = [x for x in before if x["power"] >= mp]
    what = "power_filter(%s, %d)" % (names(lst), mp)
    count()
    r, _, e = cap(m.power_filter, lst, mp)
    if e is not None:
        fail("%s raises %s; expected %s" % (what, summary(e), names(exp)))
    elif not isinstance(r, list):
        fail("%s returned %s; expected a list %s" % (what, R(r), names(exp)))
        break
    elif r != exp:
        fail("%s returned %s; expected %s (power >= min_power, same order)"
             % (what, names(r), names(exp)))
    if lst != before:
        fail("%s modifies the list it receives" % what)
        break
EOF
			t_begin
			t_py "$F" "power_filter()" "$CODE"
			T_NOTE="power >= min_power, list returned"
			t_end "power_filter"

			# ---- spell_transformer
			py_code <<'EOF'
for spells in (["fireball", "heal", "shield"], [], ["x"],
               ["Lightning Bolt", "ice-storm"], ["", " "], ["éclair ⚡", "火球"],
               ["* star *"], ["heal"] * 50):
    expect("spell_transformer(%s)" % R(spells), m.spell_transformer,
           (list(spells),), ["* " + s + " *" for s in spells])
EOF
			t_begin
			t_py "$F" "spell_transformer()" "$CODE"
			T_NOTE='"* " + name + " *"'
			t_end "spell_transformer"

			# ---- mage_stats
			py_code <<'EOF'
cases = [[10, 20, 30], [85, 92], [7], [10, 20, 25], [1, 2, 2], [100, 0, 0],
         [-5, 5], [3, 3, 3, 3], [1, 1, 2], [99, 1, 50, 50], [2, 3],
         [-10, -20, -35], [10 ** 9, 1], [0, 0]]
for powers in cases:
    mages = [{"name": "Mage%d" % i, "power": p, "element": "fire"}
             for i, p in enumerate(powers)]
    what = "mage_stats(<mages with powers %s>)" % powers
    exp = {"max_power": max(powers), "min_power": min(powers),
           "avg_power": round(sum(powers) / len(powers), 2)}
    count()
    r, _, e = cap(m.mage_stats, mages)
    if e is not None:
        fail("%s raises %s; expected %s" % (what, summary(e), R(exp, 100)))
        continue
    if not isinstance(r, dict):
        fail("%s returned %s; expected a dict %s" % (what, R(r), R(exp, 100)))
        continue
    ok = all(type(r.get(k)) is int and r.get(k) == exp[k]
             for k in ("max_power", "min_power"))
    a = r.get("avg_power")
    ok = ok and isinstance(a, float) and abs(a - exp["avg_power"]) < 1e-9
    if not ok:
        fail("%s returned %s; expected %s" % (what, R(r, 100), R(exp, 100)))
    elif set(r) != set(exp):
        warn("%s returned extra keys: %s" % (what, R(r, 100)))
count()
r, _, e = cap(m.mage_stats, [])
if e is not None:
    warn("mage_stats([]) raises %s: the subject does not say what an empty "
         "list gives, be ready to explain your choice" % summary(e))
EOF
			t_begin
			t_py "$F" "mage_stats()" "$CODE"
			T_NOTE="max, min, average rounded to 2 decimals"
			t_end "mage_stats"
		fi
		demo_line ex0 lambda_spells.py "artifact sorter" "comes before" "spell transformer"
	fi
fi

# ----------------------------- ex1: higher magic ---------------------------- #
# Spells used by the tests: they log their calls in LOG
SPELLS_PY='
LOG = []


def make_spell(name):
    def spell(target, power):
        LOG.append((name, target, power))
        return "%s:%s:%s" % (name, target, power)
    spell.__name__ = name
    return spell


fireball, heal, shield = make_spell("fireball"), make_spell("heal"), make_spell("shield")


def res(name, target, power):
    return "%s:%s:%s" % (name, target, power)


def got_function(what, r, e):
    count()
    if e is not None:
        fail("%s raises %s" % (what, summary(e)))
    elif not callable(r):
        fail("%s returned %s; expected a function" % (what, R(r)))
    else:
        return True
    return False

'

if wanted 1; then
	section "ex1 - higher_magic"
	if ex_files ex1 higher_magic.py; then
		F="$WORK/ex1/higher_magic.py"
		flake8_line ex1/higher_magic.py
		fp_static ex1 higher_magic.py none spell_combiner power_amplifier conditional_caster spell_sequence
		mypy_line ex1/higher_magic.py

		if import_ok "$F"; then
			# ---- spell_combiner
			py_code <<'EOF'
f = m.spell_combiner
r, _, e = cap(f, fireball, heal)
if got_function("spell_combiner(fireball, heal)", r, e):
    if LOG:
        fail("spell_combiner(fireball, heal) already casts the spells (they must "
             "be cast only when the combined spell is called)")
    for t, p in (("Dragon", 10), ("Goblin", 0), ("", -5), ("Ancient Lich", 999999)):
        LOG.clear()
        if expect("spell_combiner(fireball, heal)(%r, %r)" % (t, p), r, (t, p),
                  (res("fireball", t, p), res("heal", t, p))):
            count()
            if LOG != [("fireball", t, p), ("heal", t, p)]:
                fail("spell_combiner(fireball, heal)(%r, %r) casts %s; expected "
                     "fireball then heal, once each, with the same arguments"
                     % (t, p, R(LOG, 120)))
    c2, _, e = cap(f, shield, fireball)
    if got_function("spell_combiner(shield, fireball)", c2, e):
        expect("spell_combiner(shield, fireball)('Orc', 3)", c2, ("Orc", 3),
               (res("shield", "Orc", 3), res("fireball", "Orc", 3)))
        expect("spell_combiner(fireball, heal)('Orc', 3) (after creating "
               "another combined spell)", r, ("Orc", 3),
               (res("fireball", "Orc", 3), res("heal", "Orc", 3)))
        nested, _, e = cap(f, r, shield)
        if got_function("spell_combiner(combined, shield)", nested, e):
            expect("spell_combiner(spell_combiner(fireball, heal), shield)('Imp', 1)",
                   nested, ("Imp", 1), ((res("fireball", "Imp", 1),
                                         res("heal", "Imp", 1)), res("shield", "Imp", 1)))
    nums, _, e = cap(f, lambda t, p: p * 2, lambda t, p: len(t))
    if got_function("spell_combiner(<lambda t, p: p * 2>, <lambda t, p: len(t)>)", nums, e):
        expect("spell_combiner(<lambda t, p: p * 2>, <lambda t, p: len(t)>)"
               "('abc', 21)", nums, ("abc", 21), (42, 3))
EOF
			t_begin
			t_py "$F" "spell_combiner()" "$SPELLS_PY$CODE"
			T_NOTE="tuple of both results"
			t_end "spell_combiner"

			# ---- power_amplifier
			py_code <<'EOF'
f = m.power_amplifier
for mult, p in ((3, 10), (1, 7), (0, 50), (2, 0), (10, -4), (-1, 5), (1000, 1000)):
    LOG.clear()
    amp, _, e = cap(f, fireball, mult)
    if not got_function("power_amplifier(fireball, %d)" % mult, amp, e):
        break
    if LOG:
        fail("power_amplifier(fireball, %d) already casts the spell" % mult)
    if expect("power_amplifier(fireball, %d)('Dragon', %d)" % (mult, p), amp,
              ("Dragon", p), res("fireball", "Dragon", p * mult)):
        count()
        if LOG != [("fireball", "Dragon", p * mult)]:
            fail("power_amplifier(fireball, %d)('Dragon', %d) casts %s; expected "
                 "fireball once with ('Dragon', %d)" % (mult, p, R(LOG, 100), p * mult))
else:
    double, _, e = cap(f, heal, 2)
    triple, _, e2 = cap(f, heal, 3)
    if got_function("power_amplifier(heal, 2)", double, e) \
            and got_function("power_amplifier(heal, 3)", triple, e2):
        expect("power_amplifier(heal, 2)('Elf', 4) (after power_amplifier(heal, 3))",
               double, ("Elf", 4), res("heal", "Elf", 8))
        expect("power_amplifier(heal, 3)('Elf', 4)", triple, ("Elf", 4),
               res("heal", "Elf", 12))
        expect("heal('Elf', 4) (the original spell must not change)", heal,
               ("Elf", 4), res("heal", "Elf", 4))
        both, _, e = cap(f, double, 3)
        if got_function("power_amplifier(power_amplifier(heal, 2), 3)", both, e):
            expect("power_amplifier(power_amplifier(heal, 2), 3)('Elf', 5)", both,
                   ("Elf", 5), res("heal", "Elf", 30))
    dmg, _, e = cap(f, lambda t, p: p, 3)
    if got_function("power_amplifier(<lambda t, p: p>, 3)", dmg, e):
        expect("power_amplifier(<lambda t, p: p>, 3)('x', 10) (subject: "
               "Original: 10, Amplified: 30)", dmg, ("x", 10), 30)
EOF
			t_begin
			t_py "$F" "power_amplifier()" "$SPELLS_PY$CODE"
			T_NOTE="power multiplied before casting"
			t_end "power_amplifier"

			# ---- conditional_caster
			py_code <<'EOF'
f = m.conditional_caster
CLOG = []


def strong(target, power):
    CLOG.append((target, power))
    return power >= 10


c, _, e = cap(f, strong, fireball)
if got_function("conditional_caster(<power >= 10>, fireball)", c, e):
    if LOG or CLOG:
        fail("conditional_caster(<power >= 10>, fireball) already calls the "
             "condition or the spell")
    for t, p in (("Dragon", 15), ("Dragon", 10), ("Dragon", 9), ("Imp", -1),
                 ("Titan", 10 ** 6), ("Dragon", 0)):
        LOG.clear()
        CLOG.clear()
        exp = res("fireball", t, p) if p >= 10 else "Spell fizzled"
        what = "conditional_caster(<power >= 10>, fireball)(%r, %d)" % (t, p)
        if expect(what, c, (t, p), exp):
            count()
            if CLOG != [(t, p)]:
                fail("%s: the condition receives %s; expected one call with (%r, %d)"
                     % (what, R(CLOG), t, p))
            elif p < 10 and LOG:
                fail("%s: the spell is cast although the condition is False" % what)
    by_name, _, e = cap(f, lambda t, p: t.startswith("Dra"), heal)
    if got_function("conditional_caster(<target starts with Dra>, heal)", by_name, e):
        expect("conditional_caster(<target starts with Dra>, heal)('Dragon', 1)",
               by_name, ("Dragon", 1), res("heal", "Dragon", 1))
        expect("conditional_caster(<target starts with Dra>, heal)('Orc', 99)",
               by_name, ("Orc", 99), "Spell fizzled")
    yes, _, e = cap(f, lambda t, p: True, shield)
    no, _, e2 = cap(f, lambda t, p: False, shield)
    if got_function("conditional_caster(<always True>, shield)", yes, e) \
            and got_function("conditional_caster(<always False>, shield)", no, e2):
        expect("conditional_caster(<always True>, shield)('Knight', 0)", yes,
               ("Knight", 0), res("shield", "Knight", 0))
        expect("conditional_caster(<always False>, shield)('Knight', 50)", no,
               ("Knight", 50), "Spell fizzled")
EOF
			t_begin
			t_py "$F" "conditional_caster()" "$SPELLS_PY$CODE"
			T_NOTE='"Spell fizzled" when the condition fails'
			t_end "conditional_caster"

			# ---- spell_sequence
			py_code <<'EOF'
f = m.spell_sequence
for names in (["fireball", "heal", "shield"], [], ["fireball"], ["heal", "heal"],
              ["shield", "fireball", "heal", "fireball"]):
    spells = [globals()[n] for n in names]
    LOG.clear()
    what = "spell_sequence([%s])" % ", ".join(names)
    seq, _, e = cap(f, spells)
    if not got_function(what, seq, e):
        break
    if LOG:
        fail("%s already casts the spells" % what)
    for t, p in (("Dragon", 10), ("Goblin", -3)):
        LOG.clear()
        if expect("%s(%r, %d)" % (what, t, p), seq, (t, p),
                  [res(n, t, p) for n in names]):
            count()
            if LOG != [(n, t, p) for n in names]:
                fail("%s(%r, %d) casts %s; expected each spell once, in order"
                     % (what, t, p, R(LOG, 100)))
EOF
			t_begin
			t_py "$F" "spell_sequence()" "$SPELLS_PY$CODE"
			T_NOTE="list of results, in order"
			t_end "spell_sequence"
		fi
		demo_line ex1 higher_magic.py "spell combiner" "power amplifier"
		miss=()
		for fn in spell_combiner power_amplifier conditional_caster spell_sequence; do
			[[ "$DEFS" == *" $fn "* ]] && [[ "$USED" != *" $fn "* ]] && miss+=("$fn()")
		done
		if [ ${#miss[@]} -gt 0 ]; then
			line_warn "demonstration" "never used in the program: ${miss[*]}"
			note "subject: \"Your program must demonstrate use and efficiency of all your spells modifiers functions\""
		fi
	fi
fi

# ---------------------------- ex2: scope mysteries -------------------------- #
CLOSURE_PY='
def got_closure(what, r, e):
    count()
    if e is not None:
        fail("%s raises %s" % (what, summary(e)))
    elif not callable(r):
        fail("%s returned %s; expected a function" % (what, R(r)))
    elif getattr(r, "__closure__", None) is None:
        fail("%s returned a function without closure (__closure__ is None): "
             "keep the state in the enclosing function (nonlocal)" % what)
    else:
        return True
    return False

'

if wanted 2; then
	section "ex2 - scope_mysteries"
	if ex_files ex2 scope_mysteries.py; then
		F="$WORK/ex2/scope_mysteries.py"
		flake8_line ex2/scope_mysteries.py
		fp_static ex2 scope_mysteries.py none mage_counter spell_accumulator enchantment_factory memory_vault
		mypy_line ex2/scope_mysteries.py

		if import_ok "$F"; then
			# ---- mage_counter
			py_code <<'EOF'
f = m.mage_counter
made = {}
calls = {}
steps = ([("a", 1), ("a", 2), ("new", "b"), ("b", 1), ("a", 3), ("b", 2),
          ("b", 3), ("a", 4), ("new", "c")] + [("c", i) for i in range(1, 101)]
         + [("a", 5), ("b", 4)])
errors = 0
for name, exp in steps:
    if name == "new" or not made:
        key = exp if name == "new" else "a"
        r, _, e = cap(f)
        if not got_closure("mage_counter()", r, e):
            break
        made[key], calls[key] = r, 0
        if name == "new":
            continue
    calls[name] += 1
    count()
    r, _, e = cap(made[name])
    what = ("counter_%s() (call %d; counters a, b, c are made by mage_counter() "
            "in turn)" % (name, calls[name]))
    if e is not None:
        fail("%s raises %s; expected %d" % (what, summary(e), exp))
    elif r != exp or type(r) is not int:
        fail("%s returned %s; expected %d" % (what, R(r), exp))
    else:
        continue
    errors += 1
    if errors >= 4:
        break
EOF
			t_begin
			t_py "$F" "mage_counter()" "$CLOSURE_PY$CODE"
			T_NOTE="independent counters"
			t_end "mage_counter"

			# ---- spell_accumulator
			py_code <<'EOF'
f = m.spell_accumulator
made = {}
steps = [("new", "a", 100), ("a", 20, 120), ("a", 30, 150),
         ("new", "b", 0), ("b", 5, 5), ("a", 0, 150), ("b", -10, -5),
         ("new", "c", 100), ("c", 1, 101), ("a", 1, 151),
         ("new", "d", -50), ("d", 50, 0), ("d", 0, 0),
         ("new", "e", 10 ** 18), ("e", 10 ** 18, 2 * 10 ** 18),
         ("b", 1000, 995)]
errors = 0
for name, x, exp in steps:
    if name == "new":
        r, _, e = cap(f, exp)
        if not got_closure("spell_accumulator(%d)" % exp, r, e):
            break
        made[x] = (r, exp)
        continue
    acc, start = made[name]
    count()
    what = "acc_%s(%d) (acc_%s = spell_accumulator(%d))" % (name, x, name, start)
    r, _, e = cap(acc, x)
    if e is not None:
        fail("%s raises %s; expected %d" % (what, summary(e), exp))
    elif r != exp or type(r) is not int:
        fail("%s returned %s; expected %d" % (what, R(r), exp))
    else:
        continue
    errors += 1
    if errors >= 4:
        break
EOF
			t_begin
			t_py "$F" "spell_accumulator()" "$CLOSURE_PY$CODE"
			T_NOTE="running total, independent accumulators"
			t_end "spell_accumulator"

			# ---- enchantment_factory
			py_code <<'EOF'
f = m.enchantment_factory
made = {}
for kind in ("Flaming", "Frozen", "Thundering", "Shadow"):
    r, _, e = cap(f, kind)
    if got_closure("enchantment_factory(%r)" % kind, r, e):
        made[kind] = r
for kind, item in (("Flaming", "Sword"), ("Frozen", "Shield"),
                   ("Thundering", "Hammer of Doom"), ("Shadow", "Bow"),
                   ("Flaming", "Axe"), ("Frozen", "Axe"), ("Flaming", "Sword")):
    if kind in made:
        expect("enchantment_factory(%r)(%r)" % (kind, item), made[kind], (item,),
               kind + " " + item)
EOF
			t_begin
			t_py "$F" "enchantment_factory()" "$CLOSURE_PY$CODE"
			T_NOTE='"Flaming Sword", independent factories'
			t_end "enchantment_factory"

			# the text is kept as it is (no capital letter added)
			py_code <<'EOF'
for kind, item in (("flaming", "sword"), ("Éthéré", "bâton"), ("Holy", "")):
    count()
    r, _, e = cap(lambda: m.enchantment_factory(kind)(item))
    if e is not None or r != kind + " " + item:
        warn("enchantment_factory(%r)(%r) gives %s; with the format "
             "\"enchantment_type item_name\", expected %r"
             % (kind, item, summary(e) if e else R(r), kind + " " + item))
EOF
			t_begin
			t_py "$F" "enchantment_factory()" "$CODE"
			t_end "enchant. format"

			# ---- memory_vault
			py_code <<'EOF'
f = m.memory_vault


def vault(what):
    count()
    v, _, e = cap(f)
    if e is not None:
        fail("%s raises %s" % (what, summary(e)))
    elif not isinstance(v, dict):
        fail("%s returned %s; expected a dict {'store': ..., 'recall': ...}"
             % (what, R(v)))
    elif not callable(v.get("store")) or not callable(v.get("recall")):
        fail("%s returned %s; expected the keys 'store' and 'recall' with functions"
             % (what, R(v, 100)))
    else:
        for k in ("store", "recall"):
            got_closure("%s['%s']" % (what, k), v[k], None)
        return v
    return None


v = vault("memory_vault()")
v2 = v and vault("memory_vault() (a second vault)")
if v and v2:
    st, rc = v["store"], v["recall"]
    expect("recall('secret') before any store()", rc, ("secret",), "Memory not found")
    for key, value in (("secret", 42), ("name", "Merlin"), ("list", [1, 2, 3]),
                       ("zero", 0), ("empty", ""), ("false", False)):
        count()
        _, _, e = cap(st, key, value)
        if e is not None:
            fail("store(%r, %r) raises %s" % (key, value, summary(e)))
            continue
        expect("recall(%r) after store(%r, %r)" % (key, key, value), rc, (key,), value)
    expect("recall('unknown')", rc, ("unknown",), "Memory not found")
    expect("recall('Secret') (keys are case sensitive)", rc, ("Secret",),
           "Memory not found")
    cap(st, "secret", "new")
    expect("recall('secret') after store('secret', 'new') (overwrite)", rc,
           ("secret",), "new")
    expect("vault2['recall']('secret') (vault2 = another memory_vault(): its "
           "memory must be private)", v2["recall"], ("secret",), "Memory not found")
    cap(v2["store"], "secret", 7)
    expect("vault2['recall']('secret') after vault2['store']('secret', 7)",
           v2["recall"], ("secret",), 7)
    expect("vault1['recall']('secret') after vault2['store']('secret', 7)", rc,
           ("secret",), "new")
    cap(st, "nothing", None)
    count()
    r, _, e = cap(rc, "nothing")
    if e is not None or r is not None:
        warn("recall('nothing') after store('nothing', None) gives %s; the stored "
             "value is None" % (summary(e) if e else R(r)))
EOF
			t_begin
			t_py "$F" "memory_vault()" "$CLOSURE_PY$CODE"
			T_NOTE='store / recall, "Memory not found", private memory'
			t_end "memory_vault"
		fi
		demo_line ex2 scope_mysteries.py "mage counter" "spell accumulator" "enchantment factory" "memory vault" "Memory not found"
	fi
fi

# --------------------------- ex3: functools artifacts ----------------------- #
if wanted 3; then
	section "ex3 - functools_artifacts"
	if ex_files ex3 functools_artifacts.py; then
		F="$WORK/ex3/functools_artifacts.py"
		flake8_line ex3/functools_artifacts.py
		fp_static ex3 functools_artifacts.py all spell_reducer partial_enchanter memoized_fibonacci spell_dispatcher
		mypy_line ex3/functools_artifacts.py

		# functools / operator tools required by the subject
		t_begin
		if [ -n "${FN_REFS[spell_reducer]+set}" ]; then
			T_N=$((T_N + 2))
			has "${FN_REFS[spell_reducer]}" reduce || t_fail "spell_reducer(): functools.reduce is not used"
			has "${FN_REFS[spell_reducer]}" operator || has "${FN_REFS[spell_reducer]}" add \
				|| has "${FN_REFS[spell_reducer]}" mul \
				|| t_fail "spell_reducer(): no operator function (operator.add, operator.mul, ...) is used"
		fi
		if [ -n "${FN_REFS[partial_enchanter]+set}" ]; then
			T_N=$((T_N + 1))
			has "${FN_REFS[partial_enchanter]}" partial || t_fail "partial_enchanter(): functools.partial is not used"
		fi
		if [ -n "${FN_REFS[memoized_fibonacci]+set}" ]; then
			T_N=$((T_N + 1))
			case ${FN_DECO[memoized_fibonacci]} in
				*lru_cache*) ;;
				*cache*) T_WARNS+=("memoized_fibonacci(): decorated with @cache; the subject asks for functools.lru_cache") ;;
				*) t_fail "memoized_fibonacci(): not decorated with @functools.lru_cache" ;;
			esac
		fi
		if [ -n "${FN_REFS[spell_dispatcher]+set}" ]; then
			T_N=$((T_N + 1))
			has "${FN_REFS[spell_dispatcher]}" singledispatch || t_fail "spell_dispatcher(): functools.singledispatch is not used"
		fi
		t_end "functools tools"

		if import_ok "$F"; then
			# ---- spell_reducer
			py_code <<'EOF'
f = m.spell_reducer
cases = [([10, 20, 30, 40], {"add": 100, "multiply": 240000, "max": 40, "min": 10}),
         ([7], {"add": 7, "multiply": 7, "max": 7, "min": 7}),
         ([-3, 5, -2], {"add": 0, "multiply": 30, "max": 5, "min": -3}),
         ([5, 0, 3], {"add": 8, "multiply": 0, "max": 5, "min": 0}),
         ([2 ** 40, 2 ** 40], {"add": 2 ** 41, "multiply": 2 ** 80,
                               "max": 2 ** 40, "min": 2 ** 40}),
         ([1] * 100, {"add": 100, "multiply": 1, "max": 1, "min": 1}),
         ([], {"add": 0, "multiply": 0, "max": 0, "min": 0})]
for spells, results in cases:
    for op, exp in results.items():
        expect("spell_reducer(%s, %r)" % (R(spells, 40), op), f,
               (list(spells), op), exp)
EOF
			t_begin
			t_py "$F" "spell_reducer()" "$CODE"
			T_NOTE='add, multiply, max, min, [] gives 0'
			t_end "spell_reducer"

			# unknown operation: "properly handle the error"
			py_code <<'EOF'
seen = []
for op in ("divide", "power", ""):
    count()
    r, out, e = cap(m.spell_reducer, [10, 20, 30], op)
    what = "spell_reducer([10, 20, 30], %r)" % op
    if e is None:
        seen.append("returns %s" % R(r, 40))
        continue
    seen.append("raises %s" % type(e).__name__)
    text = str(e).lower()
    deliberate = (isinstance(e, ValueError) or type(e).__module__ == m.__name__
                  or any(w in text for w in ("unknown", "invalid", "unsupported",
                                             "operation", "not supported"))
                  or (op and op in text and not isinstance(e, KeyError)))
    if isinstance(e, (TypeError, AttributeError, NameError, IndexError,
                      UnboundLocalError)) and not deliberate:
        fail("%s raises %s: the unknown operation is not handled (subject: "
             "\"If operation is unknown, properly handle the error\")"
             % (what, summary(e)))
    elif not deliberate:
        warn("%s raises %s: make sure this is a deliberate error for an unknown "
             "operation" % (what, summary(e)))
note(seen[0] if seen else "")
EOF
			t_begin
			t_py "$F" "spell_reducer()" "$CODE"
			t_end "unknown operation"

			# ---- partial_enchanter
			py_code <<'EOF'
f = m.partial_enchanter
CALLS = []


def base(power, element, target):
    CALLS.append((power, element, target))
    return "%s|%s|%s" % (power, element, target)


def cast(v, target):
    """Calls a version with the target (keyword if positional fails)."""
    r, _, e = cap(v, target)
    if isinstance(e, TypeError):
        r2, _, e2 = cap(v, target=target)
        if e2 is None:
            return r2, None
    return r, e


count()
r, _, e = cap(f, base)
if e is not None:
    fail("partial_enchanter(base) raises %s" % summary(e))
elif not isinstance(r, dict):
    fail("partial_enchanter(base) returned %s; expected a dict of 3 functions" % R(r))
elif CALLS:
    fail("partial_enchanter(base) already calls the base enchantment")
else:
    funcs = {k: v for k, v in r.items() if callable(v)}
    count()
    if len(funcs) < 3:
        fail("partial_enchanter(base) returned %d function(s): %s; expected 3 "
             "specialized versions" % (len(funcs), R(r, 100)))
    elif len(r) > 3:
        warn("partial_enchanter(base) returned %d entries; the subject asks for 3 "
             "specialized versions" % len(r))
    elements = []
    for k, v in funcs.items():
        if not isinstance(v, functools.partial):
            warn("partial_enchanter(base)[%r] is not a functools.partial object" % k)
        for target in ("Dragon", "Goblin King"):
            count()
            CALLS.clear()
            got, e = cast(v, target)
            what = "partial_enchanter(base)[%r](%r)" % (k, target)
            if e is not None:
                fail("%s raises %s" % (what, summary(e)))
                break
            if len(CALLS) != 1:
                fail("%s calls base %d times; expected once" % (what, len(CALLS)))
                break
            power, element, t = CALLS[0]
            if power != 50 or not isinstance(element, str) or not element \
                    or t != target:
                fail("%s calls base(power=%s, element=%s, target=%s); expected "
                     "base(power=50, element=<an element>, target=%r)"
                     % (what, R(power), R(element), R(t), target))
                break
            if got != base(power, element, t):
                fail("%s returned %s; expected the result of base(): %s"
                     % (what, R(got), R(base(power, element, t))))
                break
        else:
            elements.append(CALLS[0][1] if CALLS else None)
    if len(elements) == len(funcs) >= 3 and len(set(elements)) < len(elements):
        warn("the specialized versions do not have different elements: %s" % elements)
    if elements:
        note("elements: %s" % ", ".join(map(str, elements)))
    upper, _, e = cap(f, lambda power, element, target: (target, element, power))
    if e is None and isinstance(upper, dict) and upper:
        k, v = next(iter(upper.items()))
        count()
        got, e = cast(v, "Orc")
        if e is not None or not isinstance(got, tuple) or got[0] != "Orc" \
                or got[2] != 50:
            fail("partial_enchanter(<another base>)[%r]('Orc') gives %s: each "
                 "call must use the base enchantment it receives"
                 % (k, summary(e) if e else R(got)))
EOF
			t_begin
			t_py "$F" "partial_enchanter()" "$CODE"
			t_end "partial_enchanter"

			# ---- memoized_fibonacci
			py_code <<'EOF'
f = m.memoized_fibonacci
count()
if not hasattr(f, "cache_info"):
    fail("memoized_fibonacci has no cache_info(): it must be decorated with "
         "@functools.lru_cache (subject: \"You can verify caching works via "
         "memoized_fibonacci.cache_info()\")")
fib = [0, 1]
while len(fib) < 301:
    fib.append(fib[-1] + fib[-2])
errors = 0
for n in list(range(31)) + [50, 90]:
    if not expect("memoized_fibonacci(%d)" % n, f, (n,), fib[n]):
        errors += 1
        if errors >= 4:
            break
if hasattr(f, "cache_info") and hasattr(f, "cache_clear"):
    count()
    f.cache_clear()
    cap(f, 20)
    i1 = f.cache_info()
    cap(f, 20)
    i2 = f.cache_info()
    if i2.hits <= i1.hits:
        fail("a second call memoized_fibonacci(20) is not a cache hit "
             "(cache_info() before: %s, after: %s)" % (i1, i2))
    else:
        note("cache hit on repeated calls")
expect("memoized_fibonacci(300) (with memoization it is instant)", f, (300,), fib[300])
EOF
			t_begin
			t_py "$F" "memoized_fibonacci()" "$CODE"
			t_end "memoized_fibonacci"

			# ---- spell_dispatcher
			py_code <<'EOF'
f = m.spell_dispatcher
count()
d, _, e = cap(f)
if e is not None:
    fail("spell_dispatcher() raises %s" % summary(e))
elif not callable(d):
    fail("spell_dispatcher() returned %s; expected the dispatcher function" % R(d))
else:
    if not hasattr(d, "registry") or not hasattr(d, "register"):
        fail("spell_dispatcher() returned a function that is not made with "
             "@functools.singledispatch (no .register / .registry)")
    else:
        for t in (int, str, list):
            count()
            if t not in d.registry:
                fail("spell_dispatcher(): no implementation registered for %s "
                     "(registered: %s)" % (t.__name__, ", ".join(
                         getattr(k, "__name__", str(k)) for k in d.registry)))

    def call(arg, desc=None):
        count()
        r, _, e = cap(d, arg)
        what = "dispatcher(%s)" % (desc or R(arg))
        if e is not None:
            fail("%s raises %s; expected a str" % (what, summary(e)))
        elif not isinstance(r, str):
            fail("%s returned %s; expected a str" % (what, R(r)))
        else:
            return r
        return None

    shown = []
    for n in (42, 0, -5, 1000000):
        r = call(n)
        if r is not None:
            if str(n) not in r:
                fail("dispatcher(%d) returned %r; expected a damage spell with %d "
                     "(subject: \"Damage spell: 42 damage\")" % (n, r, n))
            elif "damage" not in r.lower() and n == 42:
                warn("dispatcher(42) returned %r: no \"damage\" (subject: "
                     "\"Damage spell: 42 damage\")" % r)
            if n == 42:
                shown.append(r)
    for s in ("fireball", "Frost Nova", ""):
        r = call(s)
        if r is not None and s not in r:
            fail("dispatcher(%r) returned %r; expected an enchantment with %r "
                 "(subject: \"Enchantment: fireball\")" % (s, r, s))
        if r is not None and s == "fireball":
            shown.append(r)
    for spells in (["fireball", "heal", "shield"], ["a", "b", "c", "d", "e"], []):
        r = call(spells)
        if r is not None and str(len(spells)) not in r:
            msg = ("dispatcher(%s) returned %r; expected a multi-cast with %d "
                   "(subject: \"Multi-cast: 3 spells\")" % (R(spells), r, len(spells)))
            if spells:
                fail(msg)
            else:
                warn(msg)
        if r is not None and len(spells) == 3:
            shown.append(r)
    results = {}
    for arg, desc in ((3.14, None), (None, None), ({"a": 1}, None), ((1, 2), None),
                      (object(), "object()")):
        r = call(arg, desc)
        if r is not None:
            results[desc or R(arg)] = r
    for desc, r in results.items():
        if "unknown" not in r.lower():
            warn("dispatcher(%s) returned %r: no \"unknown\" (subject: \"Unknown "
                 "spell type\")" % (desc, r))
            break
    if results:
        shown.append(next(iter(results.values())))
    d2, _, e = cap(f)
    count()
    if e is not None or not callable(d2) or cap(d2, 42)[0] != cap(d, 42)[0]:
        fail("a second spell_dispatcher() does not give the same dispatcher")
    note(" / ".join(map(repr, shown)))
EOF
			t_begin
			t_py "$F" "spell_dispatcher()" "$CODE"
			t_end "spell_dispatcher"
		fi
		demo_line ex3 functools_artifacts.py "spell reducer" "fibonacci" "spell dispatcher"
	fi
fi

# --------------------------- ex4: decorator mastery ------------------------- #
if wanted 4; then
	section "ex4 - decorator_mastery"
	if ex_files ex4 decorator_mastery.py; then
		F="$WORK/ex4/decorator_mastery.py"
		flake8_line ex4/decorator_mastery.py
		fp_static ex4 decorator_mastery.py wraps spell_timer power_validator retry_spell MageGuild \
			MageGuild.validate_mage_name MageGuild.cast_spell
		mypy_line ex4/decorator_mastery.py

		# decorators required by the subject
		t_begin
		for fn in spell_timer power_validator; do
			[ -n "${FN_REFS[$fn]+set}" ] || continue
			T_N=$((T_N + 1))
			has "${FN_REFS[$fn]}" wraps || t_fail "$fn(): functools.wraps is not used (subject: \"Use functools.wraps\")"
		done
		if [ -n "${FN_REFS[retry_spell]+set}" ]; then
			has "${FN_REFS[retry_spell]}" wraps || T_WARNS+=("retry_spell(): functools.wraps is not used (the name and docstring of the spell are lost)")
		fi
		if [ -n "${FN_REFS[MageGuild.validate_mage_name]+set}" ]; then
			T_N=$((T_N + 1))
			[[ ${FN_DECO[MageGuild.validate_mage_name]} == *staticmethod* ]] \
				|| t_fail "MageGuild.validate_mage_name(): not decorated with @staticmethod"
		fi
		if [ -n "${FN_REFS[MageGuild.cast_spell]+set}" ]; then
			T_N=$((T_N + 1))
			deco=${FN_DECO[MageGuild.cast_spell]}
			if [[ $deco != *power_validator* ]]; then
				t_fail "MageGuild.cast_spell(): not decorated with @power_validator(min_power=10)"
			elif ! [[ $deco =~ power_validator\((min_power[[:space:]]*=[[:space:]]*)?10\) ]]; then
				t_fail "MageGuild.cast_spell(): decorated with @${deco%;}; expected @power_validator(min_power=10)"
			fi
		fi
		t_end "decorators"

		if import_ok "$F"; then
			# ---- spell_timer
			py_code <<'EOF'
pat = re.compile(r"Spell completed in (\d+\.\d{3}) seconds")


def my_spell_42(a, b=2, *, c=3):
    """Doc of my spell."""
    print("inside the spell")
    time.sleep(0.1)
    return (a, b, c)


def quick_spell():
    return None


count()
dec, out, e = cap(m.spell_timer, my_spell_42)
if e is not None:
    fail("spell_timer(my_spell_42) raises %s" % summary(e))
elif not callable(dec):
    fail("spell_timer(my_spell_42) returned %s; expected a function" % R(dec))
else:
    if out:
        fail("@spell_timer prints %r when it decorates (it must print only when "
             "the spell is cast)" % short(out, 60))
    count()
    if getattr(dec, "__name__", None) != "my_spell_42" \
            or getattr(dec, "__doc__", None) != "Doc of my spell." \
            or getattr(dec, "__wrapped__", None) is not my_spell_42:
        fail("spell_timer(my_spell_42): __name__ = %s, __doc__ = %s; expected "
             "'my_spell_42' and 'Doc of my spell.' (use functools.wraps)"
             % (R(getattr(dec, "__name__", None)), R(getattr(dec, "__doc__", None))))
    for args, kw, exp in (((1, 5), {"c": 9}, (1, 5, 9)), (("x",), {}, ("x", 2, 3))):
        count()
        what = "spell_timer(my_spell_42)(%s)" % ", ".join(
            [repr(a) for a in args] + ["%s=%r" % i for i in kw.items()])
        r, out, e = cap(dec, *args, **kw)
        lines = out.splitlines()
        if e is not None:
            fail("%s raises %s" % (what, summary(e)))
            break
        if r != exp:
            fail("%s returned %s; expected the spell's result %s" % (what, R(r), R(exp)))
        if "Casting my_spell_42..." not in lines:
            fail("%s prints %s; expected \"Casting my_spell_42...\" before the spell"
                 % (what, R(lines, 120)))
            break
        done = [x for x in lines if pat.fullmatch(x)]
        if not done:
            fail("%s prints %s; expected \"Spell completed in X.XXX seconds\" after "
                 "the spell (3 decimal places)" % (what, R(lines, 120)))
            break
        inside = lines.index("inside the spell") if "inside the spell" in lines else -1
        if lines.index("Casting my_spell_42...") > inside \
                or lines.index(done[0]) < inside:
            fail("%s prints %s; expected \"Casting ...\", then the spell, then "
                 "\"Spell completed ...\"" % (what, R(lines, 120)))
        secs = float(pat.fullmatch(done[0]).group(1))
        if not 0.099 <= secs <= 5:
            fail("%s prints %r; the spell sleeps 0.1 s" % (what, done[0]))
        if len(lines) != 3:
            warn("%s prints %s; expected only the 2 lines of the subject around the "
                 "spell's output" % (what, R(lines, 120)))
    q, _, e = cap(m.spell_timer, quick_spell)
    if e is None and callable(q):
        count()
        r, out, e = cap(q)
        lines = out.splitlines()
        if e is not None or r is not None or len(lines) != 2 \
                or lines[0] != "Casting quick_spell..." \
                or not pat.fullmatch(lines[1]) \
                or float(pat.fullmatch(lines[1]).group(1)) > 0.05:
            fail("spell_timer(quick_spell)() (returns None, no sleep) gives %s, "
                 "prints %s; expected None and \"Casting quick_spell...\", "
                 "\"Spell completed in 0.000 seconds\""
                 % (summary(e) if e else R(r), R(lines, 100)))
EOF
			t_begin
			t_py "$F" "spell_timer()" "$CODE"
			T_NOTE='"Casting ...", "Spell completed in X.XXX seconds", wraps'
			t_end "spell_timer"

			# ---- power_validator
			py_code <<'EOF'
LOG = []
INS = "Insufficient power for this spell"


def check_shape(shape):
    """Tests the decorator on a standalone function. Returns the failures."""
    errs = []

    if shape == "name_power":
        def cast(spell_name, power):
            """Cast doc."""
            LOG.append(power)
            return "cast %s %s" % (spell_name, power)
        desc = "cast(spell_name, power)"

        def call(f, p):
            return cap(f, "Bolt", p)
        fmt = "('Bolt', %d)"
    else:
        def cast(power):
            """Cast doc."""
            LOG.append(power)
            return "cast %s %s" % ("Bolt", power)
        desc = "cast(power)"

        def call(f, p):
            return cap(f, p)
        fmt = "(%d)"
    for mp in (10, 0, 50, -5):
        v, _, e = cap(m.power_validator, mp)
        if e is not None or not callable(v):
            errs.append("power_validator(%d) gives %s; expected a decorator"
                        % (mp, summary(e) if e else R(v)))
            break
        dec, _, e = cap(v, cast)
        what = "power_validator(%d)(%s)" % (mp, desc)
        if e is not None or not callable(dec):
            errs.append("%s gives %s; expected a function" % (what, summary(e) if e else R(dec)))
            break
        if getattr(dec, "__name__", None) != "cast" or dec.__doc__ != "Cast doc.":
            errs.append("%s: __name__ = %s, __doc__ = %s; expected 'cast', 'Cast doc.' "
                        "(use functools.wraps)" % (what, R(getattr(dec, "__name__", None)),
                                                   R(getattr(dec, "__doc__", None))))
        for p in sorted({mp - 1, mp, mp + 1, 0, 1000, -100}):
            LOG.clear()
            exp = "cast Bolt %d" % p if p >= mp else INS
            r, _, e = call(dec, p)
            call_s = what + fmt % p
            if e is not None:
                errs.append("%s raises %s; expected %r" % (call_s, summary(e), exp))
            elif r != exp:
                errs.append("%s returned %s; expected %r" % (call_s, R(r), exp))
            elif p < mp and LOG:
                errs.append("%s: the spell is cast although the power is too low" % call_s)
    return errs


errs = check_shape("name_power")
count(10)
if errs:
    other = check_shape("power")
    if other:
        for x in errs:
            fail(x)
    else:
        warn("power_validator works only on a function whose only argument is "
             "the power; it fails on %s" % errs[0])
EOF
			t_begin
			t_py "$F" "power_validator()" "$CODE"
			T_NOTE='power >= min_power, else "Insufficient power for this spell"'
			t_end "power_validator"

			# ---- retry_spell
			py_code <<'EOF'
line_re = re.compile(r"Spell failed, retrying\.\.\. \(attempt (\d+)/(\d+)\)")


class SpellError(Exception):
    pass


def flaky(n_fail, exc):
    state = {"calls": 0}

    def unstable_spell(*a, **k):
        """Flaky doc."""
        state["calls"] += 1
        if state["calls"] <= n_fail:
            raise exc("boom %d" % state["calls"])
        return ("ok", a, k)
    return unstable_spell, state


for mx, n_fail, exc in ((3, 0, RuntimeError), (3, 2, RuntimeError),
                        (3, 99, RuntimeError), (1, 99, ValueError), (1, 0, ValueError),
                        (5, 4, SpellError), (5, 99, SpellError), (2, 1, KeyError),
                        (4, 99, ZeroDivisionError)):
    spell, state = flaky(n_fail, exc)
    count()
    v, _, e = cap(m.retry_spell, mx)
    dec = None
    if e is None and callable(v):
        dec, _, e = cap(v, spell)
    if e is not None or not callable(dec):
        fail("retry_spell(%d)(spell) gives %s; expected a function"
             % (mx, summary(e) if e else R(dec)))
        break
    what = ("retry_spell(%d)(<spell failing %s>)(1, x=2)"
            % (mx, "%d time%s" % (n_fail, "s" * (n_fail > 1)) if n_fail < 99
               else "always"))
    r, out, e = cap(dec, 1, x=2)
    lines = out.splitlines()
    success = n_fail < mx
    exp_r = ("ok", (1,), {"x": 2}) if success else \
        "Spell casting failed after %d attempts" % mx
    if e is not None:
        fail("%s raises %s; expected %s" % (what, summary(e), R(exp_r)))
        continue
    if r != exp_r:
        if not success and r == "Spell casting failed after 1 attempt" and mx == 1:
            warn("%s returned %r; the subject's text gives \"... after 1 attempts\""
                 % (what, r))
        else:
            fail("%s returned %s; expected %s" % (what, R(r), R(exp_r)))
    bad = [x for x in lines if not line_re.fullmatch(x)]
    if bad:
        fail("%s prints %r; expected only \"Spell failed, retrying... "
             "(attempt n/%d)\" lines" % (what, bad[0], mx))
        continue
    got = [tuple(map(int, line_re.fullmatch(x).groups())) for x in lines]
    exp = [(i, mx) for i in range(1, min(n_fail, mx - 1) + 1)]
    if got != exp:
        if not success and got == exp + [(mx, mx)]:
            warn("%s also prints a retry message after the last attempt (%d/%d), "
                 "when nothing is retried (subject's example: 1/3, 2/3, then the "
                 "failure text)" % (what, mx, mx))
        else:
            fail("%s prints attempts %s; expected %s" % (
                what, ", ".join("%d/%d" % g for g in got) or "nothing",
                ", ".join("%d/%d" % g for g in exp) or "nothing"))
    exp_calls = min(n_fail + 1, mx)
    if state["calls"] != exp_calls:
        if not success and state["calls"] == mx + 1:
            warn("%s calls the spell %d times; \"Spell casting failed after %d "
                 "attempts\" means %d calls" % (what, mx + 1, mx, mx))
        else:
            fail("%s calls the spell %d times; expected %d"
                 % (what, state["calls"], exp_calls))
spell, _ = flaky(0, RuntimeError)
dec = m.retry_spell(3)(spell)
if getattr(dec, "__name__", None) != "unstable_spell":
    warn("retry_spell(3)(unstable_spell).__name__ is %s: use functools.wraps"
         % R(getattr(dec, "__name__", None)))
EOF
			t_begin
			t_py "$F" "retry_spell()" "$CODE"
			T_NOTE="retries, messages, final text"
			t_end "retry_spell"

			# ---- MageGuild
			py_code <<'EOF'
G = m.MageGuild
count()
if not isinstance(inspect.getattr_static(G, "validate_mage_name", None), staticmethod):
    fail("MageGuild.validate_mage_name is not a @staticmethod")
for name, exp in (("Gandalf", True), ("Bob", True), ("abc", True),
                  ("Merlin the Wise", True), ("Jordan Riley", True), ("ALEX", True),
                  ("Al", False), ("", False), ("X", False), ("R2D2", False),
                  ("Jean-Luc", False), ("Gandalf!", False), ("Merlin42", False),
                  ("Bob_", False), ("123", False), ("a.b.c", False), ("Ab3", False)):
    expect("MageGuild.validate_mage_name(%r)" % name, G.validate_mage_name,
           (name,), exp)
count()
g, _, e = cap(G)
if e is not None:
    fail("MageGuild() raises %s" % summary(e))
else:
    expect("MageGuild().validate_mage_name('Gandalf') (on an instance)",
           g.validate_mage_name, ("Gandalf",), True)
    for spell, p in (("Lightning", 15), ("Fireball", 10), ("Fireball", 9),
                     ("Fireball", 5), ("Ice Storm", 11), ("Heal", 0), ("Heal", -3),
                     ("Meteor", 1000)):
        exp = ("Successfully cast %s with %d power" % (spell, p) if p >= 10
               else "Insufficient power for this spell")
        expect("MageGuild().cast_spell(%r, %d)" % (spell, p), g.cast_spell,
               (spell, p), exp)
EOF
			t_begin
			t_py "$F" "MageGuild" "$CODE"
			T_NOTE="staticmethod, names, cast_spell with min_power=10"
			t_end "MageGuild"
		fi
		demo_line ex4 decorator_mastery.py "spell timer" "Casting" "Spell completed in" "retrying" "MageGuild" "Successfully cast"
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/lambda_spells.py]=1 [ex1/higher_magic.py]=1 [ex2/scope_mysteries.py]=1
		[ex3/functools_artifacts.py]=1 [ex4/decorator_mastery.py]=1
	)
	extra=""
	while IFS= read -r f; do
		f=${f#./}
		[ -n "${EXPECTED[$f]}" ] || extra+="$f "
	done < <(cd "$DIR" && find ./ex[0-9]* -type f ! -path '*/__pycache__/*' ! -path '*/.mypy_cache/*' 2>/dev/null | sort)
	if [ -z "$extra" ]; then line_ok "files" "(only the requested files)"
	else
		line_warn "files" "files that are not requested (\"Files to Submit\" lists one file per exercise):"
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
