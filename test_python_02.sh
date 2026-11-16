#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_02.sh - single-file tester for Python Module 2: Garden Guardian #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_02.sh               -> test everything              #
#      bash ../test_python_02.sh 2 ex4         -> only these exercises         #
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
banner "Python Module 2 tester (Garden Guardian)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 2 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_02.XXXXXX)
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
# script <file>                  : runs the file like "python3 <file>"
#                                  (the exception, if any, goes to $PT_EXC)
# exec <file> <python code>      : imports the file as "m" (output discarded) and
#                                  runs the test code; results go to $PT_RES:
#                                  "N" (one test), "FAIL text", "WARN text",
#                                  "CUR call" (the call in progress)
# watering <file>                : "script" + spies the calls of water_plant()
#                                  (ex4: is the system closed after an error?)
# diff <expected> <got>          : first difference between two outputs
# ast <file> <calls> <imports> <only-functions 0|1> [str methods]
#                                : forbidden calls / imports / str methods,
#                                  code outside functions
# hints <file>                   : parameters / returns without type hints
# info <file>                    : functions, try / except / finally, raise
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import importlib.util
import inspect
import io
import os
import re
import runpy
import sys
import traceback

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))
RES = os.environ.get("PT_RES", os.devnull)


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


def load(path):
    path = os.path.abspath(path)
    sys.path.insert(0, os.path.dirname(path))
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def run_main(path):
    """Runs the file like "python3 <file>" does (its __main__ block too)."""
    path = os.path.abspath(path)
    sys.argv = [path]
    sys.path.insert(0, os.path.dirname(path))
    return runpy.run_path(path, run_name="__main__")


def cmd_script(path):
    try:
        run_main(path)
    except SystemExit as e:
        if e.code in (None, 0):
            return 0
        sys.stdout.flush()
        report("exits with sys.exit(%r)" % (e.code,))
        return 3
    except BaseException as e:
        sys.stdout.flush()
        report("raises " + summary(e))
        return 3
    return 0


# ---- "exec" mode: helpers given to the test code ----
class Stop(Exception):
    """Stops the test code (after a FAIL that makes the rest pointless)."""


MOD = None
BASE = ""


def put(kind, text=""):
    with open(RES, "a", encoding="utf-8") as f:
        f.write("%s %s\n" % (kind, text.replace("\n", "\\n")))


def ck(cond, text):
    """One test: FAIL <text> if cond is false."""
    put("N")
    if not cond:
        put("FAIL", text)
    return bool(cond)


def wn(text):
    put("WARN", text)


def rp(v, n=40):
    return short(repr(v), n)


def en(e):
    """ValueError: message (no location)"""
    m = short(str(e), 80)
    return type(e).__name__ + (": " + m if m else "")


def got(ret, exc):
    """what a call did: "raises X: ..." or "returns ..." """
    if exc is not None:
        return "raises " + summary(exc)
    return "returns " + rp(ret)


def run(f, *args):
    """Calls f(*args) with its output captured: (return, exception, output)"""
    put("CUR", "%s(%s)" % (getattr(f, "__name__", "?"),
                           ", ".join(rp(a) for a in args)))
    old = sys.stdout
    sys.stdout = buf = io.StringIO()
    ret = exc = None
    try:
        ret = f(*args)
    except BaseException as e:
        exc = e
    finally:
        sys.stdout = old
    return ret, exc, buf.getvalue()


def need(name, what="function"):
    """The function / class <name> of the file, or FAIL and stop."""
    obj = getattr(MOD, name, None)
    if obj is None or (what == "class" and not isinstance(obj, type)) \
            or (what == "function" and not callable(obj)):
        put("N")
        put("FAIL", "no %s %s%s in %s" % (what, name,
                                          "()" if what == "function" else "", BASE))
        raise Stop
    return obj


def nreq(f):
    """number of required positional parameters"""
    try:
        ps = inspect.signature(f).parameters.values()
    except (TypeError, ValueError):
        return 0
    return sum(p.default is p.empty and p.kind in (p.POSITIONAL_ONLY,
               p.POSITIONAL_OR_KEYWORD) for p in ps)


def lines_with(out, word):
    return [x for x in out.splitlines() if word in x.lower()]


def cmd_exec(path, code):
    global MOD, BASE
    BASE = os.path.basename(path)
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        MOD = load(path)
    except BaseException as e:
        sys.stdout = old
        put("N")
        put("FAIL", "importing %s raises %s" % (BASE, summary(e)))
        return 0
    sys.stdout = old
    try:
        exec(code, dict(globals(), m=MOD))
    except Stop:
        pass
    except BaseException as e:
        put("N")
        put("FAIL", "unexpected error during the tests: " + summary(e))
    return 0


# ---- "watering" mode (ex4) ----
def spy_run(path, func):
    """Runs the file like python3 does, and records the calls of func():
    returns (items, exception) where items is the list of the output lines
    and of the events ("CALL", argument) / ("OK", None) / ("RAISE", exc)."""
    path = os.path.realpath(path)
    buf = io.StringIO()
    events = []
    pending = {}

    def mark(ev):
        events.append(ev)
        buf.write("\x01%d\x01" % (len(events) - 1))

    def local(frame, event, arg):
        if event == "exception":
            pending[frame] = arg[1]
        elif event == "line":
            pending.pop(frame, None)
        elif event == "return":
            exc = pending.pop(frame, None)
            mark(("RAISE", exc) if exc is not None else ("OK", None))
        return local

    def tracer(frame, event, arg):
        code = frame.f_code
        if event == "call" and code.co_name == func \
                and os.path.realpath(code.co_filename) == path:
            names = code.co_varnames[:code.co_argcount]
            mark(("CALL", frame.f_locals.get(names[0]) if names else None))
            return local
        return None

    err = None
    old = sys.stdout
    sys.stdout = buf
    sys.settrace(tracer)
    try:
        run_main(path)
    except SystemExit as e:
        if e.code not in (None, 0):
            err = e
    except BaseException as e:
        err = e
    finally:
        sys.settrace(None)
        sys.stdout = old
    items = []
    text = ""
    for i, part in enumerate(re.split("\x01([0-9]+)\x01", buf.getvalue())):
        if i % 2 == 0:
            text += part
            continue
        while "\n" in text:
            line, text = text.split("\n", 1)
            items.append(("TEXT", line))
        items.append(events[int(part)])
    rest = text.split("\n")
    if rest[-1] == "":
        rest.pop()
    items += [("TEXT", x) for x in rest]
    return items, err


