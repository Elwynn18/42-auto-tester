#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_06bis.sh - single-file tester for Python Module 6bis            #
#  (Code Nexus - Abstract Architecture, from Data Streams to Battle            #
#  Strategies)                                                                 #
#                                                                              #
#  Usage (from the root of your repository, with data_processor.py ...         #
#  ex3/ ex4/ tournament.py):                                                   #
#      bash ../test_python_06bis.sh            -> test everything              #
#      bash ../test_python_06bis.sh 0 ex4      -> only these exercises         #
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
banner "Python Module 6bis tester (Code Nexus - Abstract Architecture)" "$DIR"
found=0
for f in data_processor.py data_stream.py data_pipeline.py ex3 ex4 battle.py capacitor.py tournament.py; do
	[ -e "$DIR/$f" ] && found=1
done
if [ $found -eq 0 ]; then
	echo "Error: no data_processor.py, ex3/, ex4/ ... here. Run this script from your Python Module 6bis" >&2
	echo "folder (the root of your repository)." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_06bis.XXXXXX)
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
# diff <expected> <got>          : first difference between two outputs
# ast <file> <calls> <imports> <only-functions 0|1>
#                                : forbidden calls / imports, code outside functions
#                                  (calls: "!name" = forbidden; imports: "LOCAL" =
#                                  the student's own modules and packages)
# hints <file>                   : parameters and returns without a type hint
# script <file> [args]           : runs the file like "python3 file args" from its folder
#                                  (the exception, if any, goes to $PT_EXC)
# exec <folder> <tests> <function> [params]
#                                : runs a test function of the snippets file (tests.py)
#                                  with the folder on sys.path; results go to $PT_RES
cat > "$TMP/pt.py" <<'EOF'
import abc
import ast
import builtins
import contextlib
import importlib
import importlib.util
import inspect
import io
import json
import os
import pkgutil
import re
import runpy
import signal
import sys
import textwrap
import traceback

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))
sys.dont_write_bytecode = True
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


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
        if os.path.isabs(fr.filename) \
                and os.path.realpath(fr.filename).startswith(ROOT + os.sep):
            loc = "%s:%s" % (os.path.relpath(os.path.realpath(fr.filename), ROOT), fr.lineno)
            break
    m = short(str(e), 90)
    s = type(e).__name__ + (": " + m if m else "")
    return s + (" (" + loc + ")" if loc else "")


def report(text):
    path = os.environ.get("PT_EXC")
    if path:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text + "\n")


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


def is_local_module(path, name):
    # a module of the student: a .py file or a folder next to the file,
    # one level up, or at the root of the module folder
    top = name.split(".")[0]
    d = os.path.dirname(os.path.abspath(path))
    for base in (d, os.path.dirname(d), ROOT):
        if os.path.isfile(os.path.join(base, top + ".py")) \
                or os.path.isdir(os.path.join(base, top)):
            return True
    return False


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
        if "!" + name in allowed:
            print("CALL %s %s" % (name, line))
        elif (name in bnames and name not in mine and "*" not in allowed
                and name not in allowed and not is_exception(name)):
            print("CALL %s %s" % (name, line))

    def module_ok(name):
        return ("*" in mods or name in mods or name.split(".")[0] in mods
                or ("LOCAL" in mods and is_local_module(path, name)))

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            check(n.func.id, n.lineno)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            for d in n.decorator_list:
                if isinstance(d, ast.Name):
                    check(d.id, d.lineno)
        if isinstance(n, ast.Import):
            for a in n.names:
                if not module_ok(a.name):
                    print("IMPORT %s %s" % (a.name, n.lineno))
        if isinstance(n, ast.ImportFrom) and n.level == 0:
            if not module_ok(n.module):
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


def fmt_sig(s):
    a = s.args
    parts = []
    for x in a.posonlyargs + a.args:
        parts.append(x.arg + (": " + ast.unparse(x.annotation) if x.annotation else ""))
    if a.vararg:
        parts.append("*" + a.vararg.arg)
    for x in a.kwonlyargs:
        parts.append(x.arg + (": " + ast.unparse(x.annotation) if x.annotation else ""))
    if a.kwarg:
        parts.append("**" + a.kwarg.arg)
    ret = " -> " + ast.unparse(s.returns) if s.returns else ""
    return "(%s)%s" % (", ".join(parts), ret)


def cmd_hints(path):
    # every parameter (except self / cls) and every return has a type hint
    # (__init__ may omit "-> None" when one of its parameters is annotated)
    with open(path, encoding="utf-8", errors="replace") as f:
        try:
            tree = ast.parse(f.read(), path)
        except SyntaxError as e:
            print("SYNTAX %s %s" % (e.lineno, e.msg))
            return 0

    def visit(node, in_class):
        for ch in ast.iter_child_nodes(node):
            if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef)):
                a = ch.args
                params = a.posonlyargs + a.args
                static = any(isinstance(d, ast.Name) and d.id == "staticmethod"
                             for d in ch.decorator_list)
                if in_class and not static and params:
                    params = params[1:]
                miss = [x.arg for x in params + a.kwonlyargs if x.annotation is None]
                if a.vararg and a.vararg.annotation is None:
                    miss.append("*" + a.vararg.arg)
                if a.kwarg and a.kwarg.annotation is None:
                    miss.append("**" + a.kwarg.arg)
                for m in miss:
                    print("PARAM %d %s %s" % (ch.lineno, ch.name, m))
                annotated = any(x.annotation for x in params + a.kwonlyargs)
                if ch.returns is None and not (ch.name == "__init__" and annotated):
                    print("RETURN %d %s" % (ch.lineno, ch.name))
                visit(ch, False)
            elif isinstance(ch, ast.ClassDef):
                visit(ch, True)
            elif isinstance(ch, ast.stmt):
                visit(ch, in_class)
    visit(tree, False)
    return 0


def cmd_script(path, *args):
    # runs the file like "python3 file args" from its folder
    path = os.path.abspath(path)
    d = os.path.dirname(path)
    os.chdir(d)
    sys.path.insert(0, d)
    sys.argv = [os.path.basename(path)] + list(args)
    try:
        runpy.run_path(path, run_name="__main__")
    except SystemExit as e:
        sys.stdout.flush()
        if e.code is None or e.code == 0:
            return 0
        report("exits with status %s" % e.code)
        return 2
    except BaseException as e:
        sys.stdout.flush()
        report(summary(e))
        return 3
    return 0


# ------------------------- Test snippets (exec mode) ------------------------ #
# A snippet is a Python file with test functions. It runs in this namespace:
# the helpers below write the results to $PT_RES, one line per result:
#   T (one test)   F <failure>   W <warning>   I <info>   X (stop the next tests)
class Abort(Exception):
    """Stops the current test (the failure is already reported)."""


def res(kind, text=""):
    text = str(text).replace("\n", "\\n").replace("\t", " ")
    if len(text) > 330:
        text = text[:330] + "…"
    with open(os.environ["PT_RES"], "a", encoding="utf-8") as f:
        f.write("%s\t%s\n" % (kind, text))


def fail(m):
    res("F", m)


def warn(m):
    res("W", m)


def info(m):
    res("I", m)


def check(cond, m):
    res("T")
    if not cond:
        fail(m)
    return bool(cond)


CURRENT = [""]


def on_timeout(signum, frame):
    # "timeout" stops the test: say which call was running
    res("C", CURRENT[0])
    os._exit(124)


def run(f, *a, **k):
    # calls f, captures what it prints → (returned value, output, exception)
    name = getattr(f, "__qualname__", "") or type(f).__name__
    if name == "import_module":
        CURRENT[0] = "import %s" % a[0]
    else:
        CURRENT[0] = "%s(%s)" % (name.replace(".<locals>", ""),
                                 ", ".join(r(x, 30) for x in a))
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            ret = f(*a, **k)
    except (Exception, SystemExit) as e:
        return None, buf.getvalue(), e
    return ret, buf.getvalue(), None


def r(x, n=60):
    try:
        s = repr(x)
    except Exception:
        s = "<%s object>" % type(x).__name__
    return short(s, n)


def q(s, n=70):
    return '"%s"' % short(str(s), n)


def es(e):
    return summary(e) if e is not None else ""


def imp(name):
    m, out, e = run(importlib.import_module, name)
    if e is not None:
        fail("import %s raises %s" % (name, summary(e)))
        res("X")
        raise Abort()
    return m, out


def is_local(m):
    f = getattr(m, "__file__", None)
    return bool(f) and os.path.realpath(f).startswith(ROOT + os.sep)


def get(mod, name):
    # a name of the module, or of a local module it imports
    v = getattr(mod, name, None)
    if v is not None:
        return v
    for x in list(vars(mod).values()):
        if inspect.ismodule(x) and is_local(x):
            v = getattr(x, name, None)
            if v is not None:
                return v
    return None


def submodules(pkg):
    mods = [pkg]
    path = getattr(pkg, "__path__", None)
    if path:
        for i in pkgutil.walk_packages(path, pkg.__name__ + "."):
            m, out, e = run(importlib.import_module, i.name)
            if e is None:
                mods.append(m)
    return mods


def find_class(pkg, name):
    for m in submodules(pkg):
        c = getattr(m, name, None)
        if isinstance(c, type):
            return c
    return None


def abstracts(c):
    return set(getattr(c, "__abstractmethods__", ()) or ())


def defined_in(cls, meth):
    for c in cls.__mro__:
        if meth in vars(c):
            return c
    return None


def root_abstract(cls, meth, prefer=""):
    # the most basic class of the MRO where meth is abstract
    found = None
    for c in cls.__mro__:
        if prefer and c.__name__ == prefer and meth in abstracts(c):
            return c
        if meth in abstracts(c):
            found = c
    return found


def cannot_inst(c, *argsets):
    # True when instantiating c raises "Can't instantiate abstract class"
    for a in argsets or ((),):
        _, _, e = run(c, *a)
        if isinstance(e, TypeError) and "abstract" in str(e):
            return True
    return False


def asig(f):
    # signature of a function, as written in its source
    try:
        src = textwrap.dedent(inspect.getsource(f))
        node = ast.parse(src).body[0]
    except Exception:
        return None
    if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        return None
    return fmt_sig(node)


def norm_sig(s):
    s = s.replace("typing.", "").replace("'", "").replace('"', "")
    for a, b in (("List[", "list["), ("Tuple[", "tuple["), ("Dict[", "dict[")):
        s = s.replace(a, b)
    return s


def nb_required(f):
    try:
        ps = inspect.signature(f).parameters.values()
    except (TypeError, ValueError):
        return 1
    return sum(1 for p in ps if p.default is p.empty
               and p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD))


def cmd_exec(root, snippet, test, *params):
    root = os.path.abspath(root)
    os.chdir(root)
    sys.path.insert(0, root)
    signal.signal(signal.SIGTERM, on_timeout)
    ns = dict(globals())
    ns["__name__"] = "pt_snippet"
    with open(snippet, encoding="utf-8") as f:
        exec(compile(f.read(), snippet, "exec"), ns)
    try:
        ns[test](*params)
    except Abort:
        pass
    except BaseException as e:
        report(summary(e))
        return 3
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"diff": cmd_diff, "ast": cmd_ast, "hints": cmd_hints,
              "script": cmd_script, "exec": cmd_exec}[cmd](*sys.argv[2:]))
EOF

# ------------------------------ Test snippets ------------------------------- #
# Test functions run by "pt.py exec": they import the student's code, call it in
# the same process and report each result (T test, F failure, W warning, I info).
cat > "$TMP/tests.py" <<'EOF'
# --------------- Data processors / data streams / data pipeline ------------- #
import copy

PROCS = ["NumericProcessor", "TextProcessor", "LogProcessor"]
LABEL = {"NumericProcessor": "Numeric Processor", "TextProcessor": "Text Processor",
         "LogProcessor": "Log Processor"}
LOG1 = {"log_level": "NOTICE", "log_message": "Connection to server"}
LOG2 = {"log_level": "ERROR", "log_message": "Unauthorized access!!"}
LOG3 = {"log_level": "WARNING", "log_message": "Telnet access! Use ssh instead"}
LOG4 = {"log_level": "INFO", "log_message": "User wil is connected"}
LOG5 = {"log_level": "ERROR", "log_message": "500 server crash"}
LOG6 = {"log_level": "NOTICE", "log_message": "Certificate expires in 10 days"}
BATCH1 = ["Hello world", [3.14, -1, 2.71], [LOG3, LOG4], 42, ["Hi", "five"]]
BATCH2 = [21, ["I love AI", "LLMs are wonderful", "Stay healthy"], [LOG5, LOG6],
          [32, 42, 64, 84, 128, 168], "World hello"]
