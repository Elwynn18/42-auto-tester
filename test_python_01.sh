#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_01.sh - single-file tester for Python Module 1                  #
#                      (Code Cultivation - Object-Oriented Garden Systems)     #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_01.sh               -> test everything              #
#      bash ../test_python_01.sh 2 ex6         -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - Your classes are imported and tested directly (constructors, methods,     #
#    inheritance, validation...), and each file is also run as a program.      #
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
banner "Python Module 1 tester (Code Cultivation)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 1 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_01.XXXXXX)
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
# diff <expected> <got>          : first difference between two outputs
# ast <file> <calls> <imports> <only-functions 0|1>
#                                : forbidden calls / imports, classes, main block,
#                                  code outside functions and classes
# hints <file>                   : functions / methods without type hints
# snip <file> <python code>      : runs a test snippet that uses the helpers
#                                  below (results in $PT_RES, see "Test snippets")
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import contextlib
import copy
import gc
import importlib.util
import inspect
import io
import os
import re
import sys
import traceback
import types

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))


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


def load(path):
    path = os.path.abspath(path)
    sys.path.insert(0, os.path.dirname(path))
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def diff_text(exp, got):
    if exp == got:
        return ""
    el = exp.splitlines(keepends=True)
    gl = got.splitlines(keepends=True)
    i = 0
    while i < len(el) and i < len(gl) and el[i] == gl[i]:
        i += 1
    if not got:
        return 'prints nothing; expected "%s"' % short(exp)
    if i >= len(gl):
        return 'output stops after line %d; expected next: "%s"' % (i, short(el[i]))
    if i >= len(el):
        return 'extra output at line %d: "%s"' % (i + 1, short("".join(gl[i:])))
    return 'line %d: "%s"; expected "%s"' % (i + 1, short(gl[i]), short(el[i]))


def cmd_diff(exp_path, got_path):
    with open(exp_path, encoding="utf-8", errors="replace", newline="") as f:
        exp = f.read()
    with open(got_path, encoding="utf-8", errors="replace", newline="") as f:
        got = f.read()
    d = diff_text(exp, got)
    if d:
        print(d)
    return 1 if d else 0


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


def cmd_ast(path, calls, imports, only_functions):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src, path)
    except SyntaxError as e:
        print("SYNTAX %s %s" % (e.lineno, e.msg))
        return 0
    allowed = set(calls.split(","))
    mods = set(imports.split(","))
    mine = bound_names(tree)
    bnames = set(dir(builtins))

    def check(name, line):
        if (name in bnames and name not in mine and "*" not in allowed
                and name not in allowed and not is_exception(name)):
            print("CALL %s %s" % (name, line))

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            check(n.func.id, n.lineno)
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
                continue
            # "assign": a simple variable (no call), "code": runs something
            kind = "code"
            if isinstance(s, (ast.Assign, ast.AnnAssign)) and \
                    not any(isinstance(x, ast.Call) for x in ast.walk(s)):
                kind = "assign"
            print("TOP %s %s %s" % (s.lineno, kind,
                                    short(ast.unparse(s).split("\n")[0], 50)))
    return 0