def cmd_watering(path):
    items, err = spy_run(path, "water_plant")
    sys.stdout.write("".join(x + "\n" for k, x in items if k == "TEXT"))
    if err is not None:
        report("raises " + summary(err))
        return 3
    texts = [x for k, x in items if k == "TEXT"]
    closes = [x for x in texts if "clos" in x.lower()]
    opens = [x for x in texts if "open" in x.lower() and "clos" not in x.lower()]
    calls = [x for k, x in items if k == "CALL"]
    ck(calls, "water_plant() is never called when the program runs")
    raised = [i for i, (k, x) in enumerate(items) if k == "RAISE"]
    ck(raised, "no call of water_plant() fails when the program runs: the subject "
       "tests an invalid plant name (like 'lettuce') too")
    if not any(k == "OK" for k, x in items):
        wn("no call of water_plant() succeeds when the program runs (the subject "
           "tests valid plants too)")
    if not closes:
        wn('no line with "clos" in the output (like "Closing watering system"): '
           'check the cleanup message by hand')
    elif opens and len(opens) != len(closes):
        wn('%d "open" lines but %d "close" lines in the output (each opening '
           'must be followed by a closing)' % (len(opens), len(closes)))
    last_call = None
    for i, (k, x) in enumerate(items):
        if k == "CALL":
            last_call = x
        if k != "RAISE":
            continue
        name = rp(last_call)
        mro = [c.__name__ for c in type(x).__mro__]
        ck("PlantError" in mro, "water_plant(%s) raises %s; expected a PlantError"
           % (name, en(x)))
        if not closes:
            continue
        rest = items[i + 1:]
        nxt = [j for j, (k2, y) in enumerate(rest) if k2 == "CALL"]
        cl = [j for j, (k2, y) in enumerate(rest)
              if k2 == "TEXT" and "clos" in y.lower()]
        if not cl:
            ck(False, "after water_plant(%s) failed, the watering system is "
               "never closed (no closing line after the error)" % name)
        elif nxt and nxt[0] < cl[0]:
            ck(False, "after water_plant(%s) failed, water_plant(%s) is called "
               "before the closing: the test must stop at the first invalid plant"
               % (name, rp(rest[nxt[0]][1])))
        else:
            ck(True, "")
    return 0


def cmd_diff(exp_path, got_path):
    with open(exp_path, encoding="utf-8", errors="replace", newline="") as f:
        exp = f.read()
    with open(got_path, encoding="utf-8", errors="replace", newline="") as f:
        got = f.read()
    if exp == got:
        return 0
    el = exp.splitlines(keepends=True)
    gl = got.splitlines(keepends=True)
    i = 0
    while i < len(el) and i < len(gl) and el[i] == gl[i]:
        i += 1
    if not got:
        print('prints nothing; expected "%s"' % short(exp))
    elif i >= len(gl):
        print('output stops after line %d; expected next: "%s"' % (i, short(el[i])))
    elif i >= len(el):
        print('extra output at line %d: "%s"' % (i + 1, short("".join(gl[i:]))))
    else:
        print('line %d: "%s"; expected "%s"' % (i + 1, short(gl[i]), short(el[i])))
    return 1


# ---- static checks ----
def bound_names(tree):
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
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


def is_main_guard(node):
    return (isinstance(node, ast.If) and isinstance(node.test, ast.Compare)
            and "__name__" in ast.dump(node.test))


def cmd_ast(path, calls, imports, only_functions, methods="*"):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src, path)
    except SyntaxError as e:
        print("SYNTAX %s %s" % (e.lineno, e.msg))
        return 0
    allowed = set(calls.split(","))
    mods = set(imports.split(","))
    meths = set(methods.split(","))
    mine = bound_names(tree)
    bnames = set(dir(builtins))

    def check(name, line):
        if (name in bnames and name not in mine and "*" not in allowed
                and name not in allowed and not is_exception(name)):
            print("CALL %s %s" % (name, line))

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            check(n.func.id, n.lineno)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute):
            a = n.func.attr
            if a in dir(str) and not a.startswith("_") and "*" not in meths \
                    and a not in meths:
                print("METH %s %s" % (a, n.lineno))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            for d in n.decorator_list:
                if isinstance(d, ast.Name):
                    check(d.id, d.lineno)
        if isinstance(n, ast.Import):
            for a in n.names:
                if "*" not in mods and a.name not in mods \
                        and a.name.split(".")[0] not in mods:
                    print("IMPORT %s %s" % (a.name, n.lineno))
        if isinstance(n, ast.ImportFrom) and n.level == 0:
            if "*" not in mods and n.module not in mods \
                    and n.module.split(".")[0] not in mods:
                print("IMPORT %s %s" % (n.module, n.lineno))
    for s in tree.body:
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
            print("DEF %s %s" % (s.name, s.lineno))
        elif isinstance(s, ast.ClassDef):
            print("CLASS %s %s" % (s.name, s.lineno))
        elif only_functions == "1":
            if isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant) \
                    and isinstance(s.value.value, str):
                continue
            if isinstance(s, (ast.Import, ast.ImportFrom)):
                continue
            if is_main_guard(s):
                print("MAIN %s" % s.lineno)
            else:
                print("TOP %s %s" % (s.lineno, short(ast.unparse(s).split("\n")[0], 50)))
    return 0


def cmd_hints(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)

    def check(fn, in_class):
        a = fn.args
        params = a.posonlyargs + a.args
        static = any(isinstance(d, ast.Name) and d.id == "staticmethod"
                     for d in fn.decorator_list)
        if in_class and not static and params:
            params = params[1:]
        miss = [p.arg for p in params + a.kwonlyargs if p.annotation is None]
        for p, star in ((a.vararg, "*"), (a.kwarg, "**")):
            if p is not None and p.annotation is None:
                miss.append(star + p.arg)
        typed = any(p.annotation is not None for p in params + a.kwonlyargs)
        # PEP 484: __init__ may omit "-> None" when a parameter is annotated
        if fn.returns is None and not (fn.name == "__init__" and typed):
            miss.append("return")
        if miss:
            print("%s: %s(): no type hint for %s" % (fn.lineno, fn.name, ", ".join(miss)))

    def visit(node, in_class):
        for ch in ast.iter_child_nodes(node):
            if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef)):
                check(ch, in_class)
                visit(ch, False)
            elif isinstance(ch, ast.ClassDef):
                visit(ch, True)
            else:
                visit(ch, in_class)

    visit(tree, False)
    return 0