SIGS = {
    "DataProcessor.validate": (2, "(self, data: Any) -> bool"),
    "DataProcessor.ingest": (2, "(self, data: Any) -> None"),
    "DataProcessor.output": (1, "(self) -> tuple[int, str]"),
    "DataStream.register_processor": (2, "(self, proc: DataProcessor) -> None"),
    "DataStream.process_stream": (2, "(self, stream: list[Any]) -> None"),
    "DataStream.print_processors_stats": (1, "(self) -> None"),
    "DataStream.output_pipeline": (3, "(self, nb: int, plugin: ExportPlugin) -> None"),
    "ExportPlugin.process_output": (2, "(self, data: list[tuple[int, str]]) -> None"),
}
NEED = {"": [], "stream": ["DataStream"], "pipeline": ["DataStream", "ExportPlugin"]}
LOG_FMT = []


def logstr(d):
    return "%s: %s" % (d["log_level"], d["log_message"])


def load(mod, kind=""):
    m, out = imp(mod)
    C = {}
    miss = []
    for n in ["DataProcessor"] + PROCS + NEED[kind]:
        c = get(m, n)
        if isinstance(c, type):
            C[n] = c
        else:
            miss.append(n)
    if miss:
        fail("%s.py: no class %s (the names must match the subject)" % (mod, ", ".join(miss)))
        res("X")
        raise Abort()
    return m, out, C


def new(cls, label=None):
    o, out, e = run(cls)
    if e is not None:
        fail("%s() raises %s" % (label or cls.__name__, summary(e)))
        raise Abort()
    return o


def call(label, f, *a):
    v, out, e = run(f, *a)
    if e is not None:
        fail("%s raises %s" % (label, summary(e)))
        raise Abort()
    return v, out


# ------------------------------ classes / signatures ------------------------ #
def dp_classes(mod, kind="", warn_import="0"):
    m, out, C = load(mod, kind)
    if out and warn_import == "1":
        warn("import %s prints %s: put your tests under if __name__ == \"__main__\":"
             % (mod, q(out, 40)))
    DP = C["DataProcessor"]
    if check(isinstance(DP, abc.ABCMeta),
             "DataProcessor is not an abstract class (class DataProcessor(ABC): ...)"):
        if not issubclass(DP, abc.ABC):
            warn("DataProcessor uses ABCMeta but does not inherit from ABC as the subject says")
    ab = abstracts(DP)
    check({"validate", "ingest"} <= ab,
          "DataProcessor: validate() and ingest() must be abstract (@abstractmethod); "
          "abstract methods found: %s" % (", ".join(sorted(ab)) or "none"))
    check(callable(getattr(DP, "output", None)) and "output" not in ab,
          "DataProcessor: output() must be a standard (not abstract) method of DataProcessor")
    check(cannot_inst(DP), "DataProcessor() can be instantiated: an abstract class must "
          "raise TypeError (Can't instantiate abstract class)")
    for n in PROCS:
        c = C[n]
        if not check(issubclass(c, DP), "%s does not inherit from DataProcessor" % n):
            continue
        check(not abstracts(c), "%s is still abstract (not implemented: %s)"
              % (n, ", ".join(sorted(abstracts(c)))))
        for meth in ("validate", "ingest"):
            dc = defined_in(c, meth)
            check(dc is not None and dc is not DP and issubclass(dc, DP),
                  "%s does not override %s()" % (n, meth))
        o, _, e = run(c)
        check(e is None, "%s() raises %s (a processor is created without argument)"
              % (n, es(e)))
    if kind:
        DS = C["DataStream"]
        meths = ["register_processor", "process_stream", "print_processors_stats"]
        if kind == "pipeline":
            meths.append("output_pipeline")
        for mm in meths:
            check(callable(getattr(DS, mm, None)), "DataStream has no %s() method" % mm)
        o, _, e = run(DS)
        check(e is None, "DataStream() raises %s" % es(e))
    if kind == "pipeline":
        EP = C["ExportPlugin"]
        check(getattr(EP, "_is_protocol", False),
              "ExportPlugin does not inherit from typing.Protocol (class ExportPlugin(Protocol))")
        check(callable(getattr(EP, "process_output", None)),
              "ExportPlugin has no process_output() method")


def sig_cmp(label, f, nb, want):
    res("T")
    got = asig(f)
    if got is None:
        return
    try:
        n = len(inspect.signature(f).parameters)
    except (TypeError, ValueError):
        n = nb
    if n != nb:
        fail("%s%s: %d parameter(s); subject: %s%s" % (label, got, n, label, want))
    elif norm_sig(got) != want:
        warn("def %s%s; subject: %s" % (label.split(".")[-1], got, want))


def dp_sigs(mod, kind=""):
    m, out, C = load(mod, kind)
    for key, (nb, want) in SIGS.items():
        cn, meth = key.split(".")
        if cn in C and callable(getattr(C[cn], meth, None)):
            sig_cmp(key, getattr(C[cn], meth), nb, want)
    types = {"NumericProcessor": ("int", "float"), "TextProcessor": ("str",),
             "LogProcessor": ("dict",)}
    for n in PROCS:
        sig_cmp(n + ".validate", C[n].validate, 2, SIGS["DataProcessor.validate"][1])
        res("T")
        got = asig(C[n].ingest)
        if got is None:
            continue
        g = norm_sig(got)
        mt = re.match(r"\(\w+, \w+: (.*)\)( -> (.*))?$", g)
        ann = mt.group(1) if mt else ""
        if not ann or ann == "Any" or any(t not in ann for t in types[n]):
            warn("%s.ingest%s: the type of data should reflect the accepted types (%s)"
                 % (n, got, ", ".join(types[n]) + ", list"))
        elif mt.group(3) != "None":
            warn("%s.ingest%s: subject: ingest(...) -> None" % (n, got))


# -------------------------------- processors -------------------------------- #
VALID = {
    "NumericProcessor": [
        (42, True), (0, True), (-7, True), (3.14, True), (-0.5, True), (1e100, True),
        ([1, 2, 3, 4, 5], True), ([3.14, -1, 2.71], True), ([7], True),
        ("Hello", False), ("foo", False), (None, False), (LOG1, False),
        (["Hi", "five"], False), ([1, "a"], False), ([[1, 2]], False), ([LOG1], False)],
    "TextProcessor": [
        ("Hello", True), ("Hello world", True), ("42", True), ("héllo ✓ 日本", True),
        (["Hello", "Nexus", "World"], True), (["Hi"], True),
        (42, False), (3.14, False), (None, False), ([1, 2], False), (["a", 1], False),
        (LOG1, False), ([LOG1], False), ([["a"]], False)],
    "LogProcessor": [
        (LOG1, True), ([LOG1, LOG2], True), ([LOG3], True),
        ("Hello", False), (42, False), (None, False), (["Hello"], False), ([1, 2], False),
        ([LOG1, "oops"], False), ([LOG1, 42], False)],
}
ONE = {"NumericProcessor": (7, "7"), "TextProcessor": ("ok", "ok"),
       "LogProcessor": (LOG4, logstr(LOG4))}
BAD = {"NumericProcessor": ["foo", "Hello", None, ["a", "b"], LOG1],
       "TextProcessor": [42, 3.14, None, [1, 2], LOG1],
       "LogProcessor": ["Hello", 42, None, ["Hello"], [1, 2]]}
BAD_MIXED = {"NumericProcessor": [1, "a"], "TextProcessor": ["a", 1],
             "LogProcessor": [LOG1, "oops"]}


def dp_validate(mod, kind=""):
    m, out, C = load(mod, kind)
    for n in PROCS:
        p = new(C[n])
        for data, exp in VALID[n]:
            label = "%s().validate(%s)" % (n, r(data, 50))
            v, o, e = run(p.validate, copy.deepcopy(data))
            res("T")
            if e is not None:
                fail("%s raises %s" % (label, summary(e)))
            elif not isinstance(v, bool):
                fail("%s returns %s; expected a bool (%s)" % (label, r(v), exp))
            elif v != exp:
                fail("%s returns %s; expected %s" % (label, v, exp))


def same_item(g, x, n):
    # (rank, text) returned by output(); the log text may be formatted freely
    if g == x:
        return True
    if n != "LogProcessor" or not (isinstance(g, tuple) and len(g) == 2):
        return False
    lvl, msg_ = x[1].split(": ", 1)
    if g[0] == x[0] and isinstance(g[1], str) and lvl in g[1] and msg_ in g[1]:
        if not LOG_FMT:
            LOG_FMT.append(1)
            warn("log entries are stored as %s; the subject example uses %s"
                 % (q(g[1]), q(x[1])))
        return True
    return False


def expect_outs(label, p, exp, n):
    res("T")
    got = []
    for i in range(len(exp)):
        v, o, e = run(p.output)
        if e is not None:
            fail("%s: output() call %d raises %s; expected %s"
                 % (label, i + 1, summary(e), r(exp[i])))
            return False
        if not (isinstance(v, tuple) and len(v) == 2):
            fail("%s: output() returns %s; expected a tuple (rank, str) like %s"
                 % (label, r(v), r(exp[i])))
            return False
        got.append(v)
    if all(same_item(g, x, n) for g, x in zip(got, exp)):
        return True
    fail("%s: output() x%d returns %s; expected %s" % (label, len(exp), r(got, 110),
                                                       r(exp, 110)))
    return False


def ingest(p, n, data):
    call("%s().ingest(%s)" % (n, r(data, 50)), p.ingest, copy.deepcopy(data))


def dp_invalid(mod, kind=""):
    m, out, C = load(mod, kind)
    for n in PROCS:
        for data in BAD[n] + [BAD_MIXED[n]]:
            p = new(C[n])
            label = "%s().ingest(%s)" % (n, r(data, 50))
            v, o, e = run(p.ingest, copy.deepcopy(data))
            if not check(e is not None, "%s without validation does not raise an exception "
                         "(invalid data)" % label):
                continue
            # the processor must stay usable, without the invalid data
            res("T")
            v, o, e = run(p.ingest, ONE[n][0])
            if e is not None:
                fail("after a failed %s, ingest(%s) raises %s" % (label, r(ONE[n][0]), es(e)))
                continue
            v, o, e = run(p.output)
            ref = run(lambda: (lambda x: (x.ingest(ONE[n][0]), x.output())[1])(C[n]()))[0]
            ok = isinstance(v, tuple) and len(v) == 2 and isinstance(ref, tuple) \
                and v[1] == ref[1]
            if e is not None or not ok:
                m_ = ("after a failed %s then ingest(%s), output() %s; expected the same as "
                      "a new processor: %s (invalid data must not be stored)"
                      % (label, r(ONE[n][0], 30), "raises " + es(e) if e else
                         "returns " + r(v), r(ref, 40)))
                if data is BAD_MIXED[n]:
                    warn(m_)
                else:
                    fail(m_)
            elif v[0] != 0:
                warn("after a failed %s, the next item gets the rank %s (expected 0: "
                     "the invalid data should not count)" % (label, r(v[0])))