def cmd_hints(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        a = fn.args
        miss = []
        typed = False
        for i, x in enumerate(a.posonlyargs + a.args):
            if i == 0 and x.arg in ("self", "cls"):
                continue
            if x.annotation is None:
                miss.append(x.arg)
            else:
                typed = True
        for x in a.kwonlyargs:
            if x.annotation is None:
                miss.append(x.arg)
            else:
                typed = True
        for p, x in (("*", a.vararg), ("**", a.kwarg)):
            if x is not None and x.annotation is None:
                miss.append(p + x.arg)
        # __init__(self, x: int) without "-> None" is accepted (as mypy does)
        if fn.returns is None and not (fn.name == "__init__" and typed):
            miss.append("return")
        if miss:
            print("MISS %s %s %s" % (fn.lineno, fn.name, ",".join(miss)))
    return 0


# ------------------------------ Test snippets ------------------------------- #
# A snippet is Python code run by "snip <file> <code>" with these helpers.
# Its results go to $PT_RES, one per line:
#   N          one test          F <msg>  failure       W <msg>  warning
#   I <msg>    note              T <msg>  info shown on the OK line
#   S <msg>    line skipped      C <msg>  what is running (shown after a timeout)
FILE = BASE = ""
MOD = None
IMPORT_OUT = ""
HIST = {}
KEEP = []
NOTED = set()


class Stop(Exception):
    pass


def res(kind, text=""):
    with open(os.environ["PT_RES"], "a", encoding="utf-8") as f:
        f.write(kind + " " + str(text).replace("\n", "\\n") + "\n")


def check(cond, text):
    res("N")
    if not cond:
        res("F", text)
    return bool(cond)


def fail(text):
    check(False, text)


def stop(text):
    fail(text)
    raise Stop()


def skip(text):
    res("S", text)
    raise Stop()


def warn(text):
    res("W", text)


def info(text):
    res("I", text)


def done(text):
    res("T", text)


def q(s, n=70):
    return '"%s"' % short(str(s), n)


def lit(v):
    return q(v, 30) if isinstance(v, str) else repr(v)


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def attrs(obj):
    try:
        return dict(vars(obj))
    except TypeError:
        return {}


def desc(obj):
    return ", ".join("%s=%r" % (k, v) for k, v in attrs(obj).items()
                     if is_num(v) or isinstance(v, str))


def keys_with(obj, value):
    """attributes of obj whose value is value (same kind: number / str)"""
    out = []
    for k, v in attrs(obj).items():
        if is_num(value) and is_num(v) and v == value:
            out.append(k)
        elif isinstance(value, str) and isinstance(v, str) and v == value:
            out.append(k)
    return out


def changed(before, after):
    """{attribute: (old, new)} for the numbers that changed"""
    return {k: (before[k], v) for k, v in after.items()
            if is_num(v) and k in before and is_num(before[k]) and v != before[k]}


def has_num(text, x):
    """x written in text (25 / 25.0 / 25.00 / rounded...)"""
    forms = {repr(x), "%.1f" % x, "%.2f" % x, "%g" % x, "%d" % round(x), "%d" % int(x)}
    for f in forms:
        if re.search(r"(?<![\d.])" + re.escape(f) + r"(?!\.?\d)", text):
            return True
    return False


def nums_in(text):
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", text)]


def has_text(text, s):
    return s.lower() in text.lower()


def capture(f, *args):
    """calls f(*args) → (returned value, printed output, exception)"""
    buf = io.StringIO()
    ret = exc = None
    try:
        with contextlib.redirect_stdout(buf):
            ret = f(*args)
    except BaseException as e:
        exc = e
    return ret, buf.getvalue(), exc


def fill(f, args, extra, name):
    """adds a value for the extra required parameters of f (with a note)"""
    try:
        sig = inspect.signature(f)
    except (TypeError, ValueError):
        return tuple(args)
    try:
        sig.bind(*args)
        return tuple(args)
    except TypeError:
        pass
    ps = [p for p in sig.parameters.values()
          if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
    req = [p.name for p in ps[len(args):] if p.default is p.empty]
    if not req or len(ps) < len(args):
        return tuple(args)
    if name not in NOTED:
        NOTED.add(name)
        info("%s has extra required parameter(s) %s: the tests give %s"
             % (name, ", ".join(req), lit(extra)))
    return tuple(args) + (extra,) * len(req)


def mod():
    """imports the file (once); its output at import goes to IMPORT_OUT"""
    global MOD, IMPORT_OUT
    if MOD is None:
        res("C", "importing " + BASE)
        m, IMPORT_OUT, exc = capture(load, FILE)
        if exc is not None:
            stop("importing %s raises %s" % (BASE, summary(exc)))
        MOD = m
    return MOD


def get_class(name, g=None):
    c = (g if g is not None else vars(mod())).get(name)
    if not isinstance(c, type):
        stop("no class %s in %s" % (name, BASE))
    return c


def adopt(obj, var, text):
    KEEP.append(obj)
    HIST[id(obj)] = (var, [text])
    return obj


def what(obj):
    """the calls made on obj: 'p = Plant("Rose", 15.0, 10); p.grow()'"""
    h = HIST.get(id(obj))
    if not h:
        return "a %s instance" % type(obj).__name__
    steps = h[1] if len(h[1]) <= 5 else h[1][:1] + ["…"] + h[1][-3:]
    return "; ".join(steps)


def make(cls, *args, var="p", extra=1, need=True):
    """creates cls(*args); make.out = what the constructor prints"""
    args = fill(cls, args, extra, cls.__name__ + "()")
    text = "%s(%s)" % (cls.__name__, ", ".join(lit(a) for a in args))
    res("C", text)
    obj, make.out, make.exc = capture(cls, *args)
    if make.exc is not None:
        if need:
            stop("%s raises %s" % (text, summary(make.exc)))
        make.text = text
        return None
    return adopt(obj, var, "%s = %s" % (var, text))


class Res:
    def __init__(self, ret, out, exc):
        self.ret, self.out, self.exc = ret, out, exc


def meth(obj, name, *args, need=True, extra=1, log=True):
    """calls obj.name(*args) → Res(ret, out, exc), saved in the history"""
    var = HIST.get(id(obj), ("p",))[0]
    f = getattr(obj, name, None)
    if not callable(f):
        stop("%s has no %s() method" % (type(obj).__name__, name))
    args = fill(f, args, extra, "%s.%s()" % (type(obj).__name__, name))
    text = "%s.%s(%s)" % (var, name, ", ".join(lit(a) for a in args))
    res("C", what(obj) + "; " + text)
    ret, out, exc = capture(f, *args)
    if log and id(obj) in HIST:
        HIST[id(obj)][1].append(text)
    if exc is not None and need:
        stop("%s raises %s" % (what(obj) + ("" if log else "; " + text), summary(exc)))
    return Res(ret, out, exc)


def get(obj, name):
    """value returned by a getter (not saved in the history)"""
    return meth(obj, name, log=False).ret


def show(obj):
    return meth(obj, "show").out


class Call:
    def __init__(self, obj, name, start, before):
        self.obj, self.name, self.start, self.end = obj, name, start, start
        self.before = before
        self.after = {}
        self.out = ""


class Run:
    pass


def run_main():
    """runs the file as "python3 <file>", with every method call recorded
    (r.calls: object, method name, its output, attributes before the call)"""
    path = FILE
    real = os.path.realpath(path)
    names = {}
    buf = io.StringIO()
    calls = []
    running = {}

    def prof(frame, event, arg):
        fn = frame.f_code.co_filename
        if fn not in names:
            names[fn] = os.path.realpath(fn) == real
        if not names[fn]:
            return
        if event == "call":
            try:
                obj = frame.f_locals.get("self")
            except Exception:
                obj = None
            c = Call(obj, frame.f_code.co_name, buf.tell(),
                     attrs(obj) if obj is not None else {})
            calls.append(c)
            running[id(frame)] = c
        elif event == "return":
            c = running.pop(id(frame), None)
            if c is not None:
                c.end = buf.tell()
                c.after = attrs(c.obj) if c.obj is not None else {}

    module = types.ModuleType("__main__")
    module.__file__ = path
    old_main, old_argv = sys.modules.get("__main__"), sys.argv
    sys.modules["__main__"] = module
    sys.argv = [path]
    res("C", "python3 " + BASE)
    exc = None
    try:
        with open(path, encoding="utf-8") as f:
            code = compile(f.read(), path, "exec")
        with contextlib.redirect_stdout(buf):
            sys.setprofile(prof)
            try:
                exec(code, module.__dict__)
            finally:
                sys.setprofile(None)
    except SystemExit as e:
        if e.code not in (None, 0):
            exc = e
    except BaseException as e:
        exc = e
    sys.modules["__main__"] = old_main
    sys.argv = old_argv
    r = Run()
    r.out, r.exc, r.calls, r.g = buf.getvalue(), exc, calls, module.__dict__
    r.prog = "python3 " + BASE
    for c in calls:
        c.out = r.out[c.start:c.end]
    KEEP.append(r)
    return r


def instances(r, cls):
    """instances of cls seen during the run (method calls + still alive)"""
    seen, out = set(), []
    objs = [c.obj for c in r.calls]
    for o in gc.get_objects():
        try:
            if isinstance(o, cls):
                objs.append(o)
        except Exception:
            pass
    for o in objs:
        if isinstance(o, cls) and id(o) not in seen:
            seen.add(id(o))
            out.append(o)
    return out


def calls_of(r, name, cls=None):
    return [c for c in r.calls if c.name == name and c.obj is not None
            and (cls is None or isinstance(c.obj, cls))]


def differs(text, out, exp):
    """'<call> prints ...: line 2: "..."; the example shows "..."' (first difference)"""
    d = diff_text(exp, out).replace("; expected", "; the example shows")
    return "%s: %s" % (text, d)


def program(r):
    """the program must run without error"""
    if r.exc is not None:
        stop("%s raises %s" % (r.prog, summary(r.exc)))
    check(r.out.strip() != "", "%s prints nothing" % r.prog)


def example(r, exp):
    """compares the output of the program with the subject example"""
    if r.exc is not None:
        skip("the program does not run (see above)")
    res("N")
    d = diff_text(exp, r.out)
    if not d:
        done("(same as the subject example)")
        return True
    warn("differs from the subject example: " + d)
    info("(the subject only gives an example: check the differences by hand)")
    return False


def cmd_snip(path, code):
    global FILE, BASE
    FILE = os.path.abspath(path)
    BASE = os.path.basename(path)
    sys.path.insert(0, os.path.dirname(FILE))
    try:
        exec(compile(code, "<test>", "exec"), globals())
    except Stop:
        pass
    except BaseException as e:
        res("F", "unexpected error during the test: " + summary(e))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"diff": cmd_diff, "ast": cmd_ast, "hints": cmd_hints,
              "snip": cmd_snip}[cmd](*sys.argv[2:]))
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
t_begin() { T_FAILS=(); T_WARNS=(); T_NOTES=(); T_N=0; T_INFO=""; T_SKIP=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
# t_end <label>: OK, KO (✗ lines), !! (warnings only) or -- (skipped)
t_end() {
	local m i=0
	if t_ok && [ -n "$T_SKIP" ] && [ $T_N -eq 0 ]; then
		line_skip "$1" "$T_SKIP"
		return
	fi
	if t_ok && [ ${#T_WARNS[@]} -eq 0 ]; then
		line_ok "$1" "${T_INFO:-($T_N tests)}"
	elif t_ok; then
		line_warn "$1" "${T_WARNS[0]}"
		for m in "${T_WARNS[@]:1:5}"; do note "!! $m"; done
	else
		line_ko "$1"
		for m in "${T_FAILS[@]}"; do
			i=$((i + 1))
			if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
			msg "$m"
		done
		for m in "${T_WARNS[@]:0:3}"; do note "!! $m"; done
	fi
	for m in "${T_NOTES[@]}"; do note "$m"; done
	[ -n "$T_SKIP" ] && note "$T_SKIP"
}

# t_snip <file> [code prefix] <<'PY' ... PY
# Runs a test snippet (Python code on stdin, after the optional prefix, with the
# pt.py helpers) in a new python3 process, and adds its results to the current line.
t_snip() {
	local code l k m last=""
	code="${2:+$2$'\n'}$(cat)"
	[ $T_TIMEOUT -eq 1 ] && return 1
	: > "$TMP/res"
	run_py /dev/null snip "$1" "$code"
	while IFS= read -r l; do
		k=${l%% *}; m=${l#* }
		case $k in
			N) T_N=$((T_N + 1)) ;;
			F) t_fail "$m" ;;
			W) T_WARNS+=("$m") ;;
			I) T_NOTES+=("$m") ;;
			T) T_INFO=$m ;;
			S) T_SKIP=$m ;;
			C) last=$m ;;
		esac
	done < "$TMP/res"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "${last:-the test}: infinite loop or too slow (more than 10 s)"
	elif [ $RC -ne 0 ]; then
		t_fail "${last:+$last: }python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"
	fi
}

