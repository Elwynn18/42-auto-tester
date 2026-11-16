#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_09.sh - single-file tester for Python Module 9 (Cosmic Data)    #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ex2/):      #
#      bash ../test_python_09.sh               -> test everything              #
#      bash ../test_python_09.sh 0 ex2         -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - Activate your venv first: pydantic 2.x must be importable by python3.     #
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
banner "Python Module 9 tester (Cosmic Data)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 9 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_09.XXXXXX)
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
EXS=(0 1 2)
declare -A WANTED=()
for a in "$@"; do
	a=${a#ex}
	case " ${EXS[*]} " in
		*" $a "*) WANTED[$a]=1 ;;
		*) echo "Unknown exercise: '$a'. Exercises: ${EXS[*]} (or ex0 ex1 ex2)" >&2; exit 1 ;;
	esac
done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# ------------------------- Python helper (pt.py) ---------------------------- #
# call <file> <function> [args]  : imports the file and calls the function
#                                  (the exception, if any, goes to $PT_EXC)
# ast <file> <calls> <imports> <only-functions 0|1>
#                                : forbidden calls / imports, code outside functions
#                                  ("STDLIB" in <imports> = any standard module)
# hints <file>                   : parameters / returns without type hints
# pyd <file>                     : Pydantic v1 / v2 APIs used
# exec <file> <python code>      : imports the file (as "MOD") and runs a test
#                                  snippet with the helpers below; the results
#                                  go to $PT_RES, one per line:
#                                  T <label> (passed), F <label> <message> (failed),
#                                  N <label> <note>, C <label> <call> (running)
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import datetime
import enum
import importlib.util
import io
import os
import sys
import traceback

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


def cmd_call(path, func, args="()"):
    try:
        mod = load(path)
    except BaseException as e:
        report("importing %s raises %s" % (os.path.basename(path), summary(e)))
        return 5
    f = getattr(mod, func, None)
    if not callable(f):
        report("no function %s() in %s" % (func, os.path.basename(path)))
        return 4
    a = ast.literal_eval(args)
    if not isinstance(a, tuple):
        a = (a,)
    try:
        f(*a)
    except BaseException as e:
        sys.stdout.flush()
        report(summary(e))
        return 3
    return 0


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
    if "STDLIB" in mods:
        mods |= set(sys.stdlib_module_names)
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
            else:
                print("TOP %s %s" % (s.lineno, short(ast.unparse(s).split("\n")[0], 50)))
    return 0