def dp_output(mod, kind=""):
    m, out, C = load(mod, kind)
    N, Tx, L = C["NumericProcessor"], C["TextProcessor"], C["LogProcessor"]
    n = "NumericProcessor"
    p = new(N)
    ingest(p, n, [1, 2, 3, 4, 5])
    if expect_outs("ingest([1, 2, 3, 4, 5])", p, [(0, "1"), (1, "2"), (2, "3")], n):
        expect_outs("ingest([1, 2, 3, 4, 5]) then 3 output()", p, [(3, "4"), (4, "5")], n)
    p = new(N)
    for d in (42, 3.14, -1, [3.14, -1, 2.71], 0):
        ingest(p, n, d)
    expect_outs("ingest(42), ingest(3.14), ingest(-1), ingest([3.14, -1, 2.71]), ingest(0)",
                p, [(0, "42"), (1, "3.14"), (2, "-1"), (3, "3.14"), (4, "-1"),
                    (5, "2.71"), (6, "0")], n)
    p = new(N)
    ingest(p, n, [1, 2])
    lab = "ingest([1, 2]), output(), ingest(3), output() x2, ingest([4, 5]), output()"
    ok = expect_outs(lab, p, [(0, "1")], n)
    ingest(p, n, 3)
    ok = ok and expect_outs(lab, p, [(1, "2"), (2, "3")], n)
    ingest(p, n, [4, 5])
    ok = ok and expect_outs(lab, p, [(3, "4")], n)
    p = new(N)
    ingest(p, n, list(range(1000)))
    res("T")
    got = [run(p.output)[0] for _ in range(1000)]
    if got != [(i, str(i)) for i in range(1000)]:
        fail("ingest(list(range(1000))) then output() x1000: the items or ranks differ "
             "(first difference: %s)" % r(next((g for i, g in enumerate(got)
                                                 if g != (i, str(i))), None)))
    n = "TextProcessor"
    p = new(Tx)
    ingest(p, n, ["Hello", "Nexus", "World"])
    if expect_outs("ingest(['Hello', 'Nexus', 'World'])", p, [(0, "Hello")], n):
        ingest(p, n, "héllo ✓ 日本")
        expect_outs("ingest(['Hello', 'Nexus', 'World']), output(), ingest('héllo ✓ 日本')",
                    p, [(1, "Nexus"), (2, "World"), (3, "héllo ✓ 日本")], n)
    n = "LogProcessor"
    p = new(L)
    ingest(p, n, [LOG1, LOG2])
    ingest(p, n, LOG3)
    expect_outs("ingest([%s, %s]), ingest(%s)" % (r(LOG1, 20), r(LOG2, 20), r(LOG3, 20)), p,
                [(0, logstr(LOG1)), (1, logstr(LOG2)), (2, logstr(LOG3))], n)
    # independent instances
    a, b, t = new(N), new(N), new(Tx)
    ingest(a, "NumericProcessor", [1, 2])
    ingest(b, "NumericProcessor", 9)
    ingest(t, "TextProcessor", "a")
    res("T")
    vb, vt, va = run(b.output)[0], run(t.output)[0], run(a.output)[0]
    if (vb, vt, va) != ((0, "9"), (0, "a"), (0, "1")):
        fail("two NumericProcessor and a TextProcessor share their data (class attribute?): "
             "a.ingest([1, 2]), b.ingest(9), t.ingest('a'): b.output() = %s, "
             "t.output() = %s, a.output() = %s; expected (0, '9'), (0, 'a'), (0, '1')"
             % (r(vb), r(vt), r(va)))


def dp_edge(mod, kind=""):
    m, out, C = load(mod, kind)
    cases = [("TextProcessor", "", True, "an empty str is a str"),
             ("NumericProcessor", "42", False, "a str is not an int / float"),
             ("NumericProcessor", True, None, ""),
             ("LogProcessor", {"log_level": "INFO", "log_message": 42}, False,
              "not a dict of string key-value pairs"),
             ("LogProcessor", {1: "a"}, False, "not a dict of string key-value pairs")]
    for n, data, exp, why in cases:
        p = new(C[n])
        v, o, e = run(p.validate, data)
        res("T")
        if e is not None:
            fail("%s().validate(%s) raises %s (validate() must accept any data)"
                 % (n, r(data), summary(e)))
        elif exp is not None and v is not exp:
            warn("%s().validate(%s) returns %s; expected %s (%s)" % (n, r(data), r(v), exp, why))
    for n in PROCS:
        p = new(C[n])
        v, o, e = run(p.validate, [])
        check(e is None, "%s().validate([]) raises %s" % (n, es(e)))
        v, o, e = run(p.validate, object())
        check(e is None, "%s().validate(object()) raises %s" % (n, es(e)))


def dp_all(mod, kind=""):
    for f in (dp_validate, dp_invalid, dp_output):
        try:
            f(mod, kind)
        except Abort:
            pass


# ------------------------------- data stream -------------------------------- #
def exp_stats(rows):
    s = "== DataStream statistics ==\n"
    if not rows:
        return s + "No processor found, no data\n"
    for c, t, rem in rows:
        s += "%s: total %d items processed, remaining %d on processor\n" % (LABEL[c], t, rem)
    return s


COSM = []


def check_stats(label, ds, rows):
    res("T")
    v, out, e = run(ds.print_processors_stats)
    if e is not None:
        fail("%s: print_processors_stats() raises %s" % (label, summary(e)))
        return False
    exp = exp_stats(rows)
    if out == exp:
        return True
    lines = out.splitlines()
    if not out.strip():
        fail("%s: print_processors_stats() prints nothing; expected %s" % (label, q(exp, 90)))
        return False
    bad = False
    for c, t, rem in rows:
        key = c.replace("Processor", "").lower()
        found = False
        for li in lines:
            if key not in li.lower():
                continue
            nums = [int(x) for x in re.findall(r"-?\d+", li)]
            if t in nums and rem in nums[nums.index(t) + 1:]:
                found = True
        if not found:
            bad = True
            fail("%s: print_processors_stats() prints %s; expected a line like %s"
                 % (label, q(out, 110), q("%s: total %d items processed, remaining %d on "
                                          "processor" % (LABEL[c], t, rem))))
    if not rows and re.search(r"numeric|text|log", out.lower()):
        bad = True
        fail("%s: print_processors_stats() prints %s; expected no processor (%s)"
             % (label, q(out, 90), q(exp)))
    if not bad and not COSM:
        COSM.append(1)
        d = [(a, b) for a, b in zip(lines, exp.splitlines()) if a != b]
        a, b = d[0] if d else (out, exp)
        warn("print_processors_stats() prints %s; subject example: %s (cosmetic)"
             % (q(a, 60), q(b, 60)))
    return not bad


def stream_setup(mod, kind):
    m, out, C = load(mod, kind)
    return C, new(C["DataStream"])


def ds_stats(mod, kind="stream"):
    C, ds = stream_setup(mod, kind)
    check_stats("new DataStream", ds, [])
    ds2 = new(C["DataStream"])
    call("register_processor(NumericProcessor())", ds2.register_processor,
         new(C["NumericProcessor"]))
    check_stats("DataStream with a NumericProcessor and no data", ds2,
                [("NumericProcessor", 0, 0)])
    check_stats("a second DataStream (the first one has a processor)", ds, [])
    for n in ("TextProcessor", "LogProcessor"):
        call("register_processor(%s())" % n, ds2.register_processor, new(C[n]))
    check_stats("DataStream with the 3 processors and no data", ds2,
                [(n, 0, 0) for n in PROCS])


def ds_scenario(mod, kind="stream"):
    C, ds = stream_setup(mod, kind)
    num = new(C["NumericProcessor"])
    call("register_processor(NumericProcessor())", ds.register_processor, num)
    lab = "subject scenario, step 1 (only a NumericProcessor)"
    v, out = call("%s: process_stream(%s)" % (lab, r(BATCH1, 40)), ds.process_stream,
                  copy.deepcopy(BATCH1))
    exp = "".join("DataStream error - Can't process element in stream: %s\n" % x
                  for x in (BATCH1[0], BATCH1[2], BATCH1[4]))
    res("T")
    if not out.strip():
        fail("%s: process_stream() prints no error for the 3 elements no processor can "
             "handle" % lab)
    elif out != exp:
        nl_ = len(out.strip().splitlines())
        warn("%s: process_stream() prints %d line(s) %s; subject: %s"
             % (lab, nl_, q(out, 70), q(exp, 50)))
    if not check_stats(lab, ds, [("NumericProcessor", 4, 4)]):
        raise Abort()
    txt, log = new(C["TextProcessor"]), new(C["LogProcessor"])
    call("register_processor(TextProcessor())", ds.register_processor, txt)
    call("register_processor(LogProcessor())", ds.register_processor, log)
    lab = "subject scenario, step 2 (the 3 processors, same batch)"
    v, out = call("%s: process_stream()" % lab, ds.process_stream, copy.deepcopy(BATCH1))
    if out.strip():
        warn("%s: process_stream() prints %s while every element can be processed"
             % (lab, q(out, 60)))
    if not check_stats(lab, ds, [("NumericProcessor", 8, 8), ("TextProcessor", 3, 3),
                                 ("LogProcessor", 2, 2)]):
        raise Abort()
    lab = "subject scenario, step 3 (consume Numeric 3, Text 2, Log 1)"
    got = [run(num.output)[0] for _ in range(3)] + [run(txt.output)[0] for _ in range(2)]
    lg = run(log.output)[0]
    res("T")
    exp = [(0, "3.14"), (1, "-1"), (2, "2.71"), (0, "Hello world"), (1, "Hi")]
    if got != exp:
        fail("%s: output() returns %s; expected %s" % (lab, r(got, 100), r(exp, 100)))
    if not (isinstance(lg, tuple) and len(lg) == 2 and lg[0] == 0):
        fail("%s: LogProcessor output() returns %s; expected (0, %s)"
             % (lab, r(lg), q(logstr(LOG3))))
    check_stats(lab, ds, [("NumericProcessor", 8, 5), ("TextProcessor", 3, 1),
                          ("LogProcessor", 2, 1)])


def ds_routing(mod, kind="stream"):
    C, ds = stream_setup(mod, kind)
    N = C["NumericProcessor"]

    class Spy(N):
        # a NumericProcessor subclass that only accepts "ok": the DataStream
        # must ask each processor (validate / ingest), not look at the types
        def validate(self, data):
            return data == "ok"

        def ingest(self, data):
            if data != "ok":
                raise ValueError("only 'ok'")
            self.__dict__.setdefault("pt_seen", []).append(data)

    spy = new(Spy, "NumericProcessor subclass()")
    call("register_processor()", ds.register_processor, spy)
    stream = [7, "ok", 8, "x", "ok"]
    v, out = call("process_stream(%s)" % r(stream), ds.process_stream, stream)
    res("T")
    seen = spy.__dict__.get("pt_seen", [])
    if seen != ["ok", "ok"]:
        fail("polymorphism: with only a registered NumericProcessor subclass whose validate() "
             "accepts only 'ok', process_stream(%s) sends it %s; expected ['ok', 'ok'] (route "
             "with each processor's validate() / ingest(), not with the type of the data)"
             % (r(stream), r(seen)))
    check(out.strip() != "", "process_stream(%s) with a processor that only accepts 'ok' "
          "prints no error for 7, 8 and 'x'" % r(stream))
    # elements no processor can handle
    C, ds = stream_setup(mod, kind)
    for n in PROCS:
        call("register_processor(%s())" % n, ds.register_processor, new(C[n]))
    weird = [None, {1, 2}, 3 + 4j, b"bytes", object(), [[1, 2]], [None]]
    for x in weird:
        v, out, e = run(ds.process_stream, [x])
        lab = "DataStream with the 3 processors: process_stream([%s])" % r(x, 30)
        if check(e is None, "%s raises %s (print an error and continue)" % (lab, es(e))):
            check(out.strip() != "", "%s prints no error message" % lab)
    v, out, e = run(ds.process_stream, [])
    check(e is None, "process_stream([]) raises %s" % es(e))
    v, out, e = run(ds.process_stream, [None, 1, "a", LOG1, [1.5, 2]])
    check(e is None, "process_stream([None, 1, 'a', {...}, [1.5, 2]]) raises %s: an "
          "invalid element must not stop the stream" % es(e))
    check_stats("after the elements above (only 1, 'a', a log and [1.5, 2] can be processed)",
                ds, [("NumericProcessor", 3, 3), ("TextProcessor", 1, 1),
                     ("LogProcessor", 1, 1)])
    C, ds = stream_setup(mod, kind)
    for n in PROCS:
        call("register_processor(%s())" % n, ds.register_processor, new(C[n]))
    call("process_stream() of 3000 elements", ds.process_stream,
         list(range(1000)) + ["t%d" % i for i in range(1000)] + [LOG2] * 1000)
    check_stats("after a stream of 1000 int, 1000 str, 1000 logs", ds,
                [("NumericProcessor", 1000, 1000), ("TextProcessor", 1000, 1000),
                 ("LogProcessor", 1000, 1000)])


def ds_all(mod, kind="pipeline"):
    for f in (ds_stats, ds_scenario, ds_routing):
        try:
            f(mod, kind)
        except Abort:
            pass


# ------------------------------- data pipeline ------------------------------ #
class SpyPlugin:
    # an export plugin that only records what it receives (duck typing)
    def __init__(self):
        self.calls = []

    def process_output(self, data):
        self.calls.append(list(data) if isinstance(data, list) else data)