# snip_line <label> <file> [code prefix] <<'PY' ... PY : one line = one snippet
snip_line() {
	t_begin
	t_snip "$2" "$3"
	t_end "$1"
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

# hints_line <file>: every parameter (except self / cls) and every return
# must have a type hint ("All functions and methods must include type hints")
hints_line() {
	local base l n w miss=() m
	base=$(basename "$1")
	while read -r _ l n w; do
		miss+=("$base:$l: $n(): no type hint for ${w//,/, }")
	done < <(python3 -I "$PT" hints "$1")
	if [ ${#miss[@]} -eq 0 ]; then line_ok "type hints"
	else
		line_ko "type hints"
		for m in "${miss[@]:0:6}"; do msg "$m"; done
		[ ${#miss[@]} -gt 6 ] && msg "… (${#miss[@]} functions in total)"
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

# static_checks <file> <allowed calls> <label of the authorized list> <main 0|1> <classes...>
# Lines "structure" (requested classes, if __name__ == "__main__": block, code
# outside classes / functions) and "authorized" (functions and imports).
# main = 1: the main block is required and nothing may run outside it;
# main = 0: code outside it is only a warning (it runs when the file is imported).
# typing / __future__ imports are accepted (type hints are required).
static_checks() {
	local f=$1 calls=$2 label=$3 need=$4 base kind a b c main=0 cls=() top=() bad=() ko=() m
	shift 4
	base=$(basename "$f")
	while read -r kind a b c; do
		case $kind in
			CLASS) cls+=("$a") ;;
			MAIN) main=1 ;;
			TOP) [ "$b" = code ] && top+=("$base:$a: $c") ;;
			CALL) bad+=("$a() (line $b)") ;;
			IMPORT) bad+=("import $a (line $b)") ;;
		esac
	done < <(python3 -I "$PT" ast "$f" "$calls" typing,__future__ 1)
	for a in "$@"; do
		[[ " ${cls[*]} " == *" $a "* ]] || ko+=("$base: no class $a (the name must match exactly)")
	done
	if [ "$need" = 1 ]; then
		[ $main -eq 0 ] && ko+=("$base: no if __name__ == \"__main__\": block (required by the subject)")
		for m in "${top[@]}"; do ko+=("$m: code outside the if __name__ == \"__main__\": block"); done
	fi
	if [ ${#ko[@]} -gt 0 ]; then
		line_ko "structure"
		for m in "${ko[@]:0:6}"; do msg "$m"; done
	elif [ ${#top[@]} -gt 0 ]; then
		line_warn "structure" "code outside classes and functions (it runs when the file is imported):"
		for m in "${top[@]:0:4}"; do note "$m"; done
		note "put your test code in an if __name__ == \"__main__\": block"
	else
		a=$(printf '%s, ' "${cls[@]}")
		a="classes: ${a%, }"
		[ ${#cls[@]} -eq 0 ] && a="no class"
		[ $main -eq 1 ] && a+=", main block"
		line_ok "structure" "($a)"
	fi
	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized" "($label)"
	else
		line_ko "authorized"
		msg "forbidden: ${bad[*]}"
		note "authorized: $label"
	fi
}

# common_checks <exercise dir> <file> <allowed calls> <label> <main 0|1> <classes...>
common_checks() {
	local ex=$1 file=$2
	shift 2
	flake8_line "$ex/$file"
	static_checks "$WORK/$ex/$file" "$@"
	hints_line "$WORK/$ex/$file"
	mypy_line "$ex/$file"
}

# ================================ Exercises ================================= #

# --------------------------- ex0: ft_garden_intro --------------------------- #
if wanted 0; then
	section "ex0 - ft_garden_intro"
	if ex_files ex0 ft_garden_intro.py; then
		F="$WORK/ex0/ft_garden_intro.py"
		common_checks ex0 ft_garden_intro.py print "print()" 1

		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
mod()
check(IMPORT_OUT == "", "importing %s prints %s: the display must only happen in "
      "the if __name__ == \"__main__\": block" % (BASE, q(IMPORT_OUT)))
with open(FILE, encoding="utf-8") as f:
    src = f.read()
miss = [v for v in ("name", "height", "age") if v not in bound_names(ast.parse(src))]
if miss:
    warn("no variable named %s (subject: \"store the plant information in simple "
         "variables: name, height, and age\")" % ", ".join(miss))
if not src.startswith("#!"):
    info("no shebang line: the evaluation will ask you to add one live "
         "(e.g. #!/usr/bin/env python3)")
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
EX = ("=== Welcome to My Garden ===\nPlant: Rose\nHeight: 25cm\nAge: 30 days\n\n"
      "=== End of Program ===\n")
if r.exc is not None:
    skip("the program does not run (see above)")
res("N")
if r.out == EX:
    done("(same as the subject example)")
elif re.fullmatch(r"=== Welcome to My Garden ===\nPlant: .+\nHeight: \d+(\.\d+)?cm\n"
                  r"Age: \d+ days\n\n=== End of Program ===\n", r.out):
    done("(format of the subject example)")
else:
    warn("differs from the subject example: " + diff_text(EX, r.out))
    info("(no strict output check for this exercise: \"mimic the output display\")")
PY
	fi
fi

# --------------------------- ex1: ft_garden_data ---------------------------- #
if wanted 1; then
	section "ex1 - ft_garden_data"
	if ex_files ex1 ft_garden_data.py; then
		F="$WORK/ex1/ft_garden_data.py"
		common_checks ex1 ft_garden_data.py print "print()" 0 Plant

		# The program: at least 3 plants, displayed with show()
		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
P = get_class("Plant", r.g)
check(callable(getattr(P, "show", None)), "class Plant has no show() method")
plants = instances(r, P)
check(len(plants) >= 3, "%s creates %d Plant instance(s); expected at least 3 plants"
      % (r.prog, len(plants)))
shows = calls_of(r, "show", P)
shown = {id(c.obj) for c in shows}
if len(shown) < 3 and callable(getattr(P, "show", None)):
    warn("show() is called for %d plant(s) only: the plants should be displayed "
         "with the show() method" % len(shown))
outs = {c.out for c in shows}
if len(shows) >= 3:
    check(len(outs) >= 3, "the show() calls only print %d different text(s) (%s): "
          "expected 3 different plants" % (len(outs), ", ".join(q(o, 40) for o in outs)))
for c in shows:
    strs = [v for v in c.before.values() if isinstance(v, str) and v.strip()]
    nums = [v for v in c.before.values() if is_num(v)]
    if strs:
        check(any(has_text(c.out, s) for s in strs), "show() on a plant (%s) prints %s; "
              "expected its name" % (desc(c.obj), q(c.out)))
    if len(nums) >= 2:
        check(sum(has_num(c.out, n) for n in nums) >= 2, "show() on a plant (%s) prints %s; "
              "expected its height and age" % (desc(c.obj), q(c.out)))
PY

		# show() on plants with other values: it must use the attributes
		snip_line "show()" "$F" <<'PY'
r = run_main()
P = get_class("Plant", r.g)
plants = [o for o in instances(r, P) if attrs(o)]
if not plants:
    skip("no Plant instance with attributes found in the program")
base = plants[0]
strs = [k for k, v in attrs(base).items() if isinstance(v, str)]
nums = [k for k, v in attrs(base).items() if is_num(v)]
if not strs or len(nums) < 2:
    skip("name / height / age attributes not found (%s)" % desc(base))
made = []
for name, vals in [("Tulip", (12, 7)), ("Rosé des prés", (0, 1)), ("Baobab", (2500, 3650)),
                   ("A", (999, 42)), ("Cherry tomato", (3, 64))]:
    p = copy.copy(base)
    vals = vals + tuple(range(5, 5 + len(nums)))
    sets = ["p.%s = %s" % (strs[0], lit(name))]
    setattr(p, strs[0], name)
    for k, v in zip(nums, vals):
        setattr(p, k, v)
        sets.append("p.%s = %r" % (k, v))
    adopt(p, "p", "; ".join(sets))
    made.append((p, name, vals[:2]))
for p, name, vals in made:
    out = show(p)
    check(has_text(out, name) and has_num(out, vals[0]) and has_num(out, vals[1]),
          "%s prints %s; expected %s, %d and %d" % (what(p), q(out), q(name), vals[0], vals[1]))
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
if r.exc is not None:
    skip("the program does not run (see above)")
P = get_class("Plant", r.g)
EX = ("=== Garden Plant Registry ===\nRose: 25cm, 30 days old\nSunflower: 80cm, 45 days old\n"
      "Cactus: 15cm, 120 days old\n")
res("N")
lines = r.out.splitlines()
bad = [c.out for c in calls_of(r, "show", P)
       if not re.fullmatch(r"\S.*: \d+(\.\d+)?cm, \d+ days old\n", c.out)]
if r.out == EX:
    done("(same as the subject example)")
elif not lines or lines[0] != "=== Garden Plant Registry ===":
    warn('first line %s; the example shows "=== Garden Plant Registry ==="'
         % q(lines[0] if lines else ""))
elif bad:
    warn('show() prints %s; the example shows "Rose: 25cm, 30 days old"' % q(bad[0]))
else:
    done("(format of the subject example)")
PY
	fi
fi

# --------------------------- ex2: ft_plant_growth --------------------------- #
if wanted 2; then
	section "ex2 - ft_plant_growth"
	if ex_files ex2 ft_plant_growth.py; then
		F="$WORK/ex2/ft_plant_growth.py"
		common_checks ex2 ft_plant_growth.py print,range,round "print(), range(), round()" 0 Plant

		snip_line "Plant class" "$F" <<'PY'
P = get_class("Plant")
for m in ("grow", "age"):
    check(callable(getattr(P, m, None)), "class Plant has no %s() method" % m)
if not callable(getattr(P, "show", None)):
    warn("class Plant has no show() method (reuse your Plant class from exercise 1)")
PY

		# The program: a week of growth, then the total increase
		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
P = get_class("Plant", r.g)
grows, ages = calls_of(r, "grow", P), calls_of(r, "age", P)
check(grows, "%s never calls grow() on a plant: expected a week of growth" % r.prog)
check(ages, "%s never calls age() on a plant: expected a week of growth" % r.prog)
if grows:
    per = {}
    for c in grows:
        per.setdefault(id(c.obj), []).append(c)
    gl = max(per.values(), key=len)
    if len(gl) < 7:
        warn("grow() is called %d time(s) for a plant: a week is 7 days "
             "(fine if your grow() takes a number of days)" % len(gl))
    p = gl[0].obj
    keys = {k for c in gl for k, (x, y) in changed(c.before, c.after).items() if y > x}
    diffs = [attrs(p)[k] - gl[0].before[k] for k in keys
             if is_num(attrs(p).get(k)) and is_num(gl[0].before.get(k))]
    tail = "\n".join(r.out.splitlines()[-3:])
    if diffs and not any(abs(n - d) < 0.051 for n in nums_in(tail) for d in diffs):
        warn("the end of the output (%s) does not show the growth of the week "
             "(the plant grew by %s)" % (q(tail, 60), " or ".join("%g" % round(d, 2) for d in diffs)))
PY

		# grow() and age() on a copy of a plant of the program
		snip_line "grow() / age()" "$F" <<'PY'
r = run_main()
P = get_class("Plant", r.g)
grown = [c.obj for c in calls_of(r, "grow", P)]
plants = grown or [o for o in instances(r, P) if attrs(o)]
if not plants:
    skip("no Plant instance found in the program")
base = plants[0]
try:
    p, o = copy.deepcopy(base), copy.deepcopy(base)
except Exception:
    p, o = copy.copy(base), copy.copy(base)
adopt(p, "p", "p = (a plant of your program: %s)" % short(desc(base), 60))
adopt(o, "o", "o = (another copy)")
b = attrs(p)
meth(p, "grow")
up = [k for k, (x, y) in changed(b, attrs(p)).items() if y > x]
check(up, "%s changes no number attribute; expected the height to increase" % what(p))
b = attrs(p)
meth(p, "age")
ups = {k: y - x for k, (x, y) in changed(b, attrs(p)).items() if y > x}
check(ups, "%s changes no number attribute; expected the age to increase" % what(p))
if ups and not any(abs(v - 1) < 1e-9 for v in ups.values()):
    warn("%s: %s; the example ages 1 day per day"
         % (what(p), ", ".join("%s +%g" % kv for kv in ups.items())))
if up:
    k = up[0]
    for i in range(6):
        h = attrs(p)[k]
        meth(p, "grow")
        if not check(attrs(p)[k] >= h, "%s: %s goes from %r to %r; a plant should not shrink"
                     % (what(p), k, h, attrs(p)[k])):
            break
    check(attrs(o) == attrs(base), "%s also changes another plant (o: %s)"
          % (what(p), short(desc(o), 50)))
    if callable(getattr(p, "show", None)):
        out = show(p)
        if not has_num(out, attrs(p)[k]):
            warn("%s prints %s; expected the new height %r" % (what(p), q(out), attrs(p)[k]))
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
if r.exc is not None:
    skip("the program does not run (see above)")
res("N")
lines = r.out.splitlines()
days = [ln for ln in lines if re.fullmatch(r"=== Day \d+ ===", ln)]
if not lines or lines[0] != "=== Garden Plant Growth ===":
    warn('first line %s; the example shows "=== Garden Plant Growth ==="'
         % q(lines[0] if lines else ""))
elif len(days) != 7:
    warn('%d "=== Day N ===" line(s); the example shows the 7 days of the week' % len(days))
elif not re.fullmatch(r"Growth this week: \d+(\.\d+)?cm", lines[-1]):
    warn('last line %s; the example shows "Growth this week: 5.6cm"' % q(lines[-1]))
else:
    done("(format of the subject example)")
PY
	fi
fi

# --------------------------- ex3: ft_plant_factory -------------------------- #
if wanted 3; then
	section "ex3 - ft_plant_factory"
	if ex_files ex3 ft_plant_factory.py; then
		F="$WORK/ex3/ft_plant_factory.py"
		common_checks ex3 ft_plant_factory.py print,range,round "print(), range(), round()" 0 Plant

		# Plant(name, height, age) then show()
		snip_line "constructor" "$F" <<'PY'
P = get_class("Plant")
fmt = None
for name, h, a in [("Rose", 25.0, 30), ("Oak", 200.0, 365), ("Cactus", 5.0, 90),
                   ("Sunflower", 80.0, 45), ("Fern", 15.0, 120), ("Moss", 0.0, 0),
                   ("Baobab", 2500.5, 3650), ("Rosé", 12, 7), ("Cherry tomato", 1.5, 2),
                   ("X", 0.5, 100000)]:
    p = make(P, name, h, a)
    out = show(p)
    ok = has_text(out, name) and has_num(out, h) and has_num(out, a)
    check(ok, "%s prints %s; expected the name %s, the height %s and the age %s"
          % (what(p), q(out), q(name), h, a))
    exp = "%s: %.1fcm, %d days old\n" % (name, h, a)
    if ok and isinstance(h, float) and out != exp and fmt is None:
        fmt = differs(what(p), out, exp)
if fmt:
    warn(fmt)
PY

		# Two plants do not share their data
		snip_line "independent" "$F" <<'PY'
P = get_class("Plant")
a = make(P, "Rose", 25.0, 30, var="a")
b = make(P, "Oak", 200.0, 365, var="b")
ctx = "a = Plant(\"Rose\", 25.0, 30); b = Plant(\"Oak\", 200.0, 365); "
out = meth(a, "show", log=False).out
check(has_text(out, "Rose") and not has_text(out, "Oak") and has_num(out, 25.0) and has_num(out, 30),
      ctx + "a.show() prints %s; expected the data of a (Rose, 25.0, 30)" % q(out))
out = meth(b, "show", log=False).out
check(has_text(out, "Oak") and has_num(out, 200.0) and has_num(out, 365),
      ctx + "b.show() prints %s; expected the data of b (Oak, 200.0, 365)" % q(out))
if callable(getattr(b, "grow", None)):
    before = meth(a, "show", log=False).out
    meth(b, "grow", log=False)
    out = meth(a, "show", log=False).out
    check(out == before, ctx + "b.grow(); a.show() prints %s; expected %s (a unchanged)"
          % (q(out), q(before)))
PY

		# Ready to use right after the construction (grow / age)
		snip_line "grow() / age()" "$F" <<'PY'
P = get_class("Plant")
if not callable(getattr(P, "grow", None)) or not callable(getattr(P, "age", None)):
    res("N")
    warn("class Plant has no grow() / age() method (improve your Plant class "
         "from the previous exercises)")
    raise Stop()
p = make(P, "Rose", 25.0, 30)
b = attrs(p)
meth(p, "grow")
up = [k for k, (x, y) in changed(b, attrs(p)).items() if y > x]
check(up, "%s changes no number attribute; expected the height to increase" % what(p))
b = attrs(p)
meth(p, "age")
ups = {k: y - x for k, (x, y) in changed(b, attrs(p)).items() if y > x}
check(ups, "%s changes no number attribute; expected the age to increase" % what(p))
out = show(p)
if up and not has_num(out, attrs(p)[up[0]]):
    warn("%s prints %s; expected the new height %r" % (what(p), q(out), attrs(p)[up[0]]))
PY

		# The program: at least 5 different plants
		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
P = get_class("Plant", r.g)
plants = instances(r, P)
check(len(plants) >= 5, "%s creates %d Plant instance(s); expected at least 5 plants"
      % (r.prog, len(plants)))
data = {tuple(sorted((k, repr(v)) for k, v in attrs(o).items())) for o in plants}
if len(plants) >= 5:
    check(len(data) >= 5, "%s creates %d plants but only %d different ones; expected "
          "\"varying characteristics\"" % (r.prog, len(plants), len(data)))
shown = {id(c.obj) for c in calls_of(r, "show", P)}
if len(shown) < 5:
    warn("show() is called for %d plant(s): \"display all created plants\"" % len(shown))
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
EX = ("=== Plant Factory Output ===\nCreated: Rose: 25.0cm, 30 days old\n"
      "Created: Oak: 200.0cm, 365 days old\nCreated: Cactus: 5.0cm, 90 days old\n"
      "Created: Sunflower: 80.0cm, 45 days old\nCreated: Fern: 15.0cm, 120 days old\n")
if r.exc is not None:
    skip("the program does not run (see above)")
res("N")
lines = r.out.splitlines()
created = [ln for ln in lines if re.fullmatch(r"Created: \S.*: \d+(\.\d+)?cm, \d+ days old", ln)]
if r.out == EX:
    done("(same as the subject example)")
elif lines and lines[0] == "=== Plant Factory Output ===" and len(created) >= 5 \
        and len(created) == len(lines) - 1:
    done("(format of the subject example)")
else:
    warn("differs from the subject example: " + diff_text(EX, r.out))
    info("(the subject only gives an example: check the differences by hand)")
PY
	fi
fi

# -------------------------- ex4: ft_garden_security ------------------------- #
if wanted 4; then
	section "ex4 - ft_garden_security"
	if ex_files ex4 ft_garden_security.py; then
		F="$WORK/ex4/ft_garden_security.py"
		common_checks ex4 ft_garden_security.py print,range,round "print(), range(), round()" 0 Plant

		snip_line "methods" "$F" <<'PY'
P = get_class("Plant")
for m in ("set_height", "set_age", "get_height", "get_age"):
    check(callable(getattr(P, m, None)), "class Plant has no %s() method" % m)
if not callable(getattr(P, "show", None)):
    warn("class Plant has no show() method (improve your Plant class "
         "from the previous exercises)")
PY

		# Getters / setters with valid values
		snip_line "get / set" "$F" <<'PY'
P = get_class("Plant")
p = make(P, "Rose", 15.0, 10)
for g, exp in (("get_height", 15.0), ("get_age", 10)):
    v = get(p, g)
    check(v == exp, "%s; p.%s() returns %r; expected %r" % (what(p), g, v, exp))
for s, g, v in [("set_height", "get_height", 25), ("set_age", "get_age", 30),
                ("set_height", "get_height", 12.5), ("set_age", "get_age", 365),
                ("set_height", "get_height", 100000.0), ("set_age", "get_age", 1),
                ("set_height", "get_height", 25.0), ("set_age", "get_age", 30)]:
    meth(p, s, v)
    got = get(p, g)
    check(got == v, "%s; p.%s() returns %r; expected %r" % (what(p), g, got, v))
if callable(getattr(p, "show", None)):
    out = show(p)
    check(has_text(out, "Rose") and has_num(out, 25.0) and has_num(out, 30),
          "%s prints %s; expected Rose, 25.0 and 30" % (what(p), q(out)))
z = make(P, "Moss", 3.0, 4, var="z")
for s, g in (("set_height", "get_height"), ("set_age", "get_age")):
    meth(z, s, 0)
    got = get(z, g)
    res("N")
    if got != 0:
        warn("%s; z.%s() returns %r: 0 is not negative, it should probably be accepted"
             % (what(z), g, got))
PY

		# Negative values: error message printed, value unchanged
		snip_line "validation" "$F" <<'PY'
P = get_class("Plant")
p = make(P, "Rose", 15.0, 10)
fmt = None
for s, g, bad, keep, word in [("set_height", "get_height", -5, 15.0, "height"),
                              ("set_age", "get_age", -1, 10, "age"),
                              ("set_height", "get_height", -0.1, 15.0, "height"),
                              ("set_age", "get_age", -365, 10, "age"),
                              ("set_height", "get_height", -100000, 15.0, "height")]:
    rr = meth(p, s, bad, need=False)
    if rr.exc is not None:
        fail("%s raises %s; expected an error message printed by the class (value unchanged)"
             % (what(p), summary(rr.exc)))
        continue
    check(rr.out.strip() != "", "%s prints nothing; expected an error message" % what(p))
    got = get(p, g)
    check(got == keep, "%s; p.%s() returns %r; expected %r (value unchanged)"
          % (what(p), g, got, keep))
    exp = "Rose: Error, %s can't be negative" % word
    if rr.out.strip() and exp not in rr.out and fmt is None:
        fmt = "%s prints %s; the example shows %s" % (what(p), q(rr.out), q(exp))
if callable(getattr(p, "show", None)):
    out = show(p)
    check(has_num(out, 15.0) and has_num(out, 10), "%s prints %s; expected 15.0 and 10 "
          "(the invalid values are rejected)" % (what(p), q(out)))
o = make(P, "Oak", 200.0, 365, var="o")
rr = meth(o, "set_height", -1, need=False)
if rr.exc is None and rr.out.strip() and not has_text(rr.out, "Oak") and fmt is None:
    fmt = "%s prints %s; the example shows the plant name (\"Oak: Error, ...\")" \
        % (what(o), q(rr.out))
if fmt:
    warn(fmt)
PY

		# Invalid values given to the constructor
		snip_line "constructor" "$F" <<'PY'
P = get_class("Plant")
quiet = None
for args, g, word in [(("Bad", -5.0, 10), "get_height", "height"),
                      (("Bad", 5.0, -3), "get_age", "age"),
                      (("Bad", -1.5, -1), "get_height", "height"),
                      (("Bad", -1.5, -1), "get_age", "age")]:
    p = make(P, *args, need=False)
    if p is None:
        fail("%s raises %s; expected an error message, and the plant created with "
             "default values" % (make.text, summary(make.exc)))
        continue
    v = get(p, g)
    check(is_num(v) and v >= 0, "%s; p.%s() returns %r; expected %s that is not "
          "negative (a default value)" % (what(p), g, v, "an age" if word == "age" else "a height"))
    if not make.out.strip() and quiet is None:
        quiet = "%s prints nothing: the subject asks for an error message " \
                "for invalid values" % what(p)
p = make(P, "Good", 1.0, 2)
v = get(p, "get_height"), get(p, "get_age")
check(v == (1.0, 2), "%s; get_height(), get_age() return %r, %r; expected 1.0, 2"
      % (what(p), v[0], v[1]))
if quiet:
    warn(quiet)
PY

		# Protected attributes: _height (not height, not __height)
		snip_line "protected" "$F" <<'PY'
P = get_class("Plant")
p = make(P, "Rose", 17.5, 11)
for value, word in ((17.5, "height"), (11, "age")):
    ks = keys_with(p, value)
    if not ks:
        warn("no attribute of p stores the %s %r (%s): check by hand that it is protected"
             % (word, value, short(desc(p), 50)))
        continue
    for k in ks:
        if re.match(r"_[A-Za-z]\w*__", k):
            fail("%s: the %s is stored in %s, this is name mangling (__); expected the "
                 "protected convention (one underscore: _%s)" % (what(p), word, k, word))
        else:
            check(k.startswith("_"), "%s: the %s is stored in the public attribute p.%s; "
                  "expected a protected attribute (_%s)" % (what(p), word, k, k))
pub = [k for k in keys_with(p, "Rose") if not k.startswith("_")]
if pub:
    warn("the name is stored in the public attribute p.%s (\"prevent your class attributes "
         "from being used directly\")" % pub[0])
PY

		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
P = get_class("Plant", r.g)
neg = [c for c in r.calls if c.name in ("set_height", "set_age")]
check(neg, "%s never calls set_height() / set_age()" % r.prog)
if not re.search("error", r.out, re.I):
    warn("no error message in the output: the example shows rejected negative values")
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
example(r, "=== Garden Security System ===\nPlant created: Rose: 15.0cm, 10 days old\n\n"
        "Height updated: 25cm\nAge updated: 30 days\n\n"
        "Rose: Error, height can't be negative\nHeight update rejected\n"
        "Rose: Error, age can't be negative\nAge update rejected\n\n"
        "Current state: Rose: 25.0cm, 30 days old\n")
PY
	fi
fi

# ---------------------------- ex5: ft_plant_types --------------------------- #
# Shared by ex5 and ex6: inheritance and super() in Flower / Tree / Vegetable / Seed
IFS= read -r -d '' SUPER_SNIP <<'PY'
with open(FILE, encoding="utf-8") as f:
    tree = ast.parse(f.read())
cdefs = {n.name: n for n in tree.body if isinstance(n, ast.ClassDef)}
if "Plant" not in cdefs:
    skip("no class Plant")
pm = {f.name for f in cdefs["Plant"].body if isinstance(f, ast.FunctionDef)}
for cn in SUBS:
    if cn not in cdefs:
        continue
    ms = {f.name: f for f in cdefs[cn].body if isinstance(f, ast.FunctionDef)}
    sup = {n for n, f in ms.items()
           if any(isinstance(x, ast.Call) and isinstance(x.func, ast.Name)
                  and x.func.id == "super" for x in ast.walk(f))}
    check(sup, "class %s never calls super(): expected to call the parent methods "
          "with super()" % cn)
    if "__init__" in ms and "__init__" not in sup:
        warn("%s.__init__() does not call super().__init__(): common plant code "
             "duplicated?" % cn)
    for n in sorted(ms):
        if n in pm and n not in sup and not n.startswith("_"):
            warn("%s.%s() overrides Plant.%s() without super(): common plant code "
                 "duplicated?" % (cn, n, n))
PY

if wanted 5; then
	section "ex5 - ft_plant_types"
	if ex_files ex5 ft_plant_types.py; then
		F="$WORK/ex5/ft_plant_types.py"
		common_checks ex5 ft_plant_types.py super,print,range,round \
			"super(), print(), range(), round()" 0 Plant Flower Tree Vegetable

		snip_line "inheritance" "$F" <<'PY'
M = mod()
P = get_class("Plant")
for m in ("show", "grow", "age"):
    check(callable(getattr(P, m, None)), "class Plant has no %s() method (start with your "
          "Plant class from the previous exercise)" % m)
for n, m in (("Flower", "bloom"), ("Tree", "produce_shade"), ("Vegetable", None)):
    c = getattr(M, n, None)
    if not isinstance(c, type):
        fail("no class %s in %s" % (n, BASE))
        continue
    check(issubclass(c, P) and c is not P, "class %s does not inherit from Plant; "
          "expected class %s(Plant)" % (n, n))
    if m:
        check(callable(getattr(c, m, None)), "class %s has no %s() method" % (n, m))
PY

		snip_line "super()" "$F" "SUBS = ('Flower', 'Tree', 'Vegetable')" <<< "$SUPER_SNIP"

		snip_line "Flower" "$F" <<'PY'
P, Fl = get_class("Plant"), get_class("Flower")
f = make(Fl, "Rose", 15.0, 10, "red", var="f")
check(isinstance(f, P), "%s is not a Plant" % what(f))
ks = keys_with(f, "red")
check(ks, "%s: no attribute of f stores the color \"red\" (%s)" % (what(f), short(desc(f), 50)))
if ks and not any(k.lstrip("_") == "color" for k in ks):
    warn("the color is stored in f.%s; the subject calls it color" % ks[0])
base = show(make(P, "Rose", 15.0, 10, var="b"))
out1 = show(f)
check(base.strip() and base in out1, "%s prints %s; expected the standard Plant output "
      "%s, then the color" % (what(f), q(out1), q(base)))
check(has_text(out1, "red"), "%s prints %s; expected the color \"red\"" % (what(f), q(out1)))
b0 = attrs(f)
meth(f, "bloom")
out2 = show(f)
check(out2 != out1 or attrs(f) != b0, "%s: bloom() changes nothing; expected the "
      "flower to bloom" % what(f))
if out2 == out1:
    warn("%s prints the same text before and after bloom()" % what(f))
e1 = base + " Color: red\n Rose has not bloomed yet\n"
e2 = base + " Color: red\n Rose is blooming beautifully!\n"
if out1 != e1:
    warn(differs("f.show()", out1, e1))
elif out2 != e2:
    warn(differs("f.bloom(); f.show()", out2, e2))
g = make(Fl, "Tulip", 8.5, 3, "yellow", var="g")
out = show(g)
check(has_text(out, "Tulip") and has_text(out, "yellow") and not has_text(out, "red")
      and has_num(out, 8.5) and has_num(out, 3),
      "%s prints %s; expected Tulip, 8.5, 3 and yellow" % (what(g), q(out)))
b0 = attrs(g)
meth(g, "grow")
meth(g, "age")
check(changed(b0, attrs(g)), "%s changes nothing: the inherited grow() / age() should work"
      % what(g))
PY

		snip_line "Tree" "$F" <<'PY'
P, T = get_class("Plant"), get_class("Tree")
t = make(T, "Oak", 200.0, 365, 5.0, var="t")
check(isinstance(t, P), "%s is not a Plant" % what(t))
ks = keys_with(t, 5.0)
check(ks, "%s: no attribute of t stores the trunk diameter 5.0 (%s)"
      % (what(t), short(desc(t), 50)))
if ks and not any(k.lstrip("_") == "trunk_diameter" for k in ks):
    warn("the trunk diameter is stored in t.%s; the subject calls it trunk_diameter" % ks[0])
base = show(make(P, "Oak", 200.0, 365, var="b"))
out = show(t)
check(base.strip() and base in out, "%s prints %s; expected the standard Plant output %s, "
      "then the trunk diameter" % (what(t), q(out), q(base)))
check(has_num(out.replace(base, "", 1), 5.0), "%s prints %s; expected the trunk diameter 5.0"
      % (what(t), q(out)))
fmt = None
e = base + " Trunk diameter: 5.0cm\n"
if out != e:
    fmt = differs("t.show()", out, e)
rr = meth(t, "produce_shade")
if not rr.out.strip() and rr.ret is None:
    warn("%s prints nothing and returns None: what does the shade look like?" % what(t))
e = "Tree Oak now produces a shade of 200.0cm long and 5.0cm wide.\n"
if rr.out.strip() and rr.out != e and fmt is None:
    fmt = differs("t.produce_shade()", rr.out, e)
u = make(T, "Pine", 350.5, 1000, 12.5, var="u")
out = show(u)
check(has_text(out, "Pine") and has_num(out, 350.5) and has_num(out, 1000) and has_num(out, 12.5),
      "%s prints %s; expected Pine, 350.5, 1000 and 12.5" % (what(u), q(out)))
rr = meth(u, "produce_shade")
if rr.out.strip() and not (has_text(rr.out, "Pine") or has_num(rr.out, 12.5)) and fmt is None:
    fmt = "%s prints %s: nothing about this tree (Pine, 12.5)?" % (what(u), q(rr.out))
if fmt:
    warn(fmt)
PY

		snip_line "Vegetable" "$F" <<'PY'
P, V = get_class("Plant"), get_class("Vegetable")
v = make(V, "Tomato", 5.0, 10, "April", var="v", extra=0)
check(isinstance(v, P), "%s is not a Plant" % what(v))
ks = keys_with(v, "April")
check(ks, "%s: no attribute of v stores the harvest season \"April\" (%s)"
      % (what(v), short(desc(v), 50)))
if ks and not any(k.lstrip("_") == "harvest_season" for k in ks):
    warn("the harvest season is stored in v.%s; the subject calls it harvest_season" % ks[0])
nk = [k for k, x in attrs(v).items() if "nutri" in k.lower() and is_num(x)]
if not nk:
    warn("no number attribute named nutritional_value in v (%s)" % short(desc(v), 50))


def nutri(text):
    m = re.search(r"nutri\w*\D{0,10}?(-?\d+(?:\.\d+)?)", text, re.I)
    return float(m.group(1)) if m else None


if nk:
    check(attrs(v)[nk[0]] == 0, "%s: v.%s is %r; expected 0 at the start"
          % (what(v), nk[0], attrs(v)[nk[0]]))
base = show(make(P, "Tomato", 5.0, 10, var="b"))
out = show(v)
check(base.strip() and base in out, "%s prints %s; expected the standard Plant output %s, "
      "then the vegetable data" % (what(v), q(out), q(base)))
check(has_text(out, "April"), "%s prints %s; expected the harvest season \"April\""
      % (what(v), q(out)))
n0 = nutri(out)
check(n0 is not None, "%s prints %s; expected the nutritional value" % (what(v), q(out)))
if n0 not in (None, 0):
    fail("%s prints %s; expected a nutritional value of 0 at the start" % (what(v), q(out)))
meth(v, "grow")
meth(v, "age")
n1 = attrs(v)[nk[0]] if nk else nutri(show(v))
check(n1 is not None and n1 > 0, "%s: nutritional value %r; expected it to increase "
      "after grow() and age()" % (what(v), n1))
for i in range(19):
    meth(v, "grow", log=False)
    meth(v, "age", log=False)
HIST[id(v)][1].append("(19 more times: v.grow(); v.age())")
out = show(v)
n2 = nutri(out)
check(n2 is not None and n1 is not None and n2 > n1, "%s prints %s; expected a nutritional "
      "value greater than after the first day (%r)" % (what(v), q(out), n1))
check(has_num(out, 30), "%s prints %s; expected the age 30 (20 days later)" % (what(v), q(out)))
if out == "Tomato: 47.0cm, 30 days old\n Harvest season: April\n Nutritional value: 20\n":
    done("(same values as the subject example)")
PY

		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
Fl, T, V = (get_class(n, r.g) for n in ("Flower", "Tree", "Vegetable"))
for c, n in ((Fl, "Flower"), (T, "Tree"), (V, "Vegetable")):
    check(instances(r, c), "%s creates no %s: expected at least one instance of each "
          "plant type" % (r.prog, n))
check(calls_of(r, "bloom", Fl), "%s never calls bloom(): \"make the flower bloom\"" % r.prog)
check(calls_of(r, "grow", V) and calls_of(r, "age", V), "%s never calls grow() and age() on "
      "a vegetable (its nutritional value must increase)" % r.prog)
if not calls_of(r, "produce_shade", T):
    warn("%s never calls produce_shade() (the example does)" % r.prog)
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
example(r, "=== Garden Plant Types ===\n=== Flower\nRose: 15.0cm, 10 days old\n Color: red\n"
        " Rose has not bloomed yet\n[asking the rose to bloom]\nRose: 15.0cm, 10 days old\n"
        " Color: red\n Rose is blooming beautifully!\n\n=== Tree\nOak: 200.0cm, 365 days old\n"
        " Trunk diameter: 5.0cm\n[asking the oak to produce shade]\n"
        "Tree Oak now produces a shade of 200.0cm long and 5.0cm wide.\n\n=== Vegetable\n"
        "Tomato: 5.0cm, 10 days old\n Harvest season: April\n Nutritional value: 0\n"
        "[make tomato grow and age for 20 days]\nTomato: 47.0cm, 30 days old\n"
        " Harvest season: April\n Nutritional value: 20\n")
PY
	fi
fi

# ------------------------- ex6: ft_garden_analytics ------------------------- #
# Statistics helpers: counts(text) → (grow, age, show) read in the output of
# the statistics function, shade(text) → number of produce_shade() calls
IFS= read -r -d '' STATS_LIB <<'PY'
def count(text, word):
    """number next to word: "1 grow" (as in the example) or "grow: 1"
    (the side is chosen once, with the word grow)"""
    if re.search(r"\d[ \t]*grow", text, re.I):
        m = re.search(r"(\d+)[ \t]*%s" % word, text, re.I)
    else:
        m = re.search(r"\b%s\w*[ \t]*\W?[ \t]*(\d+)" % word, text, re.I)
    return int(m.group(1)) if m else None


def counts(text):
    c = tuple(count(text, w) for w in ("grow", "age", "show"))
    return None if None in c else c


def shade(text):
    return count(text, "shade")


def stats_function(M, P):
    """the function outside the classes that displays the statistics"""
    fs = [f for f in vars(M).values() if inspect.isfunction(f) and f.__module__ == M.__name__]
    tested = []
    for f in fs:
        try:
            ps = [p for p in inspect.signature(f).parameters.values()
                  if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
        except (TypeError, ValueError):
            continue
        if not ps:
            tested.append(f.__name__ + "() (no parameter)")
            continue
        tested.append(f.__name__ + "()")
        p = make(P, "Rose", 15.0, 10, var="x")
        ret, out, exc = capture(f, p)
        if exc is None and counts(out) is not None:
            return f
    stop("no function outside the classes prints the statistics of a plant (tested: %s); "
         "expected something like show_stats(plant) printing its grow / age / show counts"
         % (", ".join(tested) or "none"))
PY

if wanted 6; then
	section "ex6 - ft_garden_analytics"
	if ex_files ex6 ft_garden_analytics.py; then
		F="$WORK/ex6/ft_garden_analytics.py"
		common_checks ex6 ft_garden_analytics.py super,print,range,round,staticmethod,classmethod \
			"super(), print(), range(), round(), staticmethod(), classmethod()" 0 \
			Plant Flower Tree Seed

		snip_line "inheritance" "$F" <<'PY'
M = mod()
P = get_class("Plant")
for n, parent, m in (("Flower", P, "bloom"), ("Tree", P, "produce_shade"),
                     ("Seed", getattr(M, "Flower", None), "bloom")):
    c = getattr(M, n, None)
    if not isinstance(c, type):
        fail("no class %s in %s" % (n, BASE))
        continue
    if isinstance(parent, type):
        check(issubclass(c, parent) and c is not parent, "class %s does not inherit from %s; "
              "expected class %s(%s)" % (n, parent.__name__, n, parent.__name__))
    check(callable(getattr(c, m, None)), "class %s has no %s() method" % (n, m))
for m in ("show", "grow", "age"):
    check(callable(getattr(P, m, None)), "class Plant has no %s() method" % m)
if not isinstance(getattr(M, "Vegetable", None), type):
    warn("no class Vegetable (\"enhance your classes from the previous exercise\")")
PY

		snip_line "super()" "$F" "SUBS = ('Flower', 'Tree', 'Vegetable', 'Seed')" <<< "$SUPER_SNIP"

		# Static method: is the age older than a year?
		snip_line "static method" "$F" <<'PY'
P = get_class("Plant")
sms = [k for k, v in vars(P).items() if isinstance(v, staticmethod)]
if not sms:
    stop("class Plant has no static method (@staticmethod or staticmethod())")


def answer(f, n):
    ret, out, exc = capture(f, n)
    if exc is not None:
        return "raises " + summary(exc)
    if ret is None and out.strip() in ("True", "False"):
        return out.strip() == "True"
    return ret


found = None
for k in sms:
    if answer(getattr(P, k), 30) is False and answer(getattr(P, k), 400) is True:
        found = k
        break
if found is None:
    k = sms[0]
    stop("Plant.%s(30) returns %r, Plant.%s(400) returns %r; expected False and True "
         "(is this age older than a year?)" % (k, answer(getattr(P, k), 30), k,
                                               answer(getattr(P, k), 400)))
f = getattr(P, found)
for n, exp in ((0, False), (1, False), (364, False), (366, True), (730, True), (10000, True)):
    got = answer(f, n)
    check(got is exp, "Plant.%s(%d) returns %r; expected %r" % (found, n, got, exp))
if answer(f, 365) is not False:
    warn("Plant.%s(365) returns %r: 365 days is exactly one year, not more"
         % (found, answer(f, 365)))
ret, out, exc = capture(f, 30)
if exc is None and ret is None:
    warn("Plant.%s() prints the answer instead of returning it" % found)
p = make(P, "Rose", 15.0, 10)
got = answer(getattr(p, found), 400)
check(got is True, "%s; p.%s(400) returns %r; expected True (also callable on an instance)"
      % (what(p), found, got))
done("(Plant.%s())" % found)
PY

		# Class method: an "anonymous" plant
		snip_line "class method" "$F" <<'PY'
P = get_class("Plant")
cms = [k for k, v in vars(P).items() if isinstance(v, classmethod)]
if not cms:
    stop("class Plant has no class method (@classmethod or classmethod())")
found = a = None
args = ()
for extra in (None, 0):
    for k in cms:
        f = getattr(P, k)
        args = () if extra is None else fill(f, (), extra, "Plant.%s()" % k)
        ret, out, exc = capture(f, *args)
        if exc is None and isinstance(ret, P):
            found, a = k, ret
            text = "a = Plant.%s(%s)" % (k, ", ".join(lit(x) for x in args))
            break
    if found:
        break
if found is None:
    ret, out, exc = capture(getattr(P, cms[0]))
    stop("Plant.%s() %s; expected a class method that creates an \"anonymous\" plant"
         % (cms[0], "raises " + summary(exc) if exc else "returns %r" % (ret,)))
res("N")
adopt(a, "a", text)
b = capture(getattr(P, found), *args)[0]
check(b is not a, "%s returns the same object twice; expected a new plant each time" % text)
out = show(a)
check(out.strip() != "", "%s prints nothing" % what(a))
if out != "Unknown plant: 0.0cm, 0 days old\n":
    warn("%s prints %s; the example shows \"Unknown plant: 0.0cm, 0 days old\""
         % (what(a), q(out)))
for g in ("get_height", "get_age"):
    if callable(getattr(a, g, None)):
        v = get(a, g)
        check(is_num(v) and v >= 0, "%s; a.%s() returns %r; expected a valid value"
              % (what(a), g, v))
done("(Plant.%s())" % found)
PY

		# Nested statistics class: encapsulation and display function
		snip_line "nested class" "$F" <<'PY'
P = get_class("Plant")
nested = tuple(v for v in vars(P).values() if isinstance(v, type))
if not nested:
    stop("class Plant has no nested class (a class defined inside Plant) for the statistics")
p = make(P, "Rose", 15.0, 10)
st = [(k, v) for k, v in attrs(p).items() if isinstance(v, nested)]
if not st:
    stop("%s: no attribute of p is an instance of the nested class %s (%s)"
         % (what(p), "/".join(c.__name__ for c in nested), short(desc(p), 40)))
k, s = st[0]
res("N")
if not k.startswith("_"):
    warn("the statistics are stored in the public attribute p.%s" % k)
pub = [a for a in attrs(s) if not a.startswith("_")]
check(not pub, "the statistics object (p.%s) has public attributes: %s; encapsulation is "
      "required (protected names, e.g. _%s)" % (k, ", ".join(pub), pub[0] if pub else ""))
cnt = [a for a, v in attrs(s).items() if is_num(v)]
check(len(cnt) >= 3, "the statistics object (p.%s) holds %d number(s) (%s); expected the "
      "number of grow(), age() and show() calls" % (k, len(cnt), ", ".join(cnt)))
disp = None
names = sorted(n for n in dir(type(s)) if not n.startswith("__")
               and callable(getattr(type(s), n, None)) and getattr(type(s), n) is not None)
for n in names:
    for args in ((), (p,), ("Rose",)):
        ret, out, exc = capture(getattr(s, n), *args)
        if exc is None and re.search(r"\d", out):
            disp = n
            break
        if not (isinstance(exc, TypeError) and "argument" in str(exc)):
            break
    if disp:
        break
check(disp, "no method of the nested class %s prints the statistics (tested: %s); "
      "a display function is required" % (type(s).__name__, ", ".join(names) or "none"))
if disp:
    done("(%s, p.%s, display: %s())" % (type(s).__qualname__, k, disp))
PY

		# Statistics counted by the plants, shown by the function outside the classes
		snip_line "statistics" "$F" "$STATS_LIB" <<'PY'
M = mod()
P = get_class("Plant")
fn = stats_function(M, P)


NCHECK = [0]


def stats(o, exp, sh=None):
    NCHECK[0] += 1
    ret, out, exc = capture(fn, o)
    var = HIST[id(o)][0]
    if exc is not None:
        fail("%s; %s(%s) raises %s" % (what(o), fn.__name__, var, summary(exc)))
        return
    got = counts(out)
    m = "%s; %s(%s) prints %s; expected %d grow, %d age, %d show" \
        % (what(o), fn.__name__, var, q(out), exp[0], exp[1], exp[2])
    if got and exp[2] == 1 and got[2] == 2:
        m += " (show() counted twice: by the subclass and by Plant?)"
    check(got == exp, m)
    if sh is not None:
        check(shade(out) == sh, "%s; %s(%s) prints %s; expected %d shade"
              % (what(o), fn.__name__, var, q(out), sh))


p = make(P, "Rose", 15.0, 10)
stats(p, (0, 0, 0))
meth(p, "show")
stats(p, (0, 0, 1))
meth(p, "grow")
stats(p, (1, 0, 1))
meth(p, "age")
meth(p, "age")
stats(p, (1, 2, 1))
meth(p, "show")
stats(p, (1, 2, 2))
o = make(P, "Fern", 15.0, 120, var="o")
stats(o, (0, 0, 0))
f = make(get_class("Flower"), "Rose", 15.0, 10, "red", var="f")
meth(f, "show")
stats(f, (0, 0, 1))
meth(f, "grow")
meth(f, "bloom")
meth(f, "show")
stats(f, (1, 0, 2))
t = make(get_class("Tree"), "Oak", 200.0, 365, 5.0, var="t")
stats(t, (0, 0, 0), 0)
meth(t, "show")
meth(t, "produce_shade")
stats(t, (0, 0, 1), 1)
meth(t, "produce_shade")
meth(t, "grow")
stats(t, (1, 0, 1), 2)
u = make(get_class("Tree"), "Pine", 300.0, 900, 9.0, var="u")
stats(u, (0, 0, 0), 0)
s = make(get_class("Seed"), "Sunflower", 80.0, 45, "yellow", var="s", extra=42)
meth(s, "show")
stats(s, (0, 0, 1))
meth(s, "grow")
meth(s, "age")
meth(s, "bloom")
meth(s, "show")
stats(s, (1, 1, 2))
if isinstance(getattr(M, "Vegetable", None), type):
    v = make(M.Vegetable, "Tomato", 5.0, 10, "April", var="v", extra=0)
    meth(v, "grow")
    meth(v, "age")
    meth(v, "show")
    stats(v, (1, 1, 1))
done("(function %s(), %d checks of the counters)" % (fn.__name__, NCHECK[0]))
PY

		snip_line "Seed" "$F" <<'PY'
P, Fl, S = get_class("Plant"), get_class("Flower"), get_class("Seed")


def seeds(text):
    m = re.search(r"seeds?\b\D{0,5}?(\d+)", text, re.I) or re.search(r"(\d+)\s*seeds?", text, re.I)
    return int(m.group(1)) if m else None


s = make(S, "Sunflower", 80.0, 45, "yellow", var="s", extra=42)
check(isinstance(s, Fl), "%s is not a Flower" % what(s))
pl = show(make(P, "Sunflower", 80.0, 45, var="b"))
fl = show(make(Fl, "Sunflower", 80.0, 45, "yellow", var="f"))
out1 = show(s)
check(pl.strip() and pl in out1, "%s prints %s; expected the standard Plant output %s first"
      % (what(s), q(out1), q(pl)))
check(has_text(out1, "yellow"), "%s prints %s; expected the color \"yellow\"" % (what(s), q(out1)))
if fl not in out1:
    warn("%s prints %s; expected the Flower output %s, then the seeds"
         % (what(s), q(out1), q(fl)))
n1 = seeds(out1)
check(n1 is not None, "%s prints %s; expected the number of seeds" % (what(s), q(out1)))
if n1 not in (None, 0):
    warn("%s prints %s: %d seeds before bloom(); the example shows 0" % (what(s), q(out1), n1))
meth(s, "grow")
meth(s, "age")
meth(s, "bloom")
out2 = show(s)
n2 = seeds(out2)
check(n2 is not None and n2 > 0, "%s prints %s; expected a number of seeds greater than 0 "
      "once the flower has bloomed" % (what(s), q(out2)))
check(out2 != out1, "%s prints the same text as before bloom()" % what(s))
e1 = fl + " Seeds: 0\n"
if out1 != e1:
    warn(differs("s.show()", out1, e1))
PY

		snip_line "program" "$F" <<'PY'
r = run_main()
program(r)
for n in ("Flower", "Tree", "Seed"):
    c = r.g.get(n)
    if isinstance(c, type) and not instances(r, c):
        warn("%s creates no %s (the example shows one)" % (r.prog, n))
PY

		snip_line "output" "$F" <<'PY'
r = run_main()
example(r, "=== Garden statistics ===\n=== Check year-old\n"
        "Is 30 days more than a year? -> False\nIs 400 days more than a year? -> True\n\n"
        "=== Flower\nRose: 15.0cm, 10 days old\n Color: red\n Rose has not bloomed yet\n"
        "[statistics for Rose]\nStats: 0 grow, 0 age, 1 show\n[asking the rose to grow and bloom]\n"
        "Rose: 23.0cm, 10 days old\n Color: red\n Rose is blooming beautifully!\n"
        "[statistics for Rose]\nStats: 1 grow, 0 age, 2 show\n\n=== Tree\n"
        "Oak: 200.0cm, 365 days old\n Trunk diameter: 5.0cm\n[statistics for Oak]\n"
        "Stats: 0 grow, 0 age, 1 show\n 0 shade\n[asking the oak to produce shade]\n"
        "Tree Oak now produces a shade of 200.0cm long and 5.0cm wide.\n[statistics for Oak]\n"
        "Stats: 0 grow, 0 age, 1 show\n 1 shade\n\n=== Seed\nSunflower: 80.0cm, 45 days old\n"
        " Color: yellow\n Sunflower has not bloomed yet\n Seeds: 0\n"
        "[make sunflower grow, age and bloom]\nSunflower: 110.0cm, 65 days old\n Color: yellow\n"
        " Sunflower is blooming beautifully!\n Seeds: 42\n[statistics for Sunflower]\n"
        "Stats: 1 grow, 1 age, 2 show\n\n=== Anonymous\nUnknown plant: 0.0cm, 0 days old\n"
        "[statistics for Unknown plant]\nStats: 0 grow, 0 age, 1 show\n")
PY
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/ft_garden_intro.py]=1 [ex1/ft_garden_data.py]=1 [ex2/ft_plant_growth.py]=1
		[ex3/ft_plant_factory.py]=1 [ex4/ft_garden_security.py]=1 [ex5/ft_plant_types.py]=1
		[ex6/ft_garden_analytics.py]=1
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