# hints: every parameter (except self / cls) and every return needs a type hint
def cmd_hints(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    count = 0
    for n in ast.walk(tree):
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        count += 1
        a = n.args
        params = a.posonlyargs + a.args + a.kwonlyargs
        params += [x for x in (a.vararg, a.kwarg) if x is not None]
        for x in params:
            if x.annotation is None and x.arg not in ("self", "cls"):
                print("ARG %s %s %s" % (n.name, x.arg, n.lineno))
        if n.returns is None:
            print("RET %s %s" % (n.name, n.lineno))
    print("COUNT %d" % count)
    return 0


# pyd: Pydantic v1 APIs (removed or deprecated in v2) and v2 validators
V1_DECOS = ("validator", "root_validator")
V1_METHODS = ("dict", "json", "parse_obj", "parse_raw", "parse_file", "from_orm",
              "schema", "schema_json", "update_forward_refs", "construct")
V1_REMOVED_KW = ("regex", "const", "unique_items", "allow_mutation")
V1_DEPRECATED_KW = ("min_items", "max_items")


def func_name(node):
    f = node.func if isinstance(node, ast.Call) else node
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return ""


def cmd_pyd(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name == "pydantic.v1" or a.name.startswith("pydantic.v1."):
                    print("V1IMPORT %s %s" % (n.lineno, a.name))
        elif isinstance(n, ast.ImportFrom) and n.module:
            if n.module == "pydantic.v1" or n.module.startswith("pydantic.v1."):
                print("V1IMPORT %s %s" % (n.lineno, n.module))
            elif n.module == "pydantic" and any(a.name == "v1" for a in n.names):
                print("V1IMPORT %s pydantic.v1" % n.lineno)
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for d in n.decorator_list:
                name = func_name(d)
                if name in V1_DECOS:
                    print("V1DECO %s %s" % (d.lineno, name))
                elif name == "model_validator":
                    mode = "none"
                    for k in getattr(d, "keywords", []):
                        if k.arg == "mode" and isinstance(k.value, ast.Constant):
                            mode = str(k.value.value)
                    print("MV %s %s" % (d.lineno, mode))
                elif name == "field_validator":
                    print("FV %s" % d.lineno)
        elif isinstance(n, ast.ClassDef):
            for b in n.body:
                if isinstance(b, ast.ClassDef) and b.name == "Config":
                    print("CONFIG %s %s" % (b.lineno, n.name))
        elif isinstance(n, ast.Call):
            name = func_name(n)
            if name == "Field":
                print("FIELD %s" % n.lineno)
                for k in n.keywords:
                    if k.arg in V1_REMOVED_KW:
                        print("V1KW %s %s" % (n.lineno, k.arg))
                    elif k.arg in V1_DEPRECATED_KW:
                        print("OLDKW %s %s" % (n.lineno, k.arg))
            if isinstance(n.func, ast.Attribute) and name in V1_METHODS:
                print("V1METH %s %s" % (n.lineno, name))
    for s in tree.body:
        if isinstance(s, ast.Expr) and isinstance(s.value, ast.Call):
            print("TOPCALL %s %s" % (s.lineno, short(ast.unparse(s), 40)))
    return 0


# ------------- exec: test snippets (helpers usable in the snippets) ---------- #
RES = None              # results file ($PT_RES)
MOD = None              # the student's module
FNAME = ""              # its file name
DEL = object()          # field value for ok() / ko(): leave the field out
ValidationError = None  # pydantic.ValidationError (imported by cmd_exec)
BaseModel = None


class Stop(Exception):
    """Stops the snippet: the next tests would make no sense."""


MUTE = {}              # label -> label: results already shown by another snippet
#                        (failures go to the new label, or nowhere if None)


def emit(kind, label, text=""):
    if label in MUTE:
        if kind != "F" or MUTE[label] is None or "muted" in MUTE:
            return
        MUTE["muted"] = None
        label, text = MUTE[label], "not tested: %s is wrong (see above)" % label
    text = str(text).replace("\n", "\\n").replace("\t", " ")
    if len(text) > 230:
        text = text[:230] + "…"
    RES.write("%s\t%s\t%s\n" % (kind, label, text))
    RES.flush()


def rep(v):
    """Short display of a field value."""
    if isinstance(v, str) and len(v) > 12 and len(set(v)) == 1:
        return "%r * %d" % (v[0], len(v))
    if isinstance(v, str) and len(v) > 12 and len(set(v[2:])) == 1:
        return "%r + %r * %d" % (v[:2], v[2], len(v) - 2)
    if isinstance(v, enum.Enum):
        return "%s.%s" % (type(v).__name__, v.name)
    if isinstance(v, datetime.datetime):
        return repr(v).replace("datetime.datetime", "datetime")
    if isinstance(v, list):
        if len(v) > 4:
            return "[%d crew members]" % len(v)
        return "[%s]" % ", ".join(rep(x) for x in v)
    if BaseModel is not None and isinstance(v, BaseModel) and hasattr(v, "rank"):
        r = getattr(v, "rank")
        s = "%s %sy" % (getattr(r, "value", r), getattr(v, "years_experience", "?"))
        return s + ("" if getattr(v, "is_active", True) else " inactive")
    if isinstance(v, dict):
        return "{%s}" % ", ".join("%s: %s" % (k, rep(x)) for k, x in v.items())
    return short(repr(v), 40)


def what(cls, ch):
    """SpaceStation(crew_size=21, ...): the call, with the changed fields."""
    if not ch:
        return "%s(<valid values>)" % cls.__name__
    parts = ["without %s" % k if v is DEL else "%s=%s" % (k, rep(v))
             for k, v in ch.items()]
    return "%s(%s, ...)" % (cls.__name__, ", ".join(parts))


def errmsgs(e):
    try:
        return " | ".join("%s%s" % (".".join(map(str, x["loc"])) + ": " if x["loc"]
                                    else "", x["msg"]) for x in e.errors()[:2])
    except Exception:
        return short(str(e), 120)


def make(cls, base, ch):
    kw = dict(base)
    for k, v in ch.items():
        if v is DEL:
            kw.pop(k, None)
        else:
            kw[k] = v
    try:
        return cls(**kw), None
    except Stop:
        raise
    except BaseException as e:
        return None, e


def ok(label, cls, base, **ch):
    """The instance must be created (returns it, or None)."""
    emit("C", label, what(cls, ch))
    obj, e = make(cls, base, ch)
    if e is None:
        emit("T", label)
        return obj
    if isinstance(e, ValidationError):
        emit("F", label, "%s: raises ValidationError (%s); expected a valid instance"
             % (what(cls, ch), errmsgs(e)))
    else:
        emit("F", label, "%s: raises %s; expected a valid instance"
             % (what(cls, ch), summary(e)))
    return None


def ko(label, cls, base, **ch):
    """A pydantic ValidationError must be raised (returns it, or None)."""
    emit("C", label, what(cls, ch))
    obj, e = make(cls, base, ch)
    if e is None:
        emit("F", label, "%s: accepted; expected a ValidationError" % what(cls, ch))
    elif not isinstance(e, ValidationError):
        emit("F", label, "%s: raises %s; expected a pydantic ValidationError"
             % (what(cls, ch), summary(e)))
    else:
        emit("T", label)
        return e
    return None


def base_ok(label, cls, base):
    """The valid example of the subject: the other tests need it."""
    obj = ok(label, cls, base)
    if obj is None:
        emit("N", label, "the other tests of %s need this valid instance: they are not run"
             % cls.__name__)
        raise Stop
    return obj


def eq(label, desc, got, exp):
    if got == exp or isinstance(exp, enum.Enum) and got == exp.value:
        emit("T", label)
        return True
    emit("F", label, "%s: %s; expected %s" % (desc, rep(got), rep(exp)))
    return False


def words(label, desc, e, *alts):
    """The error message must contain one of the texts (case-insensitive)."""
    if e is None:
        return
    m = errmsgs(e)
    if any(a.lower() in m.lower() for a in alts):
        emit("T", label)
    else:
        emit("F", label, '%s: error "%s" does not contain "%s"'
             % (desc, short(m, 90), '" or "'.join(alts)))


def need(label, name, base):
    """The class must exist and inherit from base."""
    obj = getattr(MOD, name, None)
    if not isinstance(obj, type):
        emit("F", label, "no class %s in %s (the name must match exactly)" % (name, FNAME))
        raise Stop
    if not issubclass(obj, base):
        emit("F", label, "%s does not inherit from %s" % (name, base.__name__))
        raise Stop
    emit("T", label)
    return obj


def fields(label, cls, names):
    """The model must have these fields (the subject's names)."""
    want = names.split()
    have = list(getattr(cls, "model_fields", {}))
    miss = [n for n in want if n not in have]
    if miss:
        emit("F", label, "%s has no field %s (its fields: %s)"
             % (cls.__name__, ", ".join(miss), ", ".join(have) or "none"))
        emit("N", label, "the other tests of %s need the fields of the subject" % cls.__name__)
        raise Stop
    emit("T", label)
    extra = [n for n in have if n not in want]
    if extra:
        emit("F", "~%s fields" % cls.__name__, "%s has fields that are not in the subject: %s"
             % (cls.__name__, ", ".join(extra)))


def enum_values(label, en, values):
    got = [str(m.value) for m in en]
    if sorted(got) == sorted(values):
        emit("T", label)
    elif sorted(g.lower() for g in got) == sorted(values):
        emit("F", "~enum values", "%s values: %s; the subject shows lowercase values (%s)"
             % (en.__name__, ", ".join(got), ", ".join(values)))
    else:
        emit("F", label, "%s values: %s; expected %s"
             % (en.__name__, ", ".join(got) or "none", ", ".join(values)))


def member(label, en, value):
    """The member of the enum for this value (or name)."""
    for m in en:
        if str(m.value) == value:
            return m
    for m in en:
        if str(m.value).lower() == value or m.name.lower() == value:
            return m
    emit("F", label, "%s has no member for %r" % (en.__name__, value))
    raise Stop


def cmd_exec(path, code):
    global RES, MOD, FNAME, ValidationError, BaseModel
    RES = open(os.environ["PT_RES"], "a", encoding="utf-8")
    FNAME = os.path.basename(path)
    import pydantic
    ValidationError = pydantic.ValidationError
    BaseModel = pydantic.BaseModel
    sys.stdout = io.StringIO()      # what the student's code prints is ignored
    try:
        MOD = load(path)
    except BaseException as e:
        report("importing %s raises %s" % (FNAME, summary(e)))
        return 5
    ns = dict(globals())
    ns.update(datetime=datetime.datetime, Enum=enum.Enum)
    try:
        exec(compile(code, "<test>", "exec"), ns)
    except Stop:
        pass
    except BaseException as e:
        report(summary(e))
        return 3
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"call": cmd_call, "ast": cmd_ast, "hints": cmd_hints,
              "pyd": cmd_pyd, "exec": cmd_exec}[cmd](*sys.argv[2:]))
EOF
PT="$TMP/pt.py"