def pipe(ds, nb, label, exp, merged_ok=True):
    spy = SpyPlugin()
    v, out, e = run(ds.output_pipeline, nb, spy)
    res("T")
    if e is not None:
        fail("%s: output_pipeline(%d, plugin) raises %s" % (label, nb, summary(e)))
        return False
    calls = [c for c in spy.calls if c != []]
    for c in calls:
        if not isinstance(c, list) or not all(isinstance(t, tuple) and len(t) == 2
                                              and isinstance(t[0], int)
                                              and isinstance(t[1], str) for t in c):
            fail("%s: output_pipeline(%d, plugin) calls plugin.process_output(%s); expected "
                 "a list[tuple[int, str]]" % (label, nb, r(c)))
            return False
    flat = [t for c in calls for t in c]
    want = [t for c in exp for t in c]
    kinds = [n for n, c in zip(PROCS, exp) for _ in c]
    ok = len(flat) == len(want) and all(same_item(g, x, k) for g, x, k in
                                        zip(flat, want, kinds))
    if not ok:
        fail("%s: output_pipeline(%d, plugin) sends %s; expected %s"
             % (label, nb, r(calls, 120), r([c for c in exp if c], 120)))
        return False
    if len(calls) != len([c for c in exp if c]):
        warn("%s: output_pipeline(%d, plugin) calls process_output() %d time(s); the subject "
             "example calls it once per processor" % (label, nb, len(calls)))
    return True


def dp_pipeline(mod, kind="pipeline"):
    C, ds = stream_setup(mod, kind)
    for n in PROCS:
        call("register_processor(%s())" % n, ds.register_processor, new(C[n]))
    lab = "subject scenario"
    call("process_stream(%s)" % r(BATCH1, 40), ds.process_stream, copy.deepcopy(BATCH1))
    exp = [[(0, "3.14"), (1, "-1"), (2, "2.71")], [(0, "Hello world"), (1, "Hi"), (2, "five")],
           [(0, logstr(LOG3)), (1, logstr(LOG4))]]
    if not pipe(ds, 3, lab + " (first batch)", exp):
        raise Abort()
    check_stats(lab + ", after output_pipeline(3)", ds,
                [("NumericProcessor", 4, 1), ("TextProcessor", 3, 0), ("LogProcessor", 2, 0)])
    call("process_stream(%s)" % r(BATCH2, 40), ds.process_stream, copy.deepcopy(BATCH2))
    check_stats(lab + ", second batch", ds, [("NumericProcessor", 11, 8),
                                             ("TextProcessor", 7, 4), ("LogProcessor", 4, 2)])
    exp = [[(3, "42"), (4, "21"), (5, "32"), (6, "42"), (7, "64")],
           [(3, "I love AI"), (4, "LLMs are wonderful"), (5, "Stay healthy"),
            (6, "World hello")],
           [(2, logstr(LOG5)), (3, logstr(LOG6))]]
    if not pipe(ds, 5, lab + " (second batch)", exp):
        raise Abort()
    check_stats(lab + ", after output_pipeline(5)", ds,
                [("NumericProcessor", 11, 3), ("TextProcessor", 7, 0), ("LogProcessor", 4, 0)])
    pipe(ds, 0, lab + " (nb = 0)", [[], [], []])
    pipe(ds, 10, lab + " (nb = 10, only 3 numbers left)",
         [[(8, "84"), (9, "128"), (10, "168")], [], []])
    check_stats(lab + ", everything consumed", ds,
                [("NumericProcessor", 11, 0), ("TextProcessor", 7, 0), ("LogProcessor", 4, 0)])
    pipe(ds, 3, lab + " (nothing left)", [[], [], []])
    C, ds = stream_setup(mod, kind)
    pipe(ds, 3, "DataStream without processor", [[], [], []])


def plugin_classes(mod, C):
    m = importlib.import_module(mod)
    out = []
    seen = set()
    mods = [m] + [x for x in vars(m).values() if inspect.ismodule(x) and is_local(x)]
    for mm in mods:
        for n, c in sorted(vars(mm).items()):
            if (isinstance(c, type) and c is not C["ExportPlugin"] and c not in seen
                    and callable(getattr(c, "process_output", None))
                    and not getattr(c, "_is_protocol", False)
                    and getattr(c, "__module__", "") == mm.__name__):
                seen.add(c)
                out.append(c)
    return out


def json_strings(o):
    if isinstance(o, str):
        return [o]
    if isinstance(o, dict):
        return [s for k, v in o.items() for s in json_strings(k) + json_strings(v)]
    if isinstance(o, list):
        return [s for v in o for s in json_strings(v)]
    return [str(o)]


def find_json(out):
    # the JSON values printed by a plugin (one per line, or on several lines)
    found = []
    for li in out.splitlines():
        li = li.strip()
        if li[:1] in "{[" and li:
            try:
                found.append(json.loads(li))
            except ValueError:
                pass
    if not found and "{" in out:
        try:
            found.append(json.loads(out[out.index("{"):out.rindex("}") + 1]))
        except ValueError:
            pass
    return found


def csv_fields(line):
    return [x.strip().strip('"') for x in line.split(",")]


DATA = [(0, "Hello world"), (1, "Hi"), (2, "five")]


def dp_plugin(mod, which, kind="pipeline"):
    m, out, C = load(mod, kind)
    plugins = plugin_classes(mod, C)
    named = [c for c in plugins if which in c.__name__.lower()]
    cands = named or plugins
    ok_any = False
    tested = []
    for c in cands:
        p, o, e = run(c)
        if e is not None:
            warn("%s() raises %s: plugin not tested" % (c.__name__, summary(e)))
            continue
        v, out, e = run(p.process_output, list(DATA))
        lab = "%s().process_output(%s)" % (c.__name__, r(DATA, 50))
        if e is not None:
            if named:
                res("T")
                fail("%s raises %s" % (lab, summary(e)))
            continue
        if which == "json":
            js = find_json(out)
            if not js:
                if named:
                    res("T")
                    fail("%s prints %s: no valid JSON found (json.loads() fails)"
                         % (lab, q(out, 80)))
                continue
            strs = [s for j in js for s in json_strings(j)]
            res("T")
            if not all(x in strs for _, x in DATA):
                fail("%s prints the JSON %s: the values %s are not all in it"
                     % (lab, q(out, 70), r([x for _, x in DATA])))
                continue
        else:
            lines = out.splitlines()
            if "Hello world,Hi,five" not in lines:
                if any(csv_fields(li) == [x for _, x in DATA] for li in lines):
                    warn("%s prints %s; subject example: %s" % (lab, q(out, 60),
                                                                q("Hello world,Hi,five")))
                elif named:
                    res("T")
                    fail("%s prints %s; expected a CSV line %s" % (lab, q(out, 70),
                                                                  q("Hello world,Hi,five")))
                    continue
                else:
                    continue
            res("T")
        ok_any = True
        tested.append(c.__name__)
        edge_plugin(c, p, which)
    if not ok_any and not named:
        res("T")
        fail("no %s export plugin found (a class with process_output() and \"%s\" in its name)"
             % (which.upper(), which.upper()))
    if tested:
        info("(%s)" % ", ".join(tested))


def edge_plugin(c, p, which):
    lab = c.__name__ + "().process_output"
    v, out, e = run(p.process_output, [])
    res("T")
    if e is not None:
        warn("%s([]) raises %s" % (lab, summary(e)))
    if which == "json":
        data = [(0, 'say "hi"'), (1, "back\\slash"), (2, "héllo ✓")]
        v, out, e = run(p.process_output, data)
        res("T")
        js = find_json(out) if e is None else []
        strs = [s for j in js for s in json_strings(j)]
        if e is not None or not all(x in strs for _, x in data):
            warn("%s(%s): %s (escape \" and \\ to produce valid JSON)"
                 % (lab, r(data, 50), "raises " + summary(e) if e else
                    "invalid JSON " + q(out, 50)))
    else:
        data = [(0, "a,b"), (1, "c")]
        v, out, e = run(p.process_output, data)
        res("T")
        if e is not None or '"a,b"' not in out:
            warn('%s(%s) prints %s: a value with a comma should be quoted ("a,b",c) to keep '
                 "valid CSV" % (lab, r(data), "raises " + summary(e) if e else q(out, 40)))


# ------------------- Creatures: factories, capabilities, strategies --------- #
TXT = {
    "Flameling": ("Flameling is a Fire type Creature", "Flameling uses Ember!"),
    "Pyrodon": ("Pyrodon is a Fire/Flying type Creature", "Pyrodon uses Flamethrower!"),
    "Aquabub": ("Aquabub is a Water type Creature", "Aquabub uses Water Gun!"),
    "Torragon": ("Torragon is a Water type Creature", "Torragon uses Hydro Pump!"),
    "Sproutling": ("Sproutling is a Grass type Creature", "Sproutling uses Vine Whip!"),
    "Bloomelle": ("Bloomelle is a Grass/Fairy type Creature", "Bloomelle uses Petal Dance!"),
    "Shiftling": ("Shiftling is a Normal type Creature", "Shiftling attacks normally."),
    "Morphagon": ("Morphagon is a Normal/Dragon type Creature", "Morphagon attacks normally."),
}
HEAL_TXT = {"Sproutling": "Sproutling heals itself for a small amount",
            "Bloomelle": "Bloomelle heals itself and others for a large amount"}
TRANSFORM_TXT = {
    "Shiftling": ("Shiftling shifts into a sharper form!", "Shiftling performs a boosted strike!",
                  "Shiftling returns to normal."),
    "Morphagon": ("Morphagon morphs into a dragonic battle form!",
                  "Morphagon unleashes a devastating morph strike!",
                  "Morphagon stabilizes its form.")}
FACTS = {"FlameFactory": ("Flameling", "Pyrodon"), "AquaFactory": ("Aquabub", "Torragon"),
         "HealingCreatureFactory": ("Sproutling", "Bloomelle"),
         "TransformCreatureFactory": ("Shiftling", "Morphagon")}
FACT_CAP = {"FlameFactory": "", "AquaFactory": "", "HealingCreatureFactory": "heal",
            "TransformCreatureFactory": "transform"}
CAPS = {"heal": ("HealCapability", ("heal",)),
        "transform": ("TransformCapability", ("transform", "revert"))}
STRAT_CAP = {"NormalStrategy": "", "AggressiveStrategy": "transform",
             "DefensiveStrategy": "heal"}


def exposed_factories(pkg):
    found = {}
    for n, v in sorted(vars(pkg).items()):
        if (isinstance(v, type) and callable(getattr(v, "create_base", None))
                and callable(getattr(v, "create_evolved", None)) and not abstracts(v)
                and v not in found.values()):
            found[n] = v
    # a class that other factories inherit from is not a concrete factory
    return {n: v for n, v in found.items()
            if not any(w is not v and issubclass(w, v) for w in found.values())}


class World:
    """The factories exposed by some packages, and what they create."""

    def __init__(self, pkgnames):
        self.facts = {}
        self.pkgs = {}
        self.printed = {}
        for pn in pkgnames:
            pkg, out = imp(pn)
            self.pkgs[pn] = pkg
            self.printed[pn] = out
            for n, v in exposed_factories(pkg).items():
                if v not in self.facts.values():
                    self.facts[n] = v
        self.items = []         # (factory name, "base" / "evolved", creature)
        for n, fc in self.facts.items():
            for which in ("base", "evolved"):
                c = self.spawn(n, which, report=True)
                if c is not None:
                    self.items.append((n, which, c))
        self.creature = None
        for n, w, c in self.items:
            self.creature = root_abstract(type(c), "attack", "Creature")
            if self.creature:
                break
        self.caps = {}
        for cap, (cname, meths) in CAPS.items():
            self.caps[cap] = None
            for n, w, c in self.items:
                found = None
                for k in type(c).__mro__:
                    if set(meths) <= abstracts(k):
                        found = k
                if found is not None:
                    self.caps[cap] = found
                    break

    def spawn(self, fname, which, report=False):
        fc = self.facts[fname]
        f, o, e = run(fc)
        if e is not None:
            if report:
                fail("%s() raises %s (a factory is created without argument)"
                     % (fname, summary(e)))
            return None
        c, o, e = run(getattr(f, "create_" + which))
        if e is not None:
            if report:
                fail("%s().create_%s() raises %s" % (fname, which, summary(e)))
            return None
        return c

    def has(self, c, cap):
        k = self.caps.get(cap)
        return k is not None and isinstance(c, k)

    def kind(self, c):
        return [cap for cap in CAPS if self.has(c, cap)]


def cname(c):
    return type(c).__name__


def text_of(ret, out):
    if isinstance(ret, str):
        return out + "\n" + ret
    if isinstance(ret, (list, tuple)):
        return out + "\n" + "\n".join(str(x) for x in ret)
    return out


def str_call(label, f, *a):
    """calls a method that must return a str: (value or None)"""
    v, out, e = run(f, *a)
    res("T")
    if e is not None:
        fail("%s raises %s" % (label, summary(e)))
        return None
    if not isinstance(v, str):
        fail("%s returns %s%s; expected a str (return the message, do not print it)"
             % (label, r(v), " and prints " + q(out, 40) if out else ""))
        return None
    if out:
        warn("%s prints %s and returns %s: the message should only be returned"
             % (label, q(out, 40), q(v, 40)))
    return v