def cmd_info(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)

    def exc_name(node):
        if isinstance(node, ast.Call):
            node = node.func
        if isinstance(node, ast.Name):
            return node.id
        if isinstance(node, ast.Attribute):
            return node.attr
        return "?"

    def visit(node, func):
        for ch in ast.iter_child_nodes(node):
            fn = func
            if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef)):
                fn = ch.name
                if node is tree:
                    print("FUNC %s %s %s" % (ch.name, ch.body[0].lineno, ch.end_lineno))
            elif isinstance(ch, ast.Try) or type(ch).__name__ == "TryStar":
                tup = any(isinstance(h.type, ast.Tuple) for h in ch.handlers)
                print("TRY %s %d %d %d %s" % (ch.lineno, len(ch.handlers), tup,
                                              1 if ch.finalbody else 0, func))
            elif isinstance(ch, ast.ExceptHandler) and ch.type is not None:
                types = ch.type.elts if isinstance(ch.type, ast.Tuple) else [ch.type]
                for t in types:
                    print("EXCEPT %s %s %s" % (exc_name(t), ch.lineno, func))
            elif isinstance(ch, ast.Raise):
                print("RAISE %s %s %s" % (exc_name(ch.exc) if ch.exc else "-",
                                          ch.lineno, func))
            visit(ch, fn)

    visit(tree, "-")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"script": cmd_script, "exec": cmd_exec, "watering": cmd_watering,
              "diff": cmd_diff, "ast": cmd_ast, "hints": cmd_hints,
              "info": cmd_info}[cmd](*sys.argv[2:]))
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
export PT_ROOT="$WORK" PT_EXC="$TMP/exc" PT_RES="$TMP/res"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err, EXC, $TMP/res
# (10 s at most per test)
run_py() {
	local in=$1
	shift
	rm -f "$TMP/exc" "$TMP/res"
	( cd "$TMP" && exec timeout -k 1 10 python3 -I "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
	EXC=""
	[ -f "$TMP/exc" ] && EXC=$(head -1 "$TMP/exc")
}

# Results of one test line
# (after a timeout, the other tests of the same line are skipped)
t_begin() { T_FAILS=(); T_WARNS=(); T_N=0; T_INFO=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
# t_end <label> [note shown under the warnings]
t_end() {
	local m i=0
	if t_ok; then
		if [ ${#T_WARNS[@]} -eq 0 ]; then
			line_ok "$1" "${T_INFO:-($T_N tests)}"
			return
		fi
		line_warn "$1" "${T_WARNS[0]}"
		for m in "${T_WARNS[@]:1:5}"; do note "$m"; done
		[ -n "$2" ] && note "$2"
		return
	fi
	line_ko "$1"
	for m in "${T_FAILS[@]}"; do
		i=$((i + 1))
		if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
		msg "$m"
	done
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# t_results: reads $TMP/res (written by the "exec" and "watering" modes)
t_results() {
	local line kind
	T_CUR=""
	[ -f "$TMP/res" ] || return 0
	while IFS= read -r line; do
		kind=${line%% *}
		case $kind in
			N) T_N=$((T_N + 1)) ;;
			FAIL) t_fail "${line#FAIL }" ;;
			WARN) T_WARNS+=("${line#WARN }") ;;
			CUR) T_CUR=${line#CUR } ;;
		esac
	done < "$TMP/res"
}

# t_exec <file> <python code>
# Runs test code in a new python3 process (the file is imported as "m").
t_exec() {
	[ $T_TIMEOUT -eq 1 ] && return 1
	run_py /dev/null exec "$1" "$2"
	t_results
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "${T_CUR:-importing $(basename "$1")}: infinite loop or too slow (more than 10 s)"
		return 1
	fi
	if [ $RC -ne 0 ]; then
		t_fail "${T_CUR:+$T_CUR: }python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"
		return 1
	fi
	return 0
}

# t_script <file> <example output of the subject> [pt.py mode]
# Runs "python3 <file>" (stdin: /dev/null). It must not crash and must print
# something. The output is compared with the example of the subject: only a
# warning, the wording of the examples is free.
t_script() {
	local f=$1 exp=$2 mode=${3:-script} what d
	what="python3 ${f#"$WORK/"}"
	[ $T_TIMEOUT -eq 1 ] && return 1
	printf '%s' "$exp" > "$TMP/exp"
	run_py /dev/null "$mode" "$f"
	T_N=$((T_N + 1))
	t_results
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "$what: infinite loop or too slow (more than 10 s)"
		return 1
	fi
	if [ $RC -eq 3 ]; then t_fail "$what: $EXC (the program must never crash)"; return 1; fi
	if [ $RC -ne 0 ]; then t_fail "$what: python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"; return 1; fi
	if [ ! -s "$TMP/out" ]; then t_fail "$what prints nothing (does the main part call the tests?)"; return 1; fi
	[ -s "$TMP/err" ] && T_WARNS+=("$what writes on stderr: \"$(head -1 "$TMP/err" | cut -c1-70)\"")
	d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out")
	if [ -z "$d" ]; then T_INFO="(same output as the subject example)"
	else T_WARNS+=("$what: differs from the subject example: $d")
	fi
	return 0
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

# mypy_line <file> [first line] [last line]
# The errors between the two lines are expected (ex2: the subject says that mypy
# reports the faulty TypeError code of garden_operations())
mypy_line() {
	local f=$1 from=${2:-0} to=${3:-0} out l ln bad=() tol=0
	if [ ${#MYPY[@]} -eq 0 ]; then line_skip "mypy" "not installed"; return; fi
	out=$(cd "$WORK" && "${MYPY[@]}" --cache-dir "$TMP/mypy_cache" --no-error-summary "$f" 2>&1 | grep -E 'error:')
	while IFS= read -r l; do
		[ -z "$l" ] && continue
		ln=$(cut -d: -f2 <<< "$l")
		if [[ $ln =~ ^[0-9]+$ ]] && [ "$ln" -ge "$from" ] && [ "$ln" -le "$to" ]; then
			tol=$((tol + 1))
		else
			bad+=("$l")
		fi
	done <<< "$out"
	if [ ${#bad[@]} -eq 0 ]; then
		if [ $tol -gt 0 ]; then line_ok "mypy" "($tol expected error(s) in lines $from-$to: the faulty code)"
		else line_ok "mypy"; fi
	else
		line_ko "mypy"
		for l in "${bad[@]:0:4}"; do msg "$(cut -c1-120 <<< "$l")"; done
		[ ${#bad[@]} -gt 4 ] && msg "… (${#bad[@]} errors in total)"
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
		e=$(python3 -I "$PT" ast "$WORK/$ex/$f" '*' '*' 0 | grep -m1 '^SYNTAX')
		if [ -n "$e" ]; then
			read -r _ l e <<< "$e"
			line_ko "$f"; msg "SyntaxError line $l: $e"
			return 1
		fi
	done
	return 0
}

# static_lines <file> <allowed calls> <allowed str methods> <label> <names...>
# Lines: "names" (the requested functions / classes), "authorized",
# "str methods" (warning), "type hints", "main guard" (warning)
static_lines() {
	local f=$1 calls=$2 meths=$3 label=$4 base kind a b c m n
	local defs=() top=() main=0 bad=() meth=() miss=() nf=()
	shift 4
	base=$(basename "$f")
	while read -r kind a b c; do
		case $kind in
			DEF|CLASS) defs+=("$a") ;;
			MAIN) main=1 ;;
			TOP) top+=("$base:$a: $b${c:+ $c}") ;;
			CALL) bad+=("$a() (line $b)") ;;
			IMPORT) bad+=("import $a (line $b)") ;;
			METH) meth+=(".$a() (line $b)") ;;
		esac
	done < <(python3 -I "$PT" ast "$f" "$calls" '' 1 "$meths")

	for n in "$@"; do
		[[ " ${defs[*]} " == *" ${n%()} "* ]] || nf+=("$n")
	done
	if [ ${#nf[@]} -eq 0 ]; then line_ok "names" "($*)"
	else
		line_ko "names"
		for n in "${nf[@]}"; do msg "$base: no $n defined at the top level (the name must match exactly)"; done
	fi

	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized" "($label)"
	else
		line_ko "authorized"
		msg "forbidden: ${bad[*]}"
		note "authorized: $label (+ the exception classes)"
	fi
	if [ ${#meth[@]} -gt 0 ]; then
		line_warn "str methods" "${meth[*]}: not in the authorized list ($label)"
		note "(only a warning: the tester cannot know if it is called on a str)"
	fi

	mapfile -t miss < <(python3 -I "$PT" hints "$f")
	if [ ${#miss[@]} -eq 0 ]; then line_ok "type hints" "(every parameter and return)"
	else
		line_ko "type hints"
		for m in "${miss[@]:0:6}"; do msg "$base:$m"; done
		[ ${#miss[@]} -gt 6 ] && msg "… (${#miss[@]} functions in total)"
	fi

	if [ ${#top[@]} -gt 0 ]; then
		line_warn "main guard" "code outside the functions (it also runs when the file is imported):"
		for m in "${top[@]:0:3}"; do note "$m"; done
		note "put it in an if __name__ == \"__main__\": block"
	elif [ $main -eq 0 ]; then
		line_warn "main guard" "no if __name__ == \"__main__\": block: nothing runs with python3 $base"
	else
		line_ok "main guard"
	fi
}

# info_load <file>: functions, try blocks, except clauses and raise statements
# I_FUNC[name]="first last" (body lines), I_TRY ("line handlers tuple finally func"),
# I_EXCEPT ("name line func"), I_RAISE ("name line func")
info_load() {
	local kind a b c d e f
	declare -gA I_FUNC=()
	I_TRY=(); I_EXCEPT=(); I_RAISE=()
	while read -r kind a b c d e f; do
		case $kind in
			FUNC) I_FUNC[$a]="$b $c" ;;
			TRY) I_TRY+=("$a $b $c $d $e") ;;
			EXCEPT) I_EXCEPT+=("$a $b $c") ;;
			RAISE) I_RAISE+=("$a $b $c") ;;
		esac
	done < <(python3 -I "$PT" info "$1")
}

# has_try_except: at least one try block with an except clause
has_try_except() {
	local t
	for t in "${I_TRY[@]}"; do
		read -r _ h _ _ _ <<< "$t"
		[ "$h" -gt 0 ] && return 0
	done
	return 1
}

# try_line <file>: "try/except" line (all exercises of the module require one)
try_line() {
	if has_try_except; then line_ok "try/except" "(${#I_TRY[@]} try block(s))"
	else line_ko "try/except"; msg "$(basename "$1"): no try/except block (every exercise of this module requires one)"; fi
}

nl=$'\n'

# ================================ Exercises ================================= #

# ------------------------- ex0: first exception ----------------------------- #
IFS= read -r -d '' EX0_OUT <<'EOF'
=== Garden Temperature ===

Input data is '25'
Temperature is now 25°C

Input data is 'abc'
Caught input_temperature error: invalid literal for int() with base 10: 'abc'

All tests completed - program didn't crash!
EOF

# input_temperature() of ex0: no range check
IFS= read -r -d '' EX0_INPUT <<'EOF'
f = need("input_temperature")
for s, v in [("25", 25), ("0", 0), ("40", 40), ("1", 1), ("7", 7),
             (" 42 ", 42), ("+7", 7), ("007", 7), ("-0", 0), ("30\n", 30)]:
    ret, exc, out = run(f, s)
    ck(exc is None and type(ret) is int and ret == v,
       "input_temperature(%s) %s; expected %r (an int)" % (rp(s), got(ret, exc), v))
for s, v in [("-5", -5), ("100", 100), ("-273", -273), ("123456789", 123456789)]:
    ret, exc, out = run(f, s)
    if not (exc is None and type(ret) is int and ret == v):
        wn("input_temperature(%s) %s; expected %r: the 0-40 check is for ex1, "
           "not ex0" % (rp(s), got(ret, exc), v))
for s in ["abc", "", "25abc", "2.5", "twenty", "   ", "4 2", "0x10", "25°C"]:
    ret, exc, out = run(f, s)
    ck(isinstance(exc, Exception),
       "input_temperature(%s) %s; expected an exception (test_temperature() "
       "must catch it)" % (rp(s), got(ret, exc)))
ret, exc, out = run(f, "abc")
if isinstance(exc, Exception) and not isinstance(exc, ValueError):
    wn("input_temperature('abc') raises %s; int() raises a ValueError" % en(exc))
EOF

# test_temperature() of ex0 / ex1. INPUTS: the inputs the subject asks to test
IFS= read -r -d '' TEST_TEMP <<'EOF'
f = need("input_temperature")
t = need("test_temperature")
calls = []
errs = []


def spy(*a, **k):
    calls.append(a[0] if a else None)
    try:
        return f(*a, **k)
    except Exception as e:
        errs.append(str(e))
        raise


m.input_temperature = spy
ret, exc, out = run(t)
m.input_temperature = f
ck(exc is None, "test_temperature() %s; it must catch the errors (the program "
   "must never crash)" % got(ret, exc))
for s in INPUTS:
    ck(s in calls, "test_temperature() does not call input_temperature(%s) "
       "(calls: %s)" % (rp(s), ", ".join(rp(c) for c in calls) or "none"))
if exc is None:
    ck("25" in out, 'test_temperature(): no "25" in the output (the valid '
       'temperature must be shown): "%s"' % short(out, 60))
    miss = [e for e in errs if e not in out]
    if miss:
        wn('test_temperature() does not print the error message "%s" (the '
           'example prints the message of the exception)' % short(miss[0], 60))
# every call fails: the program must keep running
calls = []


def boom(*a, **k):
    calls.append(a[0] if a else None)
    raise ValueError("tester error 42")


m.input_temperature = boom
ret, exc, out = run(t)
m.input_temperature = f
ck(exc is None, "test_temperature() with an input_temperature() that always "
   "raises ValueError: %s; expected no crash" % got(ret, exc))
if exc is None and len(calls) < len(INPUTS):
    wn("test_temperature() stops after the first error when input_temperature() "
       "always fails (calls: %s): each test should go on after an error"
       % ", ".join(rp(c) for c in calls))
EOF

if wanted 0; then
	section "ex0 - ft_first_exception"
	if ex_files ex0 ft_first_exception.py; then
		F="$WORK/ex0/ft_first_exception.py"
		flake8_line ex0/ft_first_exception.py
		static_lines "$F" int,print,super '' "int(), print()" "input_temperature()" "test_temperature()"
		mypy_line ex0/ft_first_exception.py
		info_load "$F"
		try_line "$F"

		t_begin
		t_script "$F" "$EX0_OUT"
		t_end "program output" "(the wording of the example is free: check the differences by hand)"
		t_begin
		t_exec "$F" "$EX0_INPUT"
		t_end "input_temperature"
		t_begin
		t_exec "$F" "INPUTS = ['25', 'abc']$nl$TEST_TEMP"
		t_end "test_temperature"
	fi
fi

# ------------------------- ex1: raise exception ----------------------------- #
IFS= read -r -d '' EX1_OUT <<'EOF'
=== Garden Temperature Checker ===

Input data is '25'
Temperature is now 25°C

Input data is 'abc'
Caught input_temperature error: invalid literal for int() with base 10: 'abc'

Input data is '100'
Caught input_temperature error: 100°C is too hot for plants (max 40°C)

Input data is '-50'
Caught input_temperature error: -50°C is too cold for plants (min 0°C)

All tests completed - program didn't crash!
EOF

# input_temperature() of ex1: 0 to 40, limits included
IFS= read -r -d '' EX1_INPUT <<'EOF'
f = need("input_temperature")
for s, v in [("25", 25), ("0", 0), ("40", 40), ("1", 1), ("39", 39), ("20", 20),
             (" 30 ", 30), ("+40", 40), ("-0", 0), ("007", 7)]:
    ret, exc, out = run(f, s)
    ck(exc is None and type(ret) is int and ret == v,
       "input_temperature(%s) %s; expected %r (an int from 0 to 40, limits "
       "included)" % (rp(s), got(ret, exc), v))
for s in ["41", "-1", "100", "-50", "1000", "-273", "99999999999999999999",
          "abc", "", "2.5", "25abc", "   ", "40.0"]:
    ret, exc, out = run(f, s)
    ck(isinstance(exc, Exception),
       "input_temperature(%s) %s; expected an exception (%s)"
       % (rp(s), got(ret, exc), "not a number" if s.strip("-").isdigit() is False
          else "out of the 0-40 range"))
# messages of the example
for s, want, word in [("100", "100°C is too hot for plants (max 40°C)", "hot"),
                      ("-50", "-50°C is too cold for plants (min 0°C)", "cold")]:
    ret, exc, out = run(f, s)
    if isinstance(exc, Exception) and str(exc) != want:
        wn('input_temperature(%s) raises %s; the example message is "%s"'
           % (rp(s), en(exc), want))
EOF

if wanted 1; then
	section "ex1 - ft_raise_exception"
	if ex_files ex1 ft_raise_exception.py; then
		F="$WORK/ex1/ft_raise_exception.py"
		flake8_line ex1/ft_raise_exception.py
		static_lines "$F" int,print,super '' "int(), print()" "input_temperature()" "test_temperature()"
		mypy_line ex1/ft_raise_exception.py
		info_load "$F"
		try_line "$F"
		has_raise=0
		for r in "${I_RAISE[@]}"; do [[ $r == *" input_temperature" ]] && has_raise=1; done
		[ $has_raise -eq 0 ] && line_warn "raise" "no raise statement in input_temperature() (the subject: \"otherwise, raise an exception\")"

		t_begin
		t_script "$F" "$EX1_OUT"
		t_end "program output" "(the wording of the example is free: check the differences by hand)"
		t_begin
		t_exec "$F" "$EX1_INPUT"
		t_end "input_temperature"
		t_begin
		t_exec "$F" "INPUTS = ['25', 'abc', '100', '-50']$nl$TEST_TEMP"
		t_end "test_temperature"
	fi
fi

# ------------------------- ex2: different errors ---------------------------- #
IFS= read -r -d '' EX2_OUT <<'EOF'
=== Garden Error Types Demo ===
Testing operation 0...
Caught ValueError: invalid literal for int() with base 10: 'abc'
Testing operation 1...
Caught ZeroDivisionError: division by zero
Testing operation 2...
Caught FileNotFoundError: [Errno 2] No such file or directory: '/non/existent/file'
Testing operation 3...
Caught TypeError: can only concatenate str (not "int") to str
Testing operation 4...
Operation completed successfully

All error types tested successfully!
EOF

IFS= read -r -d '' EX2_OPS <<'EOF'
g = need("garden_operations")
kinds = [ValueError, ZeroDivisionError, FileNotFoundError, TypeError]
found = []
for n in range(4):
    ret, exc, out = run(g, n)
    k = None
    for c in kinds:
        if isinstance(exc, c):
            k = c
    found.append(k)
    ck(k is not None, "garden_operations(%d) %s; expected ValueError, "
       "ZeroDivisionError, FileNotFoundError or TypeError" % (n, got(ret, exc)))
    if k is not None:
        ret2, exc2, out2 = run(g, n)
        ck(type(exc2) is type(exc), "garden_operations(%d) a second time %s; "
           "the first time: %s" % (n, got(ret2, exc2), en(exc)))
names = ", ".join("%d: %s" % (n, c.__name__ if c else "-")
                  for n, c in enumerate(found))
for c in kinds:
    ck(c in found, "no operation from 0 to 3 raises %s (%s)" % (c.__name__, names))
if None not in found and len(set(found)) == 4 and found != kinds:
    wn("the order differs from the subject example (0: ValueError, "
       "1: ZeroDivisionError, 2: FileNotFoundError, 3: TypeError): %s" % names)
for n in [4, 5, 10, 42, 1000, -1]:
    ret, exc, out = run(g, n)
    ck(exc is None, "garden_operations(%d) %s; expected no error (the other "
       "values simply return)" % (n, got(ret, exc)))
EOF

IFS= read -r -d '' EX2_TEST <<'EOF'
g = need("garden_operations")
t = need("test_error_types")
calls = []


def spy(*a, **k):
    calls.append(a[0] if a else k.get("operation_number"))
    return g(*a, **k)


m.garden_operations = spy
ret, exc, out = run(t)
m.garden_operations = g
ck(exc is None, "test_error_types() %s; it must catch every error (the "
   "program must never crash)" % got(ret, exc))
for n in range(4):
    ck(n in calls, "test_error_types() never calls garden_operations(%d): each "
       "type of error must be shown (calls: %s)"
       % (n, ", ".join(rp(c) for c in calls) or "none"))
if exc is None:
    for name in ["ValueError", "ZeroDivisionError", "FileNotFoundError", "TypeError"]:
        if name not in out:
            wn('test_error_types(): "%s" is not in the output (the example '
               'prints "Caught %s: ...")' % (name, name))
    if not any(isinstance(c, int) and not 0 <= c <= 3 for c in calls):
        wn("test_error_types() never calls garden_operations() with a value "
           "without error (the example tests operation 4)")
EOF

if wanted 2; then
	section "ex2 - ft_different_errors"
	if ex_files ex2 ft_different_errors.py; then
		F="$WORK/ex2/ft_different_errors.py"
		flake8_line ex2/ft_different_errors.py
		static_lines "$F" print,open,int,super '' "print(), open(), int()" "garden_operations()" "test_error_types()"
		info_load "$F"
		read -r g_from g_to <<< "${I_FUNC[garden_operations]:-0 0}"
		mypy_line ex2/ft_different_errors.py "$g_from" "$g_to"
		try_line "$F"
		# several error types with one try: "except (A, B)" or several except clauses
		multi=0
		for t in "${I_TRY[@]}"; do
			read -r ln h tup _ _ <<< "$t"
			{ [ "$tup" = 1 ] || [ "$h" -gt 1 ]; } && multi=1
		done
		if [ $multi -eq 1 ]; then line_ok "multiple errors" "(one try: block catches several error types)"
		else line_warn "multiple errors" "no try: block with several except clauses or an except (A, B): the subject asks to show it"; fi
		rs=()
		for r in "${I_RAISE[@]}"; do
			read -r a b c <<< "$r"
			[ "$c" = garden_operations ] && rs+=("raise $a (line $b)")
		done
		[ ${#rs[@]} -gt 0 ] && line_warn "faulty code" "garden_operations() uses ${rs[*]}: the subject asks for faulty code that raises by itself"

		t_begin
		t_script "$F" "$EX2_OUT"
		t_end "program output" "(the wording of the example is free: check the differences by hand)"
		t_begin
		t_exec "$F" "$EX2_OPS"
		t_end "garden_operations"
		t_begin
		t_exec "$F" "$EX2_TEST"
		t_end "test_error_types"
	fi
fi

# --------------------------- ex3: custom errors ----------------------------- #
IFS= read -r -d '' EX3_OUT <<'EOF'
=== Custom Garden Errors Demo ===

Testing PlantError...
Caught PlantError: The tomato plant is wilting!

Testing WaterError...
Caught WaterError: Not enough water in the tank!

Testing catching all garden errors...
Caught GardenError: The tomato plant is wilting!
Caught GardenError: Not enough water in the tank!

All custom error types work correctly!
EOF

# Hierarchy of the custom errors
IFS= read -r -d '' EX3_TREE <<'EOF'
G = need("GardenError", "class")
P = need("PlantError", "class")
W = need("WaterError", "class")
for name, c in [("GardenError", G), ("PlantError", P), ("WaterError", W)]:
    if not ck(issubclass(c, Exception), "%s is not an exception class: it "
              "must inherit from Exception (bases: %s)"
              % (name, ", ".join(b.__name__ for b in c.__bases__))):
        raise Stop
ck(issubclass(P, G), "PlantError does not inherit from GardenError (bases: %s)"
   % ", ".join(b.__name__ for b in P.__bases__))
ck(issubclass(W, G), "WaterError does not inherit from GardenError (bases: %s)"
   % ", ".join(b.__name__ for b in W.__bases__))
ck(not issubclass(G, P) and not issubclass(G, W),
   "GardenError inherits from PlantError / WaterError: it must be their base")
ck(not issubclass(P, W) and not issubclass(W, P),
   "PlantError and WaterError inherit from each other: they must be separate")
if Exception not in G.__bases__:
    wn("GardenError inherits from %s; the subject says Exception"
       % ", ".join(b.__name__ for b in G.__bases__))
for c in (P, W):
    caught = None
    try:
        raise c("tester message")
    except G as e:
        caught = e
    except Exception:
        pass
    ck(caught is not None, "except GardenError: does not catch a %s" % c.__name__)
    caught = None
    try:
        raise c("tester message")
    except c as e:
        caught = e
    except Exception:
        pass
    ck(caught is not None, "except %s: does not catch a %s" % (c.__name__, c.__name__))
for c, other in ((P, W), (W, P)):
    caught = False
    try:
        try:
            raise c("x")
        except other:
            caught = True
    except Exception:
        pass
    ck(not caught, "except %s: catches a %s" % (other.__name__, c.__name__))
caught = False
try:
    try:
        raise G("x")
    except P:
        caught = True
except Exception:
    pass
ck(not caught, "except PlantError: catches a GardenError")
EOF

# Messages: default and given
IFS= read -r -d '' EX3_MSG <<'EOF'
G = need("GardenError", "class")
P = need("PlantError", "class")
W = need("WaterError", "class")
defaults = {}
for name, c in [("GardenError", G), ("PlantError", P), ("WaterError", W)]:
    ret, exc, out = run(c)
    if ck(exc is None, "%s() %s; expected an error with a default message"
          % (name, got(ret, exc))):
        defaults[name] = str(ret)
        ck(str(ret) != "", 'str(%s()) is empty; expected a default message (like '
           '"Unknown %s error")' % (name, name[:-5].lower()))
for name, c, text in [("GardenError", G, "Something is wrong in the garden"),
                      ("PlantError", P, "The tomato plant is wilting!"),
                      ("WaterError", W, "Not enough water in the tank!"),
                      ("PlantError", P, "Rose: no more petals"),
                      ("WaterError", W, "Pipe 3 is frozen")]:
    ret, exc, out = run(c, text)
    ck(exc is None and str(ret) == text,
       "str(%s(%s)) %s; expected %s" % (name, rp(text), "-> %s" % rp(str(ret))
                                        if exc is None else got(ret, exc), rp(text)))
    if exc is None:
        try:
            raise ret
        except Exception as e:
            ck(str(e) == text, "raise %s(%s): the caught error says %s"
               % (name, rp(text), rp(str(e))))
    if exc is None and name in defaults:
        ret2, exc2, out2 = run(c)
        ck(exc2 is None and str(ret2) == defaults[name],
           "%s() after %s(%s): %s; expected the default message %s again"
           % (name, name, rp(text), rp(str(ret2)), rp(defaults[name])))
same = [(a, b) for a, b in [("PlantError", "GardenError"), ("WaterError",
        "GardenError"), ("PlantError", "WaterError")]
        if a in defaults and b in defaults and defaults[a] == defaults[b]]
if same:
    wn("%s() and %s() have the same default message %s: each error should "
       "have its own (like \"Unknown plant error\")"
       % (same[0][0], same[0][1], rp(defaults[same[0][0]])))
EOF

if wanted 3; then
	section "ex3 - ft_custom_errors"
	if ex_files ex3 ft_custom_errors.py; then
		F="$WORK/ex3/ft_custom_errors.py"
		flake8_line ex3/ft_custom_errors.py
		static_lines "$F" print,super '' "print()" "GardenError" "PlantError" "WaterError"
		mypy_line ex3/ft_custom_errors.py
		info_load "$F"
		try_line "$F"
		# "Demonstrate that catching GardenError catches all garden-related errors"
		t_begin
		ge=0; rp_=0; rw_=0
		for e in "${I_EXCEPT[@]}"; do [[ $e == "GardenError "* ]] && ge=1; done
		for r in "${I_RAISE[@]}"; do
			[[ $r == "PlantError "* ]] && rp_=1
			[[ $r == "WaterError "* ]] && rw_=1
		done
		T_N=3
		[ $ge -eq 0 ] && t_fail "no except GardenError: clause (the subject: \"demonstrate that catching GardenError catches all garden-related errors\")"
		[ $rp_ -eq 0 ] && T_WARNS+=("no raise PlantError(...) statement found")
		[ $rw_ -eq 0 ] && T_WARNS+=("no raise WaterError(...) statement found")
		t_end "raise / except" "(check by hand that both errors are raised and caught)"

		t_begin
		t_script "$F" "$EX3_OUT"
		for w in PlantError WaterError GardenError; do
			t_ok && [ -s "$TMP/out" ] && ! grep -q "$w" "$TMP/out" && T_WARNS+=("\"$w\" is not in the output (the example prints \"Caught $w: ...\")")
		done
		t_end "program output" "(the wording of the example is free: check the differences by hand)"
		t_begin
		t_exec "$F" "$EX3_TREE"
		t_end "hierarchy"
		t_begin
		t_exec "$F" "$EX3_MSG"
		t_end "messages"
	fi
fi

# --------------------------- ex4: finally block ----------------------------- #
IFS= read -r -d '' EX4_OUT <<'EOF'
=== Garden Watering System ===

Testing valid plants...
Opening watering system
Watering Tomato: [OK]
Watering Lettuce: [OK]
Watering Carrots: [OK]
Closing watering system

Testing invalid plants...
Opening watering system
Watering Tomato: [OK]
Caught PlantError: Invalid plant name to water: 'lettuce'
.. ending tests and returning to main
Closing watering system

Cleanup always happens, even with errors!
EOF

IFS= read -r -d '' EX4_WATER <<'EOF'
P = need("PlantError", "class")
w = need("water_plant")
if not ck(issubclass(P, Exception), "PlantError is not an exception class"):
    raise Stop
G = getattr(m, "GardenError", None)
if isinstance(G, type) and not issubclass(P, G):
    wn("PlantError does not inherit from GardenError (as in ex3)")
noname = []
for name in ["Tomato", "Lettuce", "Carrots", "Basil", "Sunflower", "A",
             "Cherry tomato", "Rose"]:
    ret, exc, out = run(w, name)
    ck(exc is None, "water_plant(%s) %s; expected a success (the name is "
       "capitalized)" % (rp(name), got(ret, exc)))
    if exc is None:
        ck(out.strip() != "", "water_plant(%s) prints nothing; expected a "
           "message on success" % rp(name))
        if out.strip() and name not in out:
            noname.append(name)
if noname:
    wn("water_plant(%s) prints %s: the example prints the plant name "
       "(\"Watering Tomato: [OK]\")" % (rp(noname[0]), rp(out)))
nomsg = []
for name in ["lettuce", "tomato", "carrots", "basil", "a", "cherry tomato",
             "tOMATO", "lETTUCE", "rose"]:
    ret, exc, out = run(w, name)
    ck(isinstance(exc, P), "water_plant(%s) %s; expected a PlantError (the "
       "name is not capitalized)" % (rp(name), got(ret, exc)))
    ck("[OK]" not in out, "water_plant(%s) prints %s before the error"
       % (rp(name), rp(out)))
    if isinstance(exc, P) and name not in str(exc):
        nomsg.append("%s -> %s" % (rp(name), rp(str(exc))))
if nomsg:
    wn("the PlantError message does not contain the plant name: %s (example: "
       "\"Invalid plant name to water: 'lettuce'\")" % nomsg[0])
# names where "capitalized" depends on the method: str.capitalize() is the rule
diff = []
for name in ["TOMATO", "Cherry Tomato", "ToMaTo", "LETTUCE"]:
    ret, exc, out = run(w, name)
    if not isinstance(exc, P):
        diff.append(name)
if diff:
    wn("water_plant(%s) succeeds although %s.capitalize() is %s: check how "
       "you test \"capitalized\"" % (rp(diff[0]), rp(diff[0]),
                                     rp(diff[0].capitalize())))
EOF

IFS= read -r -d '' EX4_TEST <<'EOF'
P = need("PlantError", "class")
w = need("water_plant")
t = need("test_watering_system")
n = nreq(t)
if n > 1:
    wn("test_watering_system() takes %d parameters: not tested here (the "
       "program output is tested above)" % n)
    raise Stop
args = () if n == 0 else (["Tomato", "Lettuce"],)
what = "test_watering_system(%s)" % ", ".join(rp(a) for a in args)
ret, exc, out = run(t, *args)
ck(exc is None, "%s %s; it must handle the errors" % (what, got(ret, exc)))
closing = bool(lines_with(out, "clos"))
if exc is None and not closing:
    wn('%s prints no line with "clos" (like "Closing watering system"): the '
       'cleanup is not tested' % what)


def broken(*a, **k):
    raise RuntimeError("unexpected tester error")


# finally: the closing happens even with an error that is not caught
m.water_plant = broken
ret, exc, out = run(t, *args)
m.water_plant = w
if closing:
    ck(lines_with(out, "clos"), "%s with a water_plant() that raises "
       "RuntimeError: no closing line (output: %s); the closing must be in "
       "a finally: block" % (what, rp(out, 60)))
if n == 1:
    calls = []

    def spy(*a, **k):
        calls.append(a[0] if a else None)
        return w(*a, **k)

    for plants, want in [(["Tomato", "lettuce", "Carrots"], ["Tomato", "lettuce"]),
                         (["basil", "Tomato"], ["basil"]),
                         (["Tomato", "Lettuce", "Carrots"], ["Tomato", "Lettuce", "Carrots"]),
                         ([], [])]:
        calls.clear()
        m.water_plant = spy
        ret, exc, out = run(t, plants)
        m.water_plant = w
        what = "test_watering_system(%s)" % rp(plants, 60)
        ck(exc is None, "%s %s; the PlantError must be handled" % (what, got(ret, exc)))
        ck(calls == want, "%s waters %s; expected %s%s" % (
           what, ", ".join(rp(c) for c in calls) or "nothing",
           ", ".join(rp(c) for c in want) or "nothing",
           " (the test stops at the first invalid plant)" if want != plants else ""))
        if closing:
            ck(lines_with(out, "clos"), "%s: no closing line (output: %s)"
               % (what, rp(out, 60)))
EOF

if wanted 4; then
	section "ex4 - ft_finally_block"
	if ex_files ex4 ft_finally_block.py; then
		F="$WORK/ex4/ft_finally_block.py"
		flake8_line ex4/ft_finally_block.py
		static_lines "$F" print,super capitalize "print(), str.capitalize()" "PlantError" "water_plant()" "test_watering_system()"
		mypy_line ex4/ft_finally_block.py
		info_load "$F"
		try_line "$F"
		# try/except/finally in test_watering_system()
		fin=""; fin_any=""
		for t in "${I_TRY[@]}"; do
			read -r ln h _ fi fn <<< "$t"
			if [ "$fi" = 1 ] && [ "$h" -gt 0 ]; then
				fin_any=$ln
				[ "$fn" = test_watering_system ] && fin=$ln
			fi
		done
		if [ -n "$fin" ]; then line_ok "try/except/finally" "(line $fin, in test_watering_system())"
		elif [ -n "$fin_any" ]; then line_warn "try/except/finally" "line $fin_any, but not in test_watering_system() (check by hand)"
		else line_ko "try/except/finally"; msg "no try/except/finally block: test_watering_system() must close the system in a finally: block"; fi

		t_begin
		t_script "$F" "$EX4_OUT" watering
		t_end "program output" "(the wording of the example is free: check the differences by hand)"
		t_begin
		t_exec "$F" "$EX4_WATER"
		t_end "water_plant"
		t_begin
		t_exec "$F" "$EX4_TEST"
		t_end "test_watering_system"
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/ft_first_exception.py]=1 [ex1/ft_raise_exception.py]=1
		[ex2/ft_different_errors.py]=1 [ex3/ft_custom_errors.py]=1
		[ex4/ft_finally_block.py]=1
	)
	extra=""
	while IFS= read -r f; do
		f=${f#./}
		[ -n "${EXPECTED[$f]}" ] || extra+="$f "
	done < <(cd "$DIR" && find ./ex[0-9]* -type f ! -path '*/__pycache__/*' ! -path '*/.mypy_cache/*' 2>/dev/null | sort)
	if [ -z "$extra" ]; then line_ok "files" "(only the requested files)"
	else
		line_warn "files" "files that are not requested (\"submit only the files requested\"):"
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