# --------------------------------- Pydantic --------------------------------- #
# The runtime tests need pydantic 2.x in the python3 on PATH (the student's venv)
PYD=0
PYD_VER=$(cd "$TMP" && python3 -c 'import pydantic; print(pydantic.VERSION)' 2>/dev/null)
if [ -z "$PYD_VER" ]; then
	PYD_MSG="pydantic not installed in this python3 ($(command -v python3)): activate your venv"
elif [ "${PYD_VER%%.*}" != 2 ]; then
	PYD_MSG="pydantic $PYD_VER found in this python3; the subject requires pydantic 2.x"
else
	PYD=1
fi
[ $PYD -eq 0 ] && printf "${Y}%s (the runtime tests are skipped).${N}\n" "$PYD_MSG"

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
tar -C "$DIR" --exclude=.git --exclude=__pycache__ --exclude=.mypy_cache \
	--exclude=venv --exclude=.venv -cf - . | tar -C "$WORK" -xf -
export PT_ROOT="$WORK" PT_EXC="$TMP/exc" PT_RES="$TMP/res"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err, EXC
# (10 s at most per test; no "python3 -I": pydantic may be a "pip --user" package)
run_py() {
	local in=$1
	shift
	rm -f "$TMP/exc"
	( cd "$TMP" && exec timeout -k 1 10 python3 "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
	EXC=""
	[ -f "$TMP/exc" ] && EXC=$(head -1 "$TMP/exc")
}

# run_script <exercise dir> <file> → RC, $TMP/out, $TMP/err
# Runs "python3 <file>" from the exercise folder, like the evaluator does
run_script() {
	( cd "$WORK/$1" && exec timeout -k 1 10 python3 "$2" ) < /dev/null > "$TMP/out" 2> "$TMP/err"
	RC=$?
}

# snippet <variable> <<'EOF' ... EOF : stores a test snippet in a variable
snippet() { IFS= read -r -d '' "$1" || true; }

# exec_line <label> <number of tests> <failures, one per line> <notes>
# One report line (labels starting with "~" are only warnings)
exec_line() {
	local l=$1 cnt=$2 f=$3 nt=$4 m i=0 fl
	if [ -z "$f" ]; then line_ok "${l#\~}" "($cnt tests)"; return; fi
	mapfile -t fl <<< "${f%$'\n'}"
	if [ "${l:0:1}" = "~" ]; then
		line_warn "${l:1}" "${fl[0]}"
		for m in "${fl[@]:1:5}"; do note "$m"; done
	else
		line_ko "$l"
		for m in "${fl[@]}"; do
			i=$((i + 1))
			if [ $i -gt 6 ]; then msg "… (${#fl[@]} errors in total)"; break; fi
			msg "$m"
		done
		[[ $f == *", ...)"* ]] && note "(\"...\" = the other fields have valid values, like in the subject's example)"
	fi
	[ -n "$nt" ] && while IFS= read -r m; do note "$m"; done <<< "${nt%$'\n'}"
}

# t_exec <label if it cannot run> <file> <python code>
# Runs a test snippet in a new python3 process (pt.py exec), then prints one
# line per label of its results, in order
t_exec() {
	local lb=$1 f=$2 code=$3 kind l t call=""
	local -a order=()
	local -A cnt=() fails=() notes=()
	: > "$TMP/res"
	run_py /dev/null exec "$f" "$code"
	while IFS=$'\t' read -r kind l t; do
		[ -z "$l" ] && continue
		[ "$kind" = C ] && { call=$t; continue; }
		[ -n "${cnt[$l]+x}" ] || { order+=("$l"); cnt[$l]=0; }
		case $kind in
			T) cnt[$l]=$((cnt[$l] + 1)) ;;
			F) cnt[$l]=$((cnt[$l] + 1)); fails[$l]+="$t"$'\n' ;;
			N) notes[$l]+="$t"$'\n' ;;
		esac
	done < "$TMP/res"
	# the warnings ("~" labels) after the other lines
	for l in "${order[@]}"; do
		[ "${l:0:1}" = "~" ] || exec_line "$l" "${cnt[$l]}" "${fails[$l]}" "${notes[$l]}"
	done
	for l in "${order[@]}"; do
		[ "${l:0:1}" = "~" ] && exec_line "$l" "${cnt[$l]}" "${fails[$l]}" "${notes[$l]}"
	done
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		line_ko "$lb"
		msg "${call:+$call: }infinite loop or too slow (more than 10 s): the next tests were not run"
	elif [ $RC -eq 5 ]; then
		line_ko "$lb"; msg "$EXC"
	elif [ $RC -eq 3 ]; then
		line_ko "$lb"; msg "the tests stopped: $EXC"
	elif [ $RC -ne 0 ]; then
		line_ko "$lb"; msg "python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"
	fi
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
# (mypy must see pydantic: it uses the python3 on PATH to find the packages)
mypy_line() {
	local out
	if [ ${#MYPY[@]} -eq 0 ]; then line_skip "mypy" "not installed"; return; fi
	if [ $PYD -eq 0 ]; then line_skip "mypy" "$PYD_MSG"; return; fi
	out=$(cd "$WORK" && "${MYPY[@]}" --python-executable "$(command -v python3)" \
		--cache-dir "$TMP/mypy_cache" --no-error-summary "$@" 2>&1 | grep -E 'error:')
	if [ -z "$out" ]; then line_ok "mypy"
	else
		line_ko "mypy"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
	fi
}

# hints_line <file>: "comprehensive type annotations"
hints_line() {
	local kind a b c m=() total=0
	while read -r kind a b c; do
		case $kind in
			ARG) m+=("line $c: parameter '$b' of $a() has no type hint") ;;
			RET) m+=("line $b: $a() has no return type hint (-> ...)") ;;
			COUNT) total=$a ;;
		esac
	done < <(python3 -I "$PT" hints "$1")
	if [ ${#m[@]} -eq 0 ]; then line_ok "type hints" "($total function(s))"
	else
		line_ko "type hints"
		for a in "${m[@]:0:5}"; do msg "$a"; done
		[ ${#m[@]} -gt 5 ] && msg "… (${#m[@]} missing in total)"
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

# static_checks <file> <need main() 0|1>
# "authorized" (pydantic + standard library only), "main()" and "main guard"
# Sets HAS_MAIN (1 if there is a main() function)
static_checks() {
	local f=$1 need_main=$2 kind a b c bad=() top=() main=0 base
	base=$(basename "$f")
	HAS_MAIN=0
	while read -r kind a b c; do
		case $kind in
			DEF) [ "$a" = main ] && HAS_MAIN=1 ;;
			MAIN) main=1 ;;
			IMPORT) bad+=("import $a (line $b)") ;;
		esac
	done < <(python3 -I "$PT" ast "$f" '*' 'STDLIB,pydantic,pydantic_core,typing_extensions' 1)
	while read -r kind a b; do
		top+=("$base:$a: $b")
	done < <(python3 -I "$PT" pyd "$f" | grep '^TOPCALL')
	if [ ${#bad[@]} -eq 0 ]; then line_ok "authorized" "(pydantic + standard library)"
	else
		line_ko "authorized"
		msg "forbidden: ${bad[*]}"
		note "authorized: pydantic 2.x and the standard library (Authorized: None)"
	fi
	if [ "$need_main" = 1 ]; then
		if [ $HAS_MAIN -eq 1 ]; then line_ok "main()"
		else line_ko "main()"; msg "$base: no main() function (\"Include a main() function that ...\")"; fi
	fi
	if [ ${#top[@]} -gt 0 ]; then
		line_warn "main guard" "code runs when the file is imported: ${top[0]}"
		note "put the call in an if __name__ == \"__main__\": block"
	elif [ $main -eq 0 ]; then
		line_warn "main guard" "no if __name__ == \"__main__\": block in $base"
		note "python3 $base should run the demonstration (not required by the subject)"
	else
		line_ok "main guard"
	fi
}

# pydantic_api <file> <need @model_validator 0|1>
# Pydantic v2 only: no v1 decorators / imports / Field arguments
pydantic_api() {
	local f=$1 need_mv=$2 kind a b bad=() old=() mv=() base nfield=0
	base=$(basename "$f")
	while read -r kind a b; do
		case $kind in
			V1IMPORT) bad+=("line $a: import of $b (Pydantic v1 API)") ;;
			V1DECO) bad+=("line $a: @$b is the deprecated Pydantic v1 decorator (use @model_validator / @field_validator)") ;;
			V1KW) bad+=("line $a: Field($b=...) does not exist in Pydantic v2") ;;
			OLDKW) old+=("line $a: Field($b=...) is deprecated in v2 (use min_length / max_length)") ;;
			V1METH) old+=("line $a: .$b() is a deprecated v1 method (v2: model_dump(), model_validate(), ...)") ;;
			CONFIG) old+=("line $a: class Config in $b is v1 style (v2: model_config = ConfigDict(...))") ;;
			MV) mv+=("$b") ;;
			FIELD) nfield=$((nfield + 1)) ;;
		esac
	done < <(python3 -I "$PT" pyd "$f")
	if [ ${#bad[@]} -eq 0 ]; then line_ok "pydantic v2 API"
	else
		line_ko "pydantic v2 API"
		for a in "${bad[@]:0:6}"; do msg "$base:$a"; done
	fi
	if [ ${#old[@]} -gt 0 ]; then
		line_warn "deprecated APIs" "$base:${old[0]}"
		for a in "${old[@]:1:4}"; do note "$base:$a"; done
	fi
	[ $nfield -eq 0 ] && line_warn "Field()" "$base never uses Field(...) (the subject's way to add constraints)"
	if [ "$need_mv" = 1 ]; then
		if [ ${#mv[@]} -eq 0 ]; then
			line_ko "model_validator"
			msg "$base: no @model_validator (\"Implement @model_validator(mode='after') with these rules\")"
		elif [[ " ${mv[*]} " == *" after "* ]]; then
			line_ok "model_validator" "(mode='after')"
		else
			line_warn "model_validator" "@model_validator without mode='after' (mode: ${mv[0]}); the subject asks for mode='after'"
		fi
	fi
}

# demo_check <exercise dir> <file> <texts of the example...>
# Runs the file, then looks for the texts of the subject's example in its output
# (a missing text is only a warning: the wording of the example is free)
demo_check() {
	local ex=$1 f=$2 s miss=() last
	shift 2
	DEMO_OUT=""
	run_script "$ex" "$f"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		line_ko "demo run"; msg "python3 $f: infinite loop or too slow (more than 10 s)"
		return
	fi
	if [ $RC -ne 0 ] || grep -q '^Traceback' "$TMP/err"; then
		last=$(grep -E '^[A-Za-z_.]*(Error|Exception)' "$TMP/err" | tail -1 | cut -c1-110)
		line_ko "demo run"
		msg "python3 $f: exits with status $RC${last:+ ($last)}"
		note "the validation errors of the demonstration must be caught (try / except ValidationError)"
		return
	fi
	if [ ! -s "$TMP/out" ]; then
		if [ "$HAS_MAIN" = 1 ]; then
			run_py /dev/null call "$WORK/$ex/$f" main
			if [ $RC -eq 0 ] && [ -s "$TMP/out" ]; then
				line_warn "demo run" "python3 $f prints nothing: main() is never called"
				note "add: if __name__ == \"__main__\": main()  (the next checks use the output of main())"
			else
				line_ko "demo run"; msg "python3 $f prints nothing, and main() ${EXC:+raises $EXC}${EXC:-prints nothing}"
				return
			fi
		else
			line_ko "demo run"; msg "python3 $f prints nothing; expected the demonstration (valid and invalid examples)"
			return
		fi
	else
		line_ok "demo run" "(python3 $f)"
	fi
	for s in "$@"; do grep -qiF -- "$s" "$TMP/out" || miss+=("\"$s\""); done
	if [ ${#miss[@]} -gt 0 ]; then
		line_warn "demo output" "differs from the subject's example: no ${miss[*]:0:3}"
		[ ${#miss[@]} -gt 3 ] && note "also missing: ${miss[*]:3}"
		note "(only an example: check by hand that your output shows the same information)"
	else
		line_ok "demo output" "(same texts as the subject's example)"
	fi
	DEMO_OUT=$(cat "$TMP/out")
	if grep -qE 'validation errors? for|\[type=|errors\.pydantic\.dev' "$TMP/out"; then
		line_warn "error display" "prints the whole ValidationError; the example shows only its message"
		note "e.g. error.errors()[0][\"msg\"]"
	fi
	if grep -qE '(ContactType|Rank)\.[A-Za-z]' "$TMP/out"; then
		line_warn "enum display" "prints the enum member ($(grep -oE '(ContactType|Rank)\.[A-Za-z_]+' "$TMP/out" | head -1)); the example shows its value"
	fi
	if grep -q 'PydanticDeprecated' "$TMP/err"; then
		line_warn "deprecations" "$(grep -m1 'PydanticDeprecated' "$TMP/err" | cut -c1-110)"
	fi
}

# static_part <exercise dir> <file> <need main() 0|1> <need @model_validator 0|1>
static_part() {
	flake8_line "$1/$2"
	mypy_line "$1/$2"
	hints_line "$WORK/$1/$2"
	static_checks "$WORK/$1/$2" "$3"
	pydantic_api "$WORK/$1/$2" "$4"
}

# ================================ Exercises ================================= #

# --------------------------- ex0: space station ----------------------------- #
snippet CODE0 <<'EOF'
S = need("SpaceStation model", "SpaceStation", BaseModel)
fields("SpaceStation model", S, "station_id name crew_size power_level oxygen_level "
       "last_maintenance is_operational notes")
B = dict(station_id="ISS001", name="International Space Station", crew_size=6,
         power_level=85.5, oxygen_level=92.3,
         last_maintenance=datetime(2024, 1, 15, 10, 30))

L = "valid station"
emit("N", L, "valid values used: " + ", ".join("%s=%s" % (k, rep(v)) for k, v in B.items()))
s = base_ok(L, S, B)
if s is not None:
    for k, v in B.items():
        eq(L, "SpaceStation(<valid values>).%s" % k, getattr(s, k, None), v)
ok(L, S, B, station_id="ABC123", name="Lunar Gateway", crew_size=4,
   power_level=100.0, oxygen_level=0.0, is_operational=False, notes="Docked")

L = "station_id (3-10)"
for v in ("ABC", "ISS0012345", "MIR01"):
    ok(L, S, B, station_id=v)
for v in ("AB", "ISS00123456", "", "X"):
    ko(L, S, B, station_id=v)

L = "name (1-50)"
for v in ("A", "N" * 50, "Tiangong"):
    ok(L, S, B, name=v)
for v in ("", "N" * 51, "N" * 200):
    ko(L, S, B, name=v)

L = "crew_size (1-20)"
for v in (1, 2, 19, 20):
    s = ok(L, S, B, crew_size=v)
    if s is not None:
        eq(L, "SpaceStation(crew_size=%d, ...).crew_size" % v, s.crew_size, v)
for v in (0, -1, 21, 25, 1000, 6.5, "six"):
    ko(L, S, B, crew_size=v)

L = "power_level (0-100)"
for v in (0.0, 0.1, 50, 99.9, 100.0):
    ok(L, S, B, power_level=v)
for v in (-0.1, -50.0, 100.1, 150.0, "full"):
    ko(L, S, B, power_level=v)

L = "oxygen_level (0-100)"
for v in (0.0, 0.1, 21, 99.9, 100.0):
    ok(L, S, B, oxygen_level=v)
for v in (-0.1, -1.0, 100.1, 200.0, "low"):
    ko(L, S, B, oxygen_level=v)

L = "last_maintenance"
for v in (datetime(2000, 1, 1), datetime(2030, 12, 31, 23, 59, 59)):
    s = ok(L, S, B, last_maintenance=v)
    if s is not None:
        eq(L, "SpaceStation(last_maintenance=%s, ...).last_maintenance" % rep(v),
           s.last_maintenance, v)
for v in ("yesterday", "2024-13-45", "", [2024, 1, 1]):
    ko(L, S, B, last_maintenance=v)

L = "is_operational"
s = ok(L, S, B)
if s is not None:
    eq(L, "SpaceStation(<valid values>).is_operational (default)", s.is_operational, True)
s = ok(L, S, B, is_operational=False)
if s is not None:
    eq(L, "SpaceStation(is_operational=False, ...).is_operational", s.is_operational, False)
ko(L, S, B, is_operational="maybe")

L = "notes (optional)"
s = ok(L, S, B, notes=DEL)
if s is None:
    emit("N", L, "Optional[str] without a default value is required in Pydantic v2: "
         "give it default=None")
else:
    eq(L, "SpaceStation(<valid values>).notes (default)", s.notes, None)
ok(L, S, B, notes=None)
for v in ("", "Routine check", "n" * 200):
    s = ok(L, S, B, notes=v)
    if s is not None:
        eq(L, "SpaceStation(notes=%s, ...).notes" % rep(v), s.notes, v)
for v in ("n" * 201, "n" * 500):
    ko(L, S, B, notes=v)

L = "required fields"
for k in B:
    ko(L, S, B, **{k: DEL})

L = "~type conversion"
s = ok(L, S, B, last_maintenance="2024-01-15T10:30:00")
if s is not None:
    eq(L, "SpaceStation(last_maintenance='2024-01-15T10:30:00', ...).last_maintenance",
       s.last_maintenance, datetime(2024, 1, 15, 10, 30))
s = ok(L, S, B, crew_size="6")
if s is not None:
    eq(L, "SpaceStation(crew_size='6', ...).crew_size", s.crew_size, 6)
EOF

if wanted 0; then
	section "ex0 - space_station"
	if ex_files ex0 space_station.py; then
		static_part ex0 space_station.py 1 0
		if [ $PYD -eq 1 ]; then
			t_exec "SpaceStation tests" "$WORK/ex0/space_station.py" "$CODE0"
			demo_check ex0 space_station.py "Space Station Data Validation" \
				"Valid station created" "ID:" "Name:" "Crew:" "Power:" "Oxygen:" "Status:" \
				"Expected validation error"
		else
			line_skip "runtime tests" "$PYD_MSG"
		fi
	fi
fi

# ---------------------------- ex1: alien contact ---------------------------- #
snippet CODE1 <<'EOF'
CT = need("ContactType enum", "ContactType", Enum)
enum_values("ContactType enum", CT, ["radio", "visual", "physical", "telepathic"])
RADIO = member("ContactType enum", CT, "radio")
VISUAL = member("ContactType enum", CT, "visual")
PHYS = member("ContactType enum", CT, "physical")
TELE = member("ContactType enum", CT, "telepathic")
A = need("AlienContact model", "AlienContact", BaseModel)
fields("AlienContact model", A, "contact_id timestamp location contact_type "
       "signal_strength duration_minutes witness_count message_received is_verified")
B = dict(contact_id="AC_2024_001", timestamp=datetime(2024, 3, 15, 22, 30),
         location="Area 51, Nevada", contact_type=RADIO, signal_strength=8.5,
         duration_minutes=45, witness_count=5,
         message_received="Greetings from Zeta Reticuli")

L = "valid contacts"
emit("N", L, "valid values used: " + ", ".join("%s=%s" % (k, rep(v)) for k, v in B.items()))
c = base_ok(L, A, B)
if c is not None:
    for k, v in B.items():
        eq(L, "AlienContact(<valid values>).%s" % k, getattr(c, k, None), v)
ok(L, A, B, contact_type=VISUAL, signal_strength=3.2, message_received=DEL,
   witness_count=1, duration_minutes=5)
ok(L, A, B, contact_type=PHYS, is_verified=True, witness_count=2)
ok(L, A, B, contact_type=TELE, witness_count=3, signal_strength=6.0, message_received=DEL)

L = "contact_id (5-15)"
for v in ("AC123", "AC_2024_001", "AC" + "0" * 13, "AC_X1"):
    ok(L, A, B, contact_id=v)
for v in ("AC12", "AC" + "0" * 14, "", "AC"):
    ko(L, A, B, contact_id=v)

L = "timestamp"
for v in (datetime(1947, 7, 8), datetime(2025, 12, 31, 23, 59)):
    c = ok(L, A, B, timestamp=v)
    if c is not None:
        eq(L, "AlienContact(timestamp=%s, ...).timestamp" % rep(v), c.timestamp, v)
for v in ("last night", "", "2024-02-30T10:00:00"):
    ko(L, A, B, timestamp=v)

L = "location (3-100)"
for v in ("Mars", "Oz!", "L" * 100, "Roswell, New Mexico"):
    ok(L, A, B, location=v)
for v in ("", "UK", "L" * 101):
    ko(L, A, B, location=v)

L = "contact_type"
for m in (RADIO, VISUAL):
    c = ok(L, A, B, contact_type=m)
    if c is not None:
        eq(L, "AlienContact(contact_type=%s, ...).contact_type" % rep(m), c.contact_type, m)
for v in ("smell", "", "radar", 42):
    ko(L, A, B, contact_type=v)

L = "signal (0.0-10.0)"
for v in (0.0, 0.1, 5, 7.0, 9.9, 10.0):
    c = ok(L, A, B, signal_strength=v)
    if c is not None:
        eq(L, "AlienContact(signal_strength=%s, ...).signal_strength" % rep(v),
           c.signal_strength, v)
for v in (-0.1, -5.0, 10.1, 11, 100.0, "strong"):
    ko(L, A, B, signal_strength=v)

L = "duration (1-1440)"
for v in (1, 2, 60, 1439, 1440):
    ok(L, A, B, duration_minutes=v)
for v in (0, -10, 1441, 2000, 4.5):
    ko(L, A, B, duration_minutes=v)

L = "witnesses (1-100)"
for v in (1, 2, 99, 100):
    ok(L, A, B, witness_count=v)
for v in (0, -1, 101, 1000):
    ko(L, A, B, witness_count=v)

L = "message (optional)"
c = ok(L, A, B, message_received=DEL, signal_strength=5.0)
if c is None:
    emit("N", L, "Optional[str] without a default value is required in Pydantic v2: "
         "give it default=None")
else:
    eq(L, "AlienContact(without message_received, signal_strength=5.0, ...)"
       ".message_received (default)", c.message_received, None)
ok(L, A, B, message_received=None, signal_strength=5.0)
for v in ("Hi", "m" * 500, "Take me to your leader"):
    ok(L, A, B, message_received=v)
for v in ("m" * 501, "m" * 1000):
    ko(L, A, B, message_received=v)

L = "is_verified"
c = ok(L, A, B)
if c is not None:
    eq(L, "AlienContact(<valid values>).is_verified (default)", c.is_verified, False)
c = ok(L, A, B, is_verified=True)
if c is not None:
    eq(L, "AlienContact(is_verified=True, ...).is_verified", c.is_verified, True)

L = "required fields"
for k in B:
    if k != "message_received":
        ko(L, A, B, **{k: DEL})

W = "~error messages"
L = "rule: AC prefix"
for v in ("AC_2024_001", "AC999", "ACXYZ", "AC-01"):
    ok(L, A, B, contact_id=v)
for v in ("XC_2024_001", "CA_2024_001", "ZZ123", "A_C2024", "X_AC_2024", "_AC_2024", " AC_2024"):
    e = ko(L, A, B, contact_id=v)
    words(W, "AlienContact(contact_id=%r, ...)" % v, e, "AC")

L = "rule: physical"
for v in (False, DEL):
    e = ko(L, A, B, contact_type=PHYS, is_verified=v)
    words(W, what(A, dict(contact_type=PHYS, is_verified=v)), e, "verif")
ok(L, A, B, contact_type=PHYS, is_verified=True)
ok(L, A, B, contact_type=PHYS, is_verified=True, witness_count=1)
ok(L, A, B, contact_type=RADIO, is_verified=False)
ok(L, A, B, contact_type=VISUAL, is_verified=False)

L = "rule: telepathic"
for n in (1, 2):
    e = ko(L, A, B, contact_type=TELE, witness_count=n)
    words(W, what(A, dict(contact_type=TELE, witness_count=n)), e,
          "Telepathic contact requires at least 3 witnesses")
for n in (3, 4, 100):
    ok(L, A, B, contact_type=TELE, witness_count=n)
for t in (RADIO, VISUAL):
    ok(L, A, B, contact_type=t, witness_count=1)
ok(L, A, B, contact_type=PHYS, witness_count=2, is_verified=True)

L = "rule: strong signal"
for v in (7.1, 7.01, 8.5, 10.0):
    for m in (DEL, None):
        e = ko(L, A, B, signal_strength=v, message_received=m)
        words(W, what(A, dict(signal_strength=v, message_received=m)), e, "message")
for v in (0.0, 3.5, 6.99, 7.0):
    ok(L, A, B, signal_strength=v, message_received=DEL)
for v in (7.1, 9.0, 10.0):
    ok(L, A, B, signal_strength=v, message_received="We come in peace")

L = "~type conversion"
c = ok(L, A, B, timestamp="2024-03-15T22:30:00")
if c is not None:
    eq(L, "AlienContact(timestamp='2024-03-15T22:30:00', ...).timestamp",
       c.timestamp, datetime(2024, 3, 15, 22, 30))
for m in (RADIO, TELE):
    c = ok(L, A, B, contact_type=str(m.value), witness_count=5)
    if c is not None:
        eq(L, "AlienContact(contact_type=%r, ...).contact_type" % m.value, c.contact_type, m)
EOF

if wanted 1; then
	section "ex1 - alien_contact"
	if ex_files ex1 alien_contact.py; then
		static_part ex1 alien_contact.py 0 1
		if [ $PYD -eq 1 ]; then
			t_exec "AlienContact tests" "$WORK/ex1/alien_contact.py" "$CODE1"
			demo_check ex1 alien_contact.py "Alien Contact Log Validation" \
				"Valid contact report" "ID:" "Type:" "Location:" "Signal:" "Duration:" \
				"Witnesses:" "Message:" "Expected validation error" \
				"Telepathic contact requires at least 3 witnesses"
		else
			line_skip "runtime tests" "$PYD_MSG"
		fi
	fi
fi

# ------------------------------ ex2: space crew ----------------------------- #
# Common part of the two ex2 snippets: the enum and crew members
snippet CODE2_COMMON <<'EOF'
RK = need("Rank enum", "Rank", Enum)
enum_values("Rank enum", RK, ["cadet", "officer", "lieutenant", "captain", "commander"])
CADET, OFFICER, LIEUT, CAPT, CMDR = (member("Rank enum", RK, r) for r in (
    "cadet", "officer", "lieutenant", "captain", "commander"))
CM = need("CrewMember model", "CrewMember", BaseModel)
fields("CrewMember model", CM, "member_id name rank age specialization "
       "years_experience is_active")
C1 = dict(member_id="CM001", name="Sarah Connor", rank=CMDR, age=45,
          specialization="Mission Command", years_experience=20)
C2 = dict(member_id="CM002", name="John Smith", rank=LIEUT, age=35,
          specialization="Navigation", years_experience=10)
C3 = dict(member_id="CM003", name="Alice Johnson", rank=OFFICER, age=28,
          specialization="Engineering", years_experience=5)
EOF

snippet CODE2_CREW <<'EOF'
B = C1
L = "valid crew members"
emit("N", L, "valid values used: " + ", ".join("%s=%s" % (k, rep(v)) for k, v in B.items()))
for d in (C1, C2, C3):
    c = base_ok(L, CM, d)
    if c is not None:
        for k, v in d.items():
            eq(L, "CrewMember(%s).%s" % (rep(d["name"]), k), getattr(c, k, None), v)
for r in (CADET, OFFICER, LIEUT, CAPT, CMDR):
    ok(L, CM, B, rank=r)

L = "member_id (3-10)"
for v in ("C01", "CM00000001", "ABCD"):
    ok(L, CM, B, member_id=v)
for v in ("", "C1", "CM000000001"):
    ko(L, CM, B, member_id=v)

L = "name (2-50)"
for v in ("Al", "N" * 50, "Jean-Luc Picard"):
    ok(L, CM, B, name=v)
for v in ("", "A", "N" * 51):
    ko(L, CM, B, name=v)

L = "rank"
for v in ("admiral", "", "general", 3):
    ko(L, CM, B, rank=v)

L = "age (18-80)"
for v in (18, 19, 79, 80):
    ok(L, CM, B, age=v, years_experience=0)
for v in (17, 0, -5, 81, 120):
    ko(L, CM, B, age=v, years_experience=0)

L = "specialization (3-30)"
for v in ("Med", "S" * 30, "Navigation"):
    ok(L, CM, B, specialization=v)
for v in ("", "AI", "S" * 31):
    ko(L, CM, B, specialization=v)

L = "years_exp (0-50)"
for v in (0, 1, 49, 50):
    ok(L, CM, B, years_experience=v, age=80)
for v in (-1, 51, 100):
    ko(L, CM, B, years_experience=v, age=80)

L = "is_active"
c = ok(L, CM, B)
if c is not None:
    eq(L, "CrewMember(<valid values>).is_active (default)", c.is_active, True)
c = ok(L, CM, B, is_active=False)
if c is not None:
    eq(L, "CrewMember(is_active=False, ...).is_active", c.is_active, False)

L = "crew required fields"
for k in B:
    ko(L, CM, B, **{k: DEL})

L = "~type conversion"
c = ok(L, CM, B, rank="captain")
if c is not None:
    eq(L, "CrewMember(rank='captain', ...).rank", c.rank, CAPT)
EOF

# (the results of the common part are only shown once)
CODE2_MUTE='MUTE.update({"Rank enum": "SpaceMission model", "CrewMember model": "SpaceMission model",
             "~enum values": None, "~CrewMember fields": None})
'
snippet CODE2_MISSION <<'EOF'
SM = need("SpaceMission model", "SpaceMission", BaseModel)
fields("SpaceMission model", SM, "mission_id mission_name destination launch_date "
       "duration_days crew mission_status budget_millions")
NUM = [0]


def mk(rank, exp=10, active=True):
    """A crew member (instance) for the mission tests."""
    NUM[0] += 1
    d = dict(member_id="CM%03d" % NUM[0], name="Crew Member %d" % NUM[0], rank=rank,
             age=50, specialization="Engineering", years_experience=exp,
             is_active=active)
    try:
        return CM(**d)
    except BaseException as e:
        emit("F", "valid missions", "CrewMember(%s) raises %s; expected a valid instance"
             % (", ".join("%s=%s" % (k, rep(v)) for k, v in d.items()), summary(e)))
        raise Stop


CREW = [mk(CMDR, 20), mk(LIEUT, 10), mk(OFFICER, 5)]
B = dict(mission_id="M2024_MARS", mission_name="Mars Colony Establishment",
         destination="Mars", launch_date=datetime(2024, 9, 1, 9, 0), duration_days=900,
         crew=CREW, budget_millions=2500.0)

L = "valid missions"
emit("N", L, "valid values used: " + ", ".join("%s=%s" % (k, rep(v)) for k, v in B.items()))
s = base_ok(L, SM, B)
if s is not None:
    for k, v in B.items():
        if k != "crew":
            eq(L, "SpaceMission(<valid values>).%s" % k, getattr(s, k, None), v)
    eq(L, "len(SpaceMission(<valid values>).crew)", len(s.crew), 3)
ok(L, SM, B, mission_id="MOON1", mission_name="Moon", destination="Moon",
   crew=[mk(CAPT, 0)], duration_days=30, budget_millions=1.0)

L = "mission_id (5-15)"
for v in ("M2024", "M" + "0" * 14, "MARS1", "M_EUROPA_7"):
    ok(L, SM, B, mission_id=v)
for v in ("M123", "M", "", "M" + "0" * 15):
    ko(L, SM, B, mission_id=v)

L = "mission_name (3-100)"
for v in ("Ax1", "N" * 100, "Europa Deep Dive"):
    ok(L, SM, B, mission_name=v)
for v in ("", "Ax", "N" * 101):
    ko(L, SM, B, mission_name=v)

L = "destination (3-50)"
for v in ("Ios", "Mars", "D" * 50):
    ok(L, SM, B, destination=v)
for v in ("", "Io", "D" * 51):
    ko(L, SM, B, destination=v)

L = "launch_date"
for v in (datetime(1969, 7, 16, 13, 32), datetime(2035, 1, 1)):
    s = ok(L, SM, B, launch_date=v)
    if s is not None:
        eq(L, "SpaceMission(launch_date=%s, ...).launch_date" % rep(v), s.launch_date, v)
for v in ("soon", "", "2024-00-10"):
    ko(L, SM, B, launch_date=v)

L = "duration (1-3650)"
for v in (1, 2, 365, 366, 3649, 3650):
    ok(L, SM, B, duration_days=v)
for v in (0, -1, 3651, 10000):
    ko(L, SM, B, duration_days=v)

L = "crew (1-12 members)"
ok(L, SM, B, crew=[mk(CMDR, 10)])
ok(L, SM, B, crew=[mk(CAPT, 10)] + [mk(OFFICER, 10) for _ in range(11)])
ok(L, SM, B, crew=[mk(CMDR, 10)] + [mk(CADET, 6) for _ in range(5)])
ko(L, SM, B, crew=[])
ko(L, SM, B, crew=[mk(CMDR, 10)] + [mk(OFFICER, 10) for _ in range(12)])
ko(L, SM, B, crew=[mk(CMDR, 10)] + [mk(OFFICER, 10) for _ in range(19)])
ko(L, SM, B, crew="Sarah Connor")
ko(L, SM, B, crew=None)

L = "nested crew"
s = ok(L, SM, B, crew=[dict(C1), dict(C2), dict(C3)])
if s is not None:
    eq(L, "SpaceMission(crew=[3 dicts], ...): crew[0] is a CrewMember",
       isinstance(s.crew[0], CM), True)
    eq(L, "SpaceMission(crew=[3 dicts], ...).crew[1].name", s.crew[1].name, "John Smith")
for bad in (dict(C2, age=17), dict(C2, name="J"), dict(C2, rank="admiral"),
            dict(C2, years_experience=60), {"name": "Nobody"}):
    e = ko(L, SM, B, crew=[dict(C1), bad])
    if e is not None:
        loc = e.errors()[0]["loc"] if e.errors() else ()
        eq(L, "SpaceMission(crew=[<valid>, %s], ...): error location starts with"
           % rep(bad), tuple(loc[:2]), ("crew", 1))

L = "budget (1-10000)"
for v in (1.0, 1.5, 2500, 9999.99, 10000.0):
    ok(L, SM, B, budget_millions=v)
for v in (0.99, 0.0, -5.0, 10000.01, 20000.0, "a lot"):
    ko(L, SM, B, budget_millions=v)

L = "mission_status"
s = ok(L, SM, B)
if s is not None:
    eq(L, "SpaceMission(<valid values>).mission_status (default)", s.mission_status, "planned")
for v in ("active", "completed", "planned"):
    s = ok(L, SM, B, mission_status=v)
    if s is not None:
        eq(L, "SpaceMission(mission_status=%r, ...).mission_status" % v, s.mission_status, v)

L = "mission req. fields"
for k in B:
    ko(L, SM, B, **{k: DEL})

W = "~error messages"
L = "rule: M prefix"
for v in ("X2024_MARS", "2024_MARS", "AM2024", "_M2024", " M2024", "N2024_MARS"):
    ko(L, SM, B, mission_id=v)
for v in ("M2024_MARS", "MARS_2024", "M_001"):
    ok(L, SM, B, mission_id=v)

L = "rule: commander"
for crew in ([mk(LIEUT), mk(OFFICER)], [mk(OFFICER)], [mk(CADET), mk(CADET)],
             [mk(LIEUT), mk(LIEUT), mk(OFFICER), mk(CADET)]):
    e = ko(L, SM, B, crew=crew)
    words(W, what(SM, dict(crew=crew)), e,
          "Mission must have at least one Commander or Captain")
for crew in ([mk(CMDR)], [mk(CAPT)], [mk(OFFICER), mk(CAPT)], [mk(CADET), mk(CMDR)],
             [mk(CMDR), mk(CAPT)]):
    ok(L, SM, B, crew=crew)

L = "rule: experience"
for days, crew in ((366, [mk(CMDR, 5), mk(OFFICER, 4)]),
                   (366, [mk(CMDR, 10), mk(OFFICER, 0), mk(CADET, 0), mk(LIEUT, 10)]),
                   (3650, [mk(CMDR, 5)]),
                   (900, [mk(CMDR, 50), mk(OFFICER, 5), mk(CADET, 0)]),
                   (365, [mk(CMDR, 0), mk(OFFICER, 0)]),
                   (365, [mk(CMDR, 4), mk(OFFICER, 1), mk(CADET, 0)]),
                   (1, [mk(CAPT, 0)])):
    ok(L, SM, B, duration_days=days, crew=crew)
for days, crew in ((366, [mk(CMDR, 4), mk(OFFICER, 4)]),
                   (366, [mk(CMDR, 5), mk(OFFICER, 4), mk(CADET, 0)]),
                   (900, [mk(CMDR, 4)]),
                   (3650, [mk(CMDR, 20), mk(OFFICER, 1), mk(OFFICER, 2), mk(CADET, 0)]),
                   (400, [mk(CMDR, 0), mk(OFFICER, 0), mk(CADET, 0)])):
    e = ko(L, SM, B, duration_days=days, crew=crew)
    words(W, what(SM, dict(duration_days=days, crew=crew)), e, "experience")

L = "rule: all active"
for crew in ([mk(CMDR), mk(OFFICER, active=False)], [mk(CMDR, active=False)],
             [mk(CMDR), mk(CAPT, active=False), mk(LIEUT)],
             [mk(CMDR, active=False), mk(CAPT, active=False)]):
    e = ko(L, SM, B, crew=crew)
    words(W, what(SM, dict(crew=crew)), e, "active")
ok(L, SM, B, crew=[mk(CMDR, active=True), mk(OFFICER, active=True)])

L = "~type conversion"
s = ok(L, SM, B, launch_date="2024-09-01T09:00:00")
if s is not None:
    eq(L, "SpaceMission(launch_date='2024-09-01T09:00:00', ...).launch_date",
       s.launch_date, datetime(2024, 9, 1, 9, 0))
EOF

if wanted 2; then
	section "ex2 - space_crew"
	if ex_files ex2 space_crew.py; then
		static_part ex2 space_crew.py 0 1
		if [ $PYD -eq 1 ]; then
			t_exec "CrewMember tests" "$WORK/ex2/space_crew.py" "$CODE2_COMMON$CODE2_CREW"
			t_exec "SpaceMission tests" "$WORK/ex2/space_crew.py" "$CODE2_MUTE$CODE2_COMMON$CODE2_MISSION"
			demo_check ex2 space_crew.py "Space Mission Crew Validation" \
				"Valid mission created" "Mission:" "ID:" "Destination:" "Duration:" \
				"Budget:" "Crew size:" "Crew members:" "Expected validation error" \
				"Mission must have at least one Commander or Captain"
			if [ -n "$DEMO_OUT" ] && ! grep -qE '^ *- .+ \(.+\) - .+' <<< "$DEMO_OUT"; then
				line_warn "crew lines" "no crew line like \"- Sarah Connor (commander) - Mission Command\""
			fi
		else
			line_skip "runtime tests" "$PYD_MSG"
		fi
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/space_station.py]=1 [ex1/alien_contact.py]=1 [ex2/space_crew.py]=1
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
	venvs=$(cd "$DIR" && find . -maxdepth 3 -name pyvenv.cfg 2>/dev/null | sed 's|^\./||; s|/pyvenv.cfg$||' | tr '\n' ' ')
	if [ -n "$venvs" ]; then
		line_warn "venv" "virtual environment in your folder: ${venvs% } (do not push it)"
	fi
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