def heal_call(c):
    v, out, e = run(c.heal)
    if isinstance(e, TypeError) and nb_required(c.heal) >= 1:
        v, out, e = run(c.heal, c)
        return v, out, e, "heal(itself)"
    return v, out, e, "heal()"


# --------------------------------- packages --------------------------------- #
def cr_package(pkgname, expected):
    w = World([pkgname])
    pkg = w.pkgs[pkgname]
    if w.printed[pkgname]:
        warn("import %s prints %s: a package should not print anything"
             % (pkgname, q(w.printed[pkgname], 40)))
    res("T")
    if not w.facts:
        hidden = []
        for m in submodules(pkg)[1:]:
            hidden += ["%s.%s" % (m.__name__, n) for n in exposed_factories(m)]
        if hidden:
            fail("%s/__init__.py does not expose the factories (found: %s)"
                 % (pkgname, ", ".join(hidden[:3])))
        else:
            fail("package %s: no factory found (a class with create_base() and "
                 "create_evolved())" % pkgname)
        res("X")
        raise Abort()
    exp = [x for x in expected.split(",") if x]
    miss = [x for x in exp if x not in w.facts]
    if miss:
        warn("%s does not expose %s; found: %s (other names are allowed if the patterns are "
             "kept: these factories are tested)" % (pkgname, ", ".join(miss),
                                                   ", ".join(w.facts)))
    roots = set(root_abstract(type(c), "attack", "Creature") for _, _, c in w.items)
    roots.discard(None)
    for n, v in sorted(vars(pkg).items()):
        if isinstance(v, type) and not abstracts(v) and any(issubclass(v, k) for k in roots):
            res("T")
            fail("package %s exposes the concrete creature %s: it must only expose the "
                 "factories" % (pkgname, n))
    allv = getattr(pkg, "__all__", None)
    if allv is not None:
        res("T")
        bad = [x for x in allv if not hasattr(pkg, x)]
        if bad:
            fail("%s.__all__ lists names that do not exist: %s" % (pkgname, ", ".join(bad)))
    if not w.items:
        res("X")
    info("(exposes %s)" % ", ".join(w.facts))


def cr_abstract(pkgname, caps, basepkg="-"):
    w = World([pkgname])
    if not w.items:
        raise Abort()
    C = w.creature
    if not check(C is not None, "%s does not inherit from an abstract Creature class with an "
                 "abstract attack() method" % cname(w.items[0][2])):
        raise Abort()
    for n, which, c in w.items:
        check(isinstance(c, C), "%s (%s().create_%s()) does not inherit from %s"
              % (cname(c), n, which, C.__name__))
    if not issubclass(C, abc.ABC):
        warn("%s uses ABCMeta but does not inherit from ABC" % C.__name__)
    check("describe" in vars(C) and "describe" not in abstracts(C),
          "describe() must be a concrete method of %s (generic, not abstract)" % C.__name__)
    check(cannot_inst(C, (), ("Test", "Test"), ("Test",)),
          "%s() can be instantiated: an abstract class must raise TypeError" % C.__name__)
    names = [C.__name__]
    fcls = list(w.facts.values())
    CF = root_abstract(fcls[0], "create_base", "CreatureFactory")
    if check(CF is not None, "%s does not inherit from an abstract CreatureFactory with "
             "abstract create_base() / create_evolved()" % fcls[0].__name__):
        names.append(CF.__name__)
        check({"create_base", "create_evolved"} <= abstracts(CF),
              "%s: create_base() and create_evolved() must both be abstract" % CF.__name__)
        check(cannot_inst(CF), "%s() can be instantiated: an abstract class must raise "
              "TypeError" % CF.__name__)
        if not issubclass(CF, abc.ABC):
            warn("%s uses ABCMeta but does not inherit from ABC" % CF.__name__)
        for fc in fcls:
            check(issubclass(fc, CF), "%s does not inherit from %s" % (fc.__name__, CF.__name__))
    if basepkg != "-":
        b = World([basepkg])
        if b.items and b.creature is not None:
            BC = b.creature
            BF = root_abstract(list(b.facts.values())[0], "create_base", "CreatureFactory")
            check(C is BC, "%s must build upon %s: its creatures inherit from %s.%s, not from "
                  "the Creature of %s" % (pkgname, basepkg, C.__module__, C.__name__, basepkg))
            if BF is not None:
                for fc in fcls:
                    check(issubclass(fc, BF), "%s does not inherit from the %s of %s"
                          % (fc.__name__, BF.__name__, basepkg))
    for cap in [x for x in caps.split(",") if x]:
        want, meths = CAPS[cap]
        K = w.caps[cap]
        if not check(K is not None, "no creature has a %s: an abstract class with abstract "
                     "%s() (searched in the classes of the creatures)"
                     % (want, "() and ".join(meths))):
            continue
        names.append(K.__name__)
        if K.__name__ != want:
            warn("the %s capability class is named %s (subject: %s)"
                 % (cap, K.__name__, want))
        check(not issubclass(K, C), "%s inherits from %s: a capability must not be a Creature"
              % (K.__name__, C.__name__))
        check(not issubclass(C, K), "%s inherits from %s: the capability must stay separate"
              % (C.__name__, K.__name__))
        check(cannot_inst(K), "%s() can be instantiated: an abstract class must raise TypeError"
              % K.__name__)
        if not issubclass(K, abc.ABC):
            warn("%s uses ABCMeta but does not inherit from ABC" % K.__name__)
        holders = [c for _, _, c in w.items if isinstance(c, K)]
        check(holders, "no creature of %s has the %s capability" % (pkgname, want))
    for n, which, c in w.items:
        cap = FACT_CAP.get(n)
        if cap and w.caps.get(cap) is not None:
            check(isinstance(c, w.caps[cap]), "%s (%s().create_%s()) does not inherit from %s"
                  % (cname(c), n, which, w.caps[cap].__name__))
    info("(%s)" % ", ".join(names))


def cr_factories(pkgname):
    w = World([pkgname])
    by_class = {}
    for n, fc in w.facts.items():
        b, e = w.spawn(n, "base"), w.spawn(n, "evolved")
        if b is None or e is None:
            continue
        check(type(b) is not type(e), "%s: create_base() and create_evolved() both create a %s"
              % (n, cname(b)))
        for which, c in (("base", b), ("evolved", e)):
            check(not abstracts(type(c)), "%s().create_%s() returns an abstract class"
                  % (n, which))
            prev = by_class.setdefault(type(c), n)
            check(prev == n, "%s and %s both create a %s (one family per factory)"
                  % (prev, n, cname(c)))
            f, o, x = run(fc)
            c2 = run(getattr(f, "create_" + which))[0]
            if c2 is c:
                warn("%s().create_%s() returns the same object each time" % (n, which))
            elif type(c2) is not type(c):
                warn("%s().create_%s() does not always create the same creature (%s, then %s)"
                     % (n, which, cname(c), cname(c2)))
        if n in FACTS:
            got = (cname(b), cname(e))
            if got != FACTS[n]:
                warn("%s creates %s / %s; subject: %s / %s" % ((n,) + got + FACTS[n]))
    info("(%s)" % ", ".join("%s / %s" % (cname(b), cname(e)) for b, e in
                            [(w.spawn(n, "base"), w.spawn(n, "evolved")) for n in w.facts]
                            if b is not None and e is not None))


def cr_methods(pkgname):
    w = World([pkgname])
    C = w.creature
    for n, which, c in w.items:
        lab = "%s().create_%s()" % (n, which)
        d = str_call("%s.describe()" % lab, c.describe)
        a = str_call("%s.attack()" % lab, c.attack)
        if d is not None:
            check(d.strip() != "", "%s.describe() returns an empty string" % lab)
            check(cname(c) in d or any(isinstance(v, str) and v and v in d
                                       for v in vars(c).values()),
                  "%s.describe() returns %s: it does not contain the name of the creature"
                  % (lab, q(d)))
        if a is not None:
            check(a.strip() != "", "%s.attack() returns an empty string" % lab)
        if C is not None and "describe" in vars(type(c)) and type(c) is not C:
            warn("%s overrides describe(): it should be the generic method of %s"
                 % (cname(c), C.__name__))
        strs = [v for v in vars(c).values() if isinstance(v, str)]
        if len(strs) < 2:
            warn("%s holds %d str attribute(s) (%s): Creature should hold the name and the "
                 "type" % (cname(c), len(strs), r(vars(c), 50)))
    # two creatures of the same factory are independent objects
    if w.items:
        n = w.items[0][0]
        a, b = w.spawn(n, "base"), w.spawn(n, "base")
        if a is not None and b is not None and a is not b:
            check(run(a.describe)[0] == run(b.describe)[0],
                  "two %s describe() differently" % cname(a))


def cr_texts(pkgname):
    w = World([pkgname])
    nb = 0
    for n, which, c in w.items:
        if cname(c) not in TXT:
            continue
        exp_d, exp_a = TXT[cname(c)]
        d, a = run(c.describe)[0], run(c.attack)[0]
        nb += 2
        res("T")
        if d != exp_d:
            warn("%s.describe() returns %s; subject example: %s" % (cname(c), q(d), q(exp_d)))
        if a != exp_a:
            warn("%s.attack() returns %s; subject example: %s" % (cname(c), q(a), q(exp_a)))
    info("(%d texts as in the subject example)" % nb if nb else
         "(creature names differ from the subject: texts not compared)")


def cr_heal(pkgname):
    w = World([pkgname])
    K = w.caps.get("heal")
    if not check(K is not None, "no heal capability found (see the abstract classes line)"):
        return
    holders = [(n, which, c) for n, which, c in w.items if isinstance(c, K)]
    for n, which, c in holders:
        lab = "%s().create_%s()" % (n, which)
        check(not abstracts(type(c)), "%s is abstract" % cname(c))
        v, out, e, how = heal_call(c)
        res("T")
        if e is not None:
            fail("%s.%s raises %s" % (lab, how, summary(e)))
            continue
        if not isinstance(v, str) or not v.strip():
            fail("%s.%s returns %s; expected a str message (like attack())" % (lab, how, r(v)))
            continue
        if cname(c) in HEAL_TXT and v != HEAL_TXT[cname(c)]:
            warn("%s.%s returns %s; subject example: %s" % (cname(c), how, q(v),
                                                           q(HEAL_TXT[cname(c)])))
        a = str_call("%s.attack() after %s" % (lab, how), c.attack)
        if a is not None:
            check(a == run(w.spawn(n, which).attack)[0],
                  "%s.attack() changes after %s" % (lab, how))
    info("(%s)" % ", ".join(cname(c) for _, _, c in holders))


def cr_transform(pkgname):
    w = World([pkgname])
    K = w.caps.get("transform")
    if not check(K is not None, "no transform capability found (see the abstract classes "
                 "line)"):
        return
    holders = [(n, which, c) for n, which, c in w.items if isinstance(c, K)]
    for n, which, c in holders:
        lab = "%s().create_%s()" % (n, which)
        a0 = str_call(lab + ".attack()", c.attack)
        t = str_call(lab + ".transform()", c.transform)
        a1 = str_call(lab + ".attack() after transform()", c.attack)
        rv = str_call(lab + ".revert()", c.revert)
        a2 = str_call(lab + ".attack() after revert()", c.attack)
        if None in (a0, t, a1, rv, a2):
            continue
        check(a1 != a0, "%s.attack() returns %s before and after transform(): the transformed "
              "state must change what attack() returns" % (lab, q(a0)))
        check(a2 == a0, "%s.attack() after revert() returns %s; expected the normal attack %s"
              % (lab, q(a2), q(a0)))
        x, y = w.spawn(n, which), w.spawn(n, which)
        if x is not None and y is not None and x is not y:
            run(x.transform)
            check(run(y.attack)[0] == a0, "transforming one %s also transforms another one "
                  "(the state must be an instance attribute)" % cname(c))
            check(run(x.attack)[0] == a1, "%s: attack() after transform() differs between two "
                  "instances" % cname(c))
        if cname(c) in TRANSFORM_TXT:
            exp = TRANSFORM_TXT[cname(c)]
            for what, got, want in (("transform()", t, exp[0]), ("attack() after transform()",
                                                                 a1, exp[1]),
                                    ("revert()", rv, exp[2])):
                if got != want:
                    warn("%s.%s returns %s; subject example: %s" % (cname(c), what, q(got),
                                                                   q(want)))
    info("(%s)" % ", ".join(cname(c) for _, _, c in holders))


# -------------------------------- strategies -------------------------------- #
def strategies(pkgname, names):
    pkg, out = imp(pkgname)
    S = {}
    miss = []
    for n in names.split(","):
        c = find_class(pkg, n)
        if c is None:
            miss.append(n)
        else:
            S[n] = c
    if miss:
        fail("package %s: no class %s" % (pkgname, ", ".join(miss)))
        res("X")
        raise Abort()
    return pkg, out, S


def inst(S, n):
    s, o, e = run(S[n])
    if e is not None:
        fail("%s() raises %s (a strategy is created without argument)" % (n, summary(e)))
        raise Abort()
    return s


def st_classes(pkgname, names, factpkgs):
    pkg, out, S = strategies(pkgname, names)
    if out:
        warn("import %s prints %s: a package should not print anything" % (pkgname, q(out, 40)))
    BS = find_class(pkg, "BattleStrategy")
    if BS is None:
        BS = root_abstract(S["NormalStrategy"], "act")
        warn("no class named BattleStrategy in %s%s" % (pkgname, " (found: %s)" % BS.__name__
                                                         if BS else ""))
    if not check(BS is not None, "no abstract BattleStrategy class with an abstract act()"):
        raise Abort()
    check({"act", "is_valid"} <= abstracts(BS),
          "BattleStrategy: act() and is_valid() must be abstract (@abstractmethod); abstract "
          "methods found: %s" % (", ".join(sorted(abstracts(BS))) or "none"))
    check(cannot_inst(BS), "BattleStrategy() can be instantiated: an abstract class must raise "
          "TypeError")
    if isinstance(BS, abc.ABCMeta) and not issubclass(BS, abc.ABC):
        warn("BattleStrategy uses ABCMeta but does not inherit from ABC")
    for n, c in S.items():
        if check(issubclass(c, BS), "%s does not inherit from BattleStrategy" % n):
            check(not abstracts(c), "%s is still abstract (not implemented: %s)"
                  % (n, ", ".join(sorted(abstracts(c)))))
            for meth in ("act", "is_valid"):
                dc = defined_in(c, meth)
                check(dc is not None and dc is not BS, "%s does not override %s()" % (n, meth))
            o, _, e = run(c)
            check(e is None, "%s() raises %s (a strategy is created without argument)"
                  % (n, es(e)))
    excs = []
    for m in submodules(pkg):
        for n, v in vars(m).items():
            if (isinstance(v, type) and issubclass(v, Exception) and is_local(sys.modules.get(
                    v.__module__)) and n not in excs):
                excs.append(n)
    info("(%s%s)" % (", ".join([BS.__name__] + list(S)),
                     ", exception: " + ", ".join(excs) if excs else ""))


def expected_seq(w, n, which, strat):
    """what the strategy should produce, computed on a twin creature"""
    t = w.spawn(n, which)
    if t is None:
        return None
    cap = STRAT_CAP[strat]
    if cap == "transform":
        seq = [run(t.transform)[0], run(t.attack)[0], run(t.revert)[0]]
    elif cap == "heal":
        seq = [run(t.attack)[0], heal_call(t)[0]]
    else:
        seq = [run(t.attack)[0]]
    return seq if all(isinstance(x, str) and x for x in seq) else None


def do_act(s, c, other):
    k = nb_required(s.act)
    args = [c] + [other] * max(0, k - 1)
    return run(s.act, *args)


def in_order(text, seq):
    pos = 0
    for x in seq:
        i = text.find(x, pos)
        if i < 0:
            return False
        pos = i + len(x)
    return True


def st_is_valid(pkgname, names, factpkgs):
    pkg, out, S = strategies(pkgname, names)
    w = World(factpkgs.split(","))
    for sn in S:
        s = inst(S, sn)
        cap = STRAT_CAP.get(sn, "")
        if cap and w.caps.get(cap) is None:
            continue
        for n, which, c in w.items:
            exp = True if not cap else w.has(c, cap)
            v, o, e = run(s.is_valid, c)
            lab = "%s().is_valid(%s)" % (sn, cname(c))
            res("T")
            if e is not None:
                fail("%s raises %s" % (lab, summary(e)))
            elif not isinstance(v, bool):
                fail("%s returns %s; expected a bool (%s)" % (lab, r(v), exp))
            elif v != exp:
                fail("%s returns %s; expected %s (%s)" % (
                    lab, v, exp, "suitable for any creature" if not cap else
                    "%s %s the %s capability" % (cname(c), "has" if exp else "does not have",
                                                 cap)))


def st_act(pkgname, names, factpkgs):
    pkg, out, S = strategies(pkgname, names)
    w = World(factpkgs.split(","))
    other = w.items[0][2] if w.items else None
    done = []
    for sn in S:
        s = inst(S, sn)
        cap = STRAT_CAP.get(sn, "")
        for n, which, c in w.items:
            if cap and not w.has(c, cap):
                continue
            seq = expected_seq(w, n, which, sn)
            if seq is None:
                continue
            c = w.spawn(n, which)
            normal = run(w.spawn(n, which).attack)[0]
            v, o, e = do_act(s, c, other)
            lab = "%s().act(%s)" % (sn, cname(c))
            res("T")
            if e is not None:
                fail("%s raises %s" % (lab, summary(e)))
                continue
            text = text_of(v, o)
            if not in_order(text, seq):
                fail("%s gives %s; expected %s" % (lab, q(text.strip(), 80),
                                                   " then ".join(q(x, 40) for x in seq)))
                continue
            done.append(lab)
            if cap == "transform":
                check(run(c.attack)[0] == normal, "after %s, %s is still transformed (attack() "
                      "returns %s): the strategy must revert" % (lab, cname(c),
                                                                 q(run(c.attack)[0])))
    info("(%d valid strategy / creature pairs)" % len(done))


def st_invalid(pkgname, names, factpkgs):
    pkg, out, S = strategies(pkgname, names)
    w = World(factpkgs.split(","))
    other = w.items[0][2] if w.items else None
    for sn in S:
        s = inst(S, sn)
        cap = STRAT_CAP.get(sn, "")
        if not cap or w.caps.get(cap) is None:
            continue
        for n, which, c in w.items:
            if w.has(c, cap):
                continue
            v, o, e = do_act(s, c, other)
            lab = "%s().act(%s)" % (sn, cname(c))
            if not check(e is not None, "%s does not raise an exception (%s has no %s "
                         "capability)" % (lab, cname(c), cap)):
                continue
            if type(e).__module__ == "builtins":
                warn("%s raises the built-in %s: the subject asks for a dedicated exception "
                     "(your own exception class)" % (lab, type(e).__name__))
            if not str(e).strip():
                warn("%s raises %s without message (a clear message is required)"
                     % (lab, type(e).__name__))
            a = run(c.attack)[0]
            if o.strip() or (isinstance(a, str) and a in o):
                warn("%s prints %s before raising: check the creature before acting"
                     % (lab, q(o, 40)))


def make_creatures(w):
    """test creatures built here: plain, transform and heal capabilities"""
    C = w.creature
    TK, HK = w.caps.get("transform"), w.caps.get("heal")
    params = []
    try:
        params = [p for p in list(inspect.signature(C.__init__).parameters.values())[1:]
                  if p.default is p.empty and p.kind in (p.POSITIONAL_ONLY,
                                                         p.POSITIONAL_OR_KEYWORD)]
    except (TypeError, ValueError):
        pass

    def build(cls, label):
        args = ["Test" if "type" in p.name else label for p in params]
        o, out, e = run(cls, *args)
        return o

    class Plainling(C):
        def attack(self):
            return "Plainling pokes!"

    made = {"plain": build(Plainling, "Plainling")}
    if TK is not None:
        class Testmorph(C, TK):
            def attack(self):
                return ("Testmorph strikes hard!" if self.__dict__.get("pt_t")
                        else "Testmorph pokes!")

            def transform(self):
                self.__dict__["pt_t"] = True
                return "Testmorph transforms!"

            def revert(self):
                self.__dict__["pt_t"] = False
                return "Testmorph reverts!"

        made["transform"] = build(Testmorph, "Testmorph")
    if HK is not None:
        class Testheal(C, HK):
            def attack(self):
                return "Testheal pokes!"

            def heal(self, *a):
                return "Testheal heals!"

        made["heal"] = build(Testheal, "Testheal")
    return made


def st_capabilities(pkgname, names, factpkgs, strict="1"):
    pkg, out, S = strategies(pkgname, names)
    w = World(factpkgs.split(","))
    if w.creature is None:
        raise Abort()
    made = make_creatures(w)
    report = fail if strict == "1" else warn
    for kind, c in made.items():
        if c is None:
            warn("could not create a test creature (%s) from %s: not tested"
                 % (kind, w.creature.__name__))
            continue
        for sn in S:
            s = inst(S, sn)
            cap = STRAT_CAP.get(sn, "")
            if cap and w.caps.get(cap) is None:
                continue
            exp = (not cap) or cap == kind
            v, o, e = run(s.is_valid, c)
            res("T")
            if e is not None or v != exp:
                report("%s().is_valid() on a new %s creature (made by the tester, inheriting "
                       "from %s%s) %s; expected %s: check capabilities with isinstance, not "
                       "the concrete family" % (
                           sn, kind, w.creature.__name__,
                           " and " + w.caps[kind].__name__ if kind in w.caps else "",
                           "raises " + summary(e) if e else "returns " + r(v), exp))
            elif exp and kind == "transform" and cap == "transform":
                v, o, e = do_act(s, c, c)
                res("T")
                txt = text_of(v, o)
                if e is not None or not in_order(txt, ["Testmorph transforms!",
                                                       "Testmorph strikes hard!",
                                                       "Testmorph reverts!"]):
                    report("%s().act() on a new transform creature (made by the tester) %s; "
                           "expected its transform(), attack(), revert() messages"
                           % (sn, "raises " + summary(e) if e else "gives " + q(txt, 60)))


def find_battle(mod):
    cands = []
    for n, f in vars(mod).items():
        if (inspect.isfunction(f) and f.__module__ == mod.__name__
                and ("battle" in n.lower() or "tournament" in n.lower())
                and nb_required(f) == 1):
            cands.append((n != "battle", n, f))
    return sorted(cands)[0][1:] if cands else (None, None)


def st_battle(script, names, factpkgs, strategy_pkg):
    m, out = imp(script)
    pkg, o, S = strategies(strategy_pkg, names)
    w = World(factpkgs.split(","))
    fname, fn = find_battle(m)
    if fn is None:
        warn("no battle(opponents) function found in %s.py: not tested (run it by hand)"
             % script)
        return
    by_kind = {}
    for n, which, c in w.items:
        if which == "base":
            k = (w.kind(c) or [""])[0]
            by_kind.setdefault(k, n)
    plain, trans, heal = by_kind.get(""), by_kind.get("transform"), by_kind.get("heal")
    if plain is None or trans is None:
        warn("no plain and transform factories found: %s() not tested" % fname)
        return
    strat = {"": "NormalStrategy", "transform": "AggressiveStrategy",
             "heal": "DefensiveStrategy"}
    opp = [(plain, ""), (trans, "transform"), (heal, "heal") if heal and
           "DefensiveStrategy" in S else (plain, "")]

    def opponents(lst):
        return [(w.facts[n](), inst(S, strat[k] if k in strat else k)) for n, k in lst]

    # 3 valid opponents: each one fights the 2 others
    nb = len(opp)
    v, out, e = run(fn, opponents(opp))
    lab = "%s() with %d valid opponents" % (fname, nb)
    if not check(e is None, "%s raises %s" % (lab, es(e))):
        return
    ok = False
    for which in ("base", "evolved"):
        want = {}
        for n, k in opp:
            seq = expected_seq(w, n, which, strat[k])
            for x in seq or []:
                want[x] = want.get(x, 0) + nb - 1
        counts = {x: out.count(x) for x in want}
        if any(counts.values()):
            ok = True
            break
    res("T")
    if not ok:
        fail("%s prints %s: no attack message of the creatures found" % (lab, q(out, 80)))
    else:
        for x, nbx in want.items():
            if counts[x] < nbx:
                fail("%s: %s printed %d time(s); expected %d (each opponent fights every other "
                     "one once)" % (lab, q(x, 50), counts[x], nbx))
                break
            if counts[x] > nbx:
                warn("%s: %s printed %d time(s); expected %d" % (lab, q(x, 50), counts[x],
                                                                 nbx))
                break
    # an invalid pair: handled, not propagated
    bad = [(trans, "transform"), (plain, "AggressiveStrategy")]
    v, out, e = run(fn, opponents(bad))
    lab = "%s() with an invalid pair (plain creature + AggressiveStrategy)" % fname
    if check(e is None, "%s lets the exception propagate (%s): handle it" % (lab, es(e))):
        c = w.spawn(plain, "base")
        x = do_act(inst(S, "AggressiveStrategy"), c, c)[2]
        if x is not None and str(x) and str(x) not in out:
            warn("%s does not print the error message %s" % (lab, q(str(x), 50)))
    for lst in ([], [(plain, "")]):
        v, out, e = run(fn, opponents(lst))
        res("T")
        if e is not None:
            warn("%s() with %d opponent(s) raises %s" % (fname, len(lst), summary(e)))
    info("(%s() tested)" % fname)
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
tar -C "$DIR" --exclude=.git --exclude=__pycache__ --exclude=.mypy_cache --exclude=.venv \
	--exclude=venv -cf - . | tar -C "$WORK" -xf -
export PT_ROOT="$WORK" PT_EXC="$TMP/exc" PT_RES="$TMP/res"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err, EXC
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

# Results of one test line: OK, KO (failures) or !! (only warnings)
# (after a timeout, the other tests of the same line are skipped)
t_begin() { T_FAILS=(); T_WARNS=(); T_N=0; T_INFO=""; T_TIMEOUT=0; T_STOP=0; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
t_end() {
	local m i=0
	if t_ok && [ ${#T_WARNS[@]} -eq 0 ]; then
		line_ok "$1" "${T_INFO:-($T_N tests)}"
		return
	fi
	if t_ok; then
		line_warn "$1" "${T_WARNS[0]}"
		for m in "${T_WARNS[@]:1:5}"; do note "!! $m"; done
		[ ${#T_WARNS[@]} -gt 6 ] && note "… (${#T_WARNS[@]} warnings in total)"
		return
	fi
	line_ko "$1"
	for m in "${T_FAILS[@]}"; do
		i=$((i + 1))
		if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
		msg "$m"
	done
	for m in "${T_WARNS[@]:0:2}"; do note "!! $m"; done
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# t_snip <folder> <test function> [params...]
# Runs one test function of the snippets ($TMP/tests.py) in a new python3 process
# (the folder is the current directory and is on sys.path) and reads its results.
t_snip() {
	local dir=$1 kind m ctx=""
	shift
	[ $T_TIMEOUT -eq 1 ] && return 1
	run_py /dev/null exec "$dir" "$TMP/tests.py" "$@"
	if [ -f "$TMP/res" ]; then
		while IFS=$'\t' read -r kind m; do
			case $kind in
				T) T_N=$((T_N + 1)) ;;
				F) t_fail "$m" ;;
				W) T_WARNS+=("$m") ;;
				I) T_INFO=$m ;;
				X) T_STOP=1 ;;
				C) ctx=$m ;;
			esac
		done < "$TMP/res"
	fi
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "${ctx:+$ctx: }infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
		return 1
	fi
	if [ $RC -eq 3 ]; then t_fail "unexpected exception during the tests: $EXC"; return 1; fi
	if [ $RC -ne 0 ]; then t_fail "python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"; return 1; fi
	return 0
}

# snip_line <label> <folder> <test function> [params...]: one test line
snip_line() {
	local label=$1
	shift
	t_begin
	t_snip "$@"
	t_end "$label"
}

# stop_here: after a first line that could not find the classes to test
stop_here() {
	[ $T_STOP -eq 1 ] || return 1
	line_skip "other tests" "skipped (fix the error above first)"
	return 0
}

# t_prog <label> <file> <expected output of the subject example>
# Runs "python3 file" from its folder: KO if it crashes, !! if the output
# differs from the example of the subject (the scenario and wording are free).
t_prog() {
	local label=$1 f=$2 d
	printf '%s' "$3" > "$TMP/exp"
	run_py /dev/null script "$WORK/$f"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		line_ko "$label"; msg "python3 $f: infinite loop or too slow (more than 10 s)"; return
	fi
	if [ $RC -eq 3 ]; then
		line_ko "$label"; msg "python3 $f: raises $EXC"
		[ -s "$TMP/out" ] && note "last line printed: $(tail -1 "$TMP/out" | cut -c1-90)"
		return
	fi
	if [ $RC -ne 0 ]; then
		line_ko "$label"; msg "python3 $f: ${EXC:-exits with status $RC} $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"; return
	fi
	if [ ! -s "$TMP/out" ]; then line_ko "$label"; msg "python3 $f prints nothing"; return; fi
	d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out")
	if [ -z "$d" ]; then line_ok "$label" "(runs, same output as the subject example)"
	else
		line_warn "$label" "runs without error, but the output differs from the subject example:"
		note "$d"
		note "(the example is not imposed word for word: compare by hand with the subject)"
	fi
}

# flake8_line <files...>: one line, OK / KO / skipped
flake8_line() {
	local out
	if [ ${#FLAKE8[@]} -eq 0 ]; then line_skip "flake8" "not installed"; return; fi
	out=$(cd "$WORK" && "${FLAKE8[@]}" "$@" 2>&1)
	if [ $? -gt 1 ] && ! grep -q -E ':[0-9]+:[0-9]+: ' <<< "$out"; then
		line_skip "flake8" "flake8 fails to run: $(head -1 <<< "$out" | cut -c1-80)"; return
	fi
	if [ -z "$out" ]; then line_ok "flake8"
	else
		line_ko "flake8"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
	fi
}

# mypy_line <files...>
# The subject asks to test an invalid ingest() call, which gives a mypy error
# "on purpose": the [arg-type] errors about ingest() are accepted.
mypy_line() {
	local out exp
	if [ ${#MYPY[@]} -eq 0 ]; then line_skip "mypy" "not installed"; return; fi
	out=$(cd "$WORK" && "${MYPY[@]}" --cache-dir "$TMP/mypy_cache" --follow-imports=silent \
		--no-error-summary "$@" 2>&1)
	if [ $? -gt 1 ] && ! grep -q -E 'error:' <<< "$out"; then
		line_skip "mypy" "mypy fails to run: $(head -1 <<< "$out" | cut -c1-80)"; return
	fi
	out=$(grep -E 'error:' <<< "$out")
	exp=$(grep -E '"ingest".*\[arg-type\]' <<< "$out")
	out=$(grep -v -E '"ingest".*\[arg-type\]' <<< "$out")
	if [ -z "$out" ]; then
		if [ -z "$exp" ]; then line_ok "mypy"
		elif [ "$(wc -l <<< "$exp")" -eq 1 ]; then line_ok "mypy" "(1 expected error: the invalid ingest() test)"
		else
			line_warn "mypy" "$(wc -l <<< "$exp") [arg-type] errors on ingest(): only the invalid ingest() test should give one"
			head -4 <<< "$exp" | cut -c1-120 | while IFS= read -r l; do note "$l"; done
		fi
	else
		line_ko "mypy"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
	fi
}

# hints_line <files...>: every parameter and every return has a type hint
hints_line() {
	local f k l fn p out=() m
	for f in "$@"; do
		while read -r k l fn p; do
			case $k in
				PARAM) out+=("$f:$l: $fn(): parameter '$p' has no type hint") ;;
				RETURN) out+=("$f:$l: $fn(): no return type hint (-> ...)") ;;
			esac
		done < <(python3 -I "$PT" hints "$WORK/$f")
	done
	if [ ${#out[@]} -eq 0 ]; then line_ok "type hints" "(every parameter and return value)"; return; fi
	line_ko "type hints"
	for m in "${out[@]:0:6}"; do msg "$m"; done
	[ ${#out[@]} -gt 6 ] && msg "… (${#out[@]} missing type hints in total)"
	note "\"All code must include comprehensive type annotations\""
}

# auth_line <allowed calls> <allowed imports> <label of the authorized list> <files...>
# (calls: "*" = every built-in, "!name" = forbidden; imports: "LOCAL" = the student's modules)
auth_line() {
	local calls=$1 imps=$2 lab=$3 f kind a b bad=()
	shift 3
	for f in "$@"; do
		while read -r kind a b; do
			case $kind in
				CALL) bad+=("$f: $a() (line $b)") ;;
				IMPORT) bad+=("$f: import $a (line $b)") ;;
			esac
		done < <(python3 -I "$PT" ast "$WORK/$f" "$calls" "$imps" 0)
	done
	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized" "($lab)"; return; fi
	line_ko "authorized"
	for a in "${bad[@]:0:6}"; do msg "forbidden: $a"; done
	[ ${#bad[@]} -gt 6 ] && msg "… (${#bad[@]} in total)"
	note "authorized: $lab"
}

# ex_files <label> <files...> (paths in the module folder)
# → 0 if every file exists and parses (prints "not done" or the error otherwise)
ex_files() {
	local ex=$1 f miss="" nmiss=0 e
	shift
	for f in "$@"; do
		[ -f "$WORK/$f" ] || { miss+="$f "; nmiss=$((nmiss + 1)); }
	done
	if [ $nmiss -eq $# ]; then
		line_skip "$ex" "not done (${miss% } not found)"
		return 1
	elif [ $nmiss -gt 0 ]; then
		line_ko "files"; msg "missing: ${miss% }"
		return 1
	fi
	for f in "$@"; do
		e=$(python3 -I "$PT" ast "$WORK/$f" '*' '*' 0 | grep -m1 '^SYNTAX')
		if [ -n "$e" ]; then
			read -r _ l e <<< "$e"
			line_ko "$f"; msg "SyntaxError line $l: $e"
			return 1
		fi
	done
	return 0
}

# pkg_files <label> <package> <scripts...> → FILES (scripts + every .py of the package)
# A package needs its __init__.py ("MANDATORY" in the subject).
pkg_files() {
	local label=$1 pkg=$2 f found=0
	shift 2
	FILES=()
	for f in "$@"; do [ -f "$WORK/$f" ] && found=1; done
	if [ ! -d "$WORK/$pkg" ] && [ $found -eq 0 ]; then
		line_skip "$label" "not done ($pkg/ and $* not found)"
		return 1
	fi
	if [ ! -f "$WORK/$pkg/__init__.py" ]; then
		line_ko "package"
		msg "$pkg/__init__.py not found: $pkg/ must be a package (\"a __init__.py file is MANDATORY\")"
		return 1
	fi
	FILES=("$@")
	mapfile -t -O ${#FILES[@]} FILES < <(cd "$WORK" && find "$pkg" -name '*.py' \
		! -path '*/__pycache__/*' | sort)
	ex_files "$label" "${FILES[@]}"
}

nl=$'\n'

# ---------------- Data processors / data stream / data pipeline ------------- #
AUTH_DATA="abc,typing,__future__,LOCAL"

# data_static <file> <allowed calls> <authorized label>: flake8, type hints, mypy, imports
data_static() {
	flake8_line "$1"
	hints_line "$1"
	mypy_line "$1"
	auth_line "$2" "$AUTH_DATA" "$3" "$1"
}

# test_data_processor <folder> <file> <allowed calls> <authorized label> <warn on import 0|1>
test_data_processor() {
	local d="$WORK/$1" m
	m=$(basename "$2" .py)
	data_static "$2" "$3" "$4"
	snip_line "classes" "$d" dp_classes "$m" "" "$5"
	stop_here && return
	snip_line "signatures" "$d" dp_sigs "$m"
	snip_line "validate()" "$d" dp_validate "$m"
	snip_line "invalid ingest()" "$d" dp_invalid "$m"
	snip_line "ingest() / output()" "$d" dp_output "$m"
	snip_line "edge cases" "$d" dp_edge "$m"
}

# test_data_stream <folder> <file> <allowed calls> <authorized label> <warn on import 0|1>
test_data_stream() {
	local d="$WORK/$1" m
	m=$(basename "$2" .py)
	data_static "$2" "$3" "$4"
	snip_line "classes" "$d" dp_classes "$m" stream "$5"
	stop_here && return
	snip_line "signatures" "$d" dp_sigs "$m" stream
	snip_line "processors (ex0)" "$d" dp_all "$m" stream
	snip_line "statistics" "$d" ds_stats "$m" stream
	snip_line "subject scenario" "$d" ds_scenario "$m" stream
	snip_line "routing" "$d" ds_routing "$m" stream
}

# test_data_pipeline <folder> <file> <allowed calls> <authorized label> <warn on import 0|1>
test_data_pipeline() {
	local d="$WORK/$1" m
	m=$(basename "$2" .py)
	data_static "$2" "$3" "$4"
	snip_line "classes" "$d" dp_classes "$m" pipeline "$5"
	stop_here && return
	snip_line "signatures" "$d" dp_sigs "$m" pipeline
	snip_line "processors (ex0)" "$d" dp_all "$m" pipeline
	snip_line "data stream (ex1)" "$d" ds_all "$m" pipeline
	snip_line "output_pipeline()" "$d" dp_pipeline "$m" pipeline
	snip_line "CSV plugin" "$d" dp_plugin "$m" csv pipeline
	snip_line "JSON plugin" "$d" dp_plugin "$m" json pipeline
}

# Example outputs of the subject (compared with a warning only)
IFS= read -r -d '' EXP_DP <<'XEOF'
=== Code Nexus - Data Processor ===

Testing Numeric Processor...
 Trying to validate input '42': True
 Trying to validate input 'Hello': False
 Test invalid ingestion of string 'foo' without prior validation:
 Got exception: Improper numeric data
 Processing data: [1, 2, 3, 4, 5]
 Extracting 3 values...
 Numeric value 0: 1
 Numeric value 1: 2
 Numeric value 2: 3

Testing Text Processor...
 Trying to validate input '42': False
 Processing data: ['Hello', 'Nexus', 'World']
 Extracting 1 value...
 Text value 0: Hello

Testing Log Processor...
 Trying to validate input 'Hello': False
 Processing data: [{'log_level': 'NOTICE', 'log_message': 'Connection to server'}, {'log_level': 'ERROR', 'log_message': 'Unauthorized access!!'}]
 Extracting 2 values...
 Log entry 0: NOTICE: Connection to server
 Log entry 1: ERROR: Unauthorized access!!
XEOF
IFS= read -r -d '' EXP_DS <<'XEOF'
=== Code Nexus - Data Stream ===

Initialize Data Stream...
== DataStream statistics ==
No processor found, no data

Registering Numeric Processor

Send first batch of data on stream: ['Hello world', [3.14, -1, 2.71], [{'log_level': 'WARNING', 'log_message': 'Telnet access! Use ssh instead'}, {'log_level': 'INFO', 'log_message': 'User wil is connected'}], 42, ['Hi', 'five']]
DataStream error - Can't process element in stream: Hello world
DataStream error - Can't process element in stream: [{'log_level': 'WARNING', 'log_message': 'Telnet access! Use ssh instead'}, {'log_level': 'INFO', 'log_message': 'User wil is connected'}]
DataStream error - Can't process element in stream: ['Hi', 'five']
== DataStream statistics ==
Numeric Processor: total 4 items processed, remaining 4 on processor

Registering other data processors
Send the same batch again
== DataStream statistics ==
Numeric Processor: total 8 items processed, remaining 8 on processor
Text Processor: total 3 items processed, remaining 3 on processor
Log Processor: total 2 items processed, remaining 2 on processor

Consume some elements from the data processors: Numeric 3, Text 2, Log 1
== DataStream statistics ==
Numeric Processor: total 8 items processed, remaining 5 on processor
Text Processor: total 3 items processed, remaining 1 on processor
Log Processor: total 2 items processed, remaining 1 on processor
XEOF
IFS= read -r -d '' EXP_PIPE <<'XEOF'
=== Code Nexus - Data Pipeline ===

Initialize Data Stream...

== DataStream statistics ==
No processor found, no data

Registering Processors

Send first batch of data on stream: ['Hello world', [3.14, -1, 2.71], [{'log_level': 'WARNING', 'log_message': 'Telnet access! Use ssh instead'}, {'log_level': 'INFO', 'log_message': 'User wil is connected'}], 42, ['Hi', 'five']]

== DataStream statistics ==
Numeric Processor: total 4 items processed, remaining 4 on processor
Text Processor: total 3 items processed, remaining 3 on processor
Log Processor: total 2 items processed, remaining 2 on processor

Send 3 processed data from each processor to a CSV plugin:
CSV Output:
3.14,-1,2.71
CSV Output:
Hello world,Hi,five
CSV Output:
WARNING: Telnet access! Use ssh instead,INFO: User wil is connected

== DataStream statistics ==
Numeric Processor: total 4 items processed, remaining 1 on processor
Text Processor: total 3 items processed, remaining 0 on processor
Log Processor: total 2 items processed, remaining 0 on processor

Send another batch of data: [21, ['I love AI', 'LLMs are wonderful', 'Stay healthy'], [{'log_level': 'ERROR', 'log_message': '500 server crash'}, {'log_level': 'NOTICE', 'log_message': 'Certificate expires in 10 days'}], [32, 42, 64, 84, 128, 168], 'World hello']

== DataStream statistics ==
Numeric Processor: total 11 items processed, remaining 8 on processor
Text Processor: total 7 items processed, remaining 4 on processor
Log Processor: total 4 items processed, remaining 2 on processor

Send 5 processed data from each processor to a JSON plugin:
JSON Output:
{"item_3": "42", "item_4": "21", "item_5": "32", "item_6": "42", "item_7": "64"}
JSON Output:
{"item_3": "I love AI", "item_4": "LLMs are wonderful", "item_5": "Stay healthy", "item_6": "World hello"}
JSON Output:
{"item_2": "ERROR: 500 server crash", "item_3": "NOTICE: Certificate expires in 10 days"}

== DataStream statistics ==
Numeric Processor: total 11 items processed, remaining 3 on processor
Text Processor: total 7 items processed, remaining 0 on processor
Log Processor: total 4 items processed, remaining 0 on processor
XEOF

# ------------------ Creatures: factories, capabilities, strategies ---------- #
AUTH_PKG_CALLS="*,!eval,!exec"
AUTH_PKG_LABEL="built-ins except eval() / exec(), abc, typing, own packages"

# pkg_static: flake8, type hints, mypy, imports of the files in FILES (see pkg_files)
pkg_static() {
	flake8_line "${FILES[@]}"
	hints_line "${FILES[@]}"
	mypy_line "${FILES[@]}"
	auth_line "$AUTH_PKG_CALLS" "abc,typing,__future__,LOCAL" "$AUTH_PKG_LABEL" "${FILES[@]}"
}

# test_creature_pkg <package> <factories of the subject> <capabilities> <base package or ->
test_creature_pkg() {
	snip_line "package" "$WORK" cr_package "$1" "$2"
	stop_here && return
	snip_line "abstract classes" "$WORK" cr_abstract "$1" "$3" "$4"
	snip_line "factories" "$WORK" cr_factories "$1"
	snip_line "describe() / attack()" "$WORK" cr_methods "$1"
	snip_line "example texts" "$WORK" cr_texts "$1"
	[[ ",$3," == *,heal,* ]] && snip_line "heal capability" "$WORK" cr_heal "$1"
	[[ ",$3," == *,transform,* ]] && snip_line "transform capability" "$WORK" cr_transform "$1"
	return 0
}

# test_strategy_pkg <package> <strategies> <factory packages> <isinstance checks KO 0|1>
test_strategy_pkg() {
	snip_line "package" "$WORK" st_classes "$1" "$2" "$3"
	stop_here && return
	snip_line "is_valid()" "$WORK" st_is_valid "$1" "$2" "$3"
	snip_line "act()" "$WORK" st_act "$1" "$2" "$3"
	snip_line "invalid act()" "$WORK" st_invalid "$1" "$2" "$3"
	snip_line "capability checks" "$WORK" st_capabilities "$1" "$2" "$3" "$4"
	if [ -f "$WORK/tournament.py" ]; then
		snip_line "battle function" "$WORK" st_battle tournament "$2" "$3" "$1"
	fi
}

# submission_files <files at the root> <packages>
# Only the requested files: the root scripts and the .py files of the packages
# (hidden files such as .gitignore are not checked).
submission_files() {
	local f extra=""
	while IFS= read -r f; do
		f=${f#./}
		if [[ " $1 " == *" $f "* ]]; then continue; fi
		if [[ $f == */*.py ]] && [[ " $2 " == *" ${f%%/*} "* ]]; then continue; fi
		extra+="$f "
	done < <(cd "$DIR" && find . -mindepth 1 \( -name '.*' -o -name __pycache__ -o -name venv \) \
		-prune -o -type f -print 2>/dev/null | sort)
	if [ -z "$extra" ]; then line_ok "files" "(only the requested files)"
	else
		line_warn "files" "files that are not requested (\"submit only the files requested\"):"
		note "$extra"
	fi
	if [ -n "$(cd "$DIR" && find . -name __pycache__ -o -name .mypy_cache 2>/dev/null | head -1)" ]; then
		line_warn "caches" "__pycache__ / .mypy_cache folders found: do not push them"
	fi
}

# Example outputs of the subject (compared with a warning only)
IFS= read -r -d '' EXP_BATTLE <<'XEOF'
Testing factory
Flameling is a Fire type Creature
Flameling uses Ember!
Pyrodon is a Fire/Flying type Creature
Pyrodon uses Flamethrower!

Testing factory
Shiftling is a Normal type Creature
Shiftling attacks normally.
Morphagon is a Normal/Dragon type Creature
Morphagon attacks normally.

Testing battle
Flameling is a Fire type Creature
 vs.
Shiftling is a Normal type Creature
 fight!
Flameling uses Ember!
Shiftling attacks normally.
XEOF
IFS= read -r -d '' EXP_CAPACITOR <<'XEOF'
Testing Creature with transform capability
 base:
Shiftling is a Normal type Creature
Shiftling attacks normally.
Shiftling shifts into a sharper form!
Shiftling performs a boosted strike!
Shiftling returns to normal.
 evolved:
Morphagon is a Normal/Dragon type Creature
Morphagon attacks normally.
Morphagon morphs into a dragonic battle form!
Morphagon unleashes a devastating morph strike!
Morphagon stabilizes its form.
XEOF
IFS= read -r -d '' EXP_TOURNAMENT <<'XEOF'
Tournament 0 (basic)
 [ (Flameling+Normal), (Shiftling+Aggressive) ]
*** Tournament ***
2 opponents involved

* Battle *
Flameling is a Fire type Creature
 vs.
Shiftling is a Normal type Creature
 now fight!
Flameling uses Ember!
Shiftling shifts into a sharper form!
Shiftling performs a boosted strike!
Shiftling returns to normal.

Tournament 1 (error)
 [ (Shiftling+Aggressive), (Flameling+Aggressive) ]
*** Tournament ***
2 opponents involved

* Battle *
Shiftling is a Normal type Creature
 vs.
Flameling is a Fire type Creature
 now fight!
Shiftling shifts into a sharper form!
Shiftling performs a boosted strike!
Shiftling returns to normal.
Battle error, aborting tournament: Invalid Creature 'Flameling' for this aggressive strategy
XEOF

# ================================ Exercises ================================= #
AUTH6="built-ins except eval() / exec(), abc, typing"

# ----------------------------- ex0: data processor -------------------------- #
if wanted 0; then
	section "ex0 - data_processor"
	if ex_files ex0 data_processor.py; then
		test_data_processor . data_processor.py '*,!eval,!exec' "$AUTH6" 1
		t_prog "data_processor.py" data_processor.py "$EXP_DP"
	fi
fi

# ------------------------------ ex1: data stream ---------------------------- #
if wanted 1; then
	section "ex1 - data_stream"
	if ex_files ex1 data_stream.py; then
		test_data_stream . data_stream.py '*,!eval,!exec' "$AUTH6" 1
		t_prog "data_stream.py" data_stream.py "$EXP_DS"
	fi
fi

# ----------------------------- ex2: data pipeline --------------------------- #
if wanted 2; then
	section "ex2 - data_pipeline"
	if ex_files ex2 data_pipeline.py; then
		test_data_pipeline . data_pipeline.py '*,!eval,!exec' "$AUTH6" 0
		t_prog "data_pipeline.py" data_pipeline.py "$EXP_PIPE"
	fi
fi

# ------------------ ex3: entity factories and capabilities ------------------ #
if wanted 3; then
	section "ex3 - Entity Factories and Capabilities"
	if pkg_files ex3 ex3 battle.py capacitor.py; then
		pkg_static
		test_creature_pkg ex3 "FlameFactory,TransformCreatureFactory" "transform" "-"
		t_prog "battle.py" battle.py "$EXP_BATTLE"
		t_prog "capacitor.py" capacitor.py "$EXP_CAPACITOR"
	fi
fi

# ---------------------------- ex4: abstract strategy ------------------------ #
if wanted 4; then
	section "ex4 - Abstract Strategy"
	if pkg_files ex4 ex4 tournament.py; then
		pkg_static
		test_strategy_pkg ex4 "NormalStrategy,AggressiveStrategy" "ex3" 1
		t_prog "tournament.py" tournament.py "$EXP_TOURNAMENT"
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	submission_files "data_processor.py data_stream.py data_pipeline.py battle.py capacitor.py tournament.py" "ex3 ex4"
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
