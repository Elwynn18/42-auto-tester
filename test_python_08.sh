#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_08.sh - single-file tester for Python Module 8 (The Matrix)     #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ex2/):      #
#      bash ../test_python_08.sh               -> test everything              #
#      bash ../test_python_08.sh 0 oracle      -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - construct.py is run outside and inside a virtual environment created      #
#    in /tmp (python3 -m venv --without-pip: no network needed).               #
#  - loading.py and oracle.py are run with the python3 of your PATH            #
#    (activate your venv first) and without any package (python3 -S).          #
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
banner "Python Module 8 tester (The Matrix)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 8 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_08.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1
MOD=08

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 22 ? 22 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }

# Exercises to test (numbers, ex0 ex1 ..., or construct loading oracle)
EXS=(0 1 2)
declare -A WANTED=()
for a in "$@"; do
	case ${a,,} in
		construct) a=0 ;; loading) a=1 ;; oracle) a=2 ;;
	esac
	a=${a#ex}
	case " ${EXS[*]} " in
		*" $a "*) WANTED[$a]=1 ;;
		*) echo "Unknown exercise: '$a'. Exercises: ${EXS[*]} (or ex0 ex1 ex2, construct loading oracle)" >&2; exit 1 ;;
	esac
done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# ------------------------- Python helper (pt.py) ---------------------------- #
# diff <expected> <got> [n]      : first difference between two outputs
#                                  (n: trailing spaces / blank lines ignored)
# ast <file> <calls> <imports>   : forbidden calls / imports, sys.path changes
#                                  (<calls>: "*" = all, "-a,b" = all but a and b)
# imports <file>                 : every import, one per line:
#                                  kind|line|top level 0/1|level|module|names
# idents <file>                  : every identifier used in the file
# defs <file>                    : functions defined at the top level
# hints <file>                   : parameters / returns without type hints
# exec <dir> <python code>       : runs test code with <dir> as current folder
#                                  and on sys.path; check() prints OK / FAIL /
#                                  WARN lines
# reqs <requirements.txt>        : declared packages
# toml <pyproject.toml>          : sections, name and declared packages
# env <.env file>                : KEY=value lines
# secrets <file>                 : string constants used as secret defaults
# externals <file>               : imported modules outside the standard library
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import contextlib
import importlib
import importlib.util
import io
import os
import re
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
            loc = "%s:%s" % (os.path.relpath(os.path.realpath(fr.filename), ROOT), fr.lineno)
            break
    m = short(str(e), 110)
    s = type(e).__name__ + (": " + m if m else "")
    return s + (" (" + loc + ")" if loc else "")


def parse(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return ast.parse(f.read(), path)


def normalized(text):
    lines = [x.rstrip() for x in text.splitlines()]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "".join(x + "\n" for x in lines)


def cmd_diff(exp_path, got_path, mode=""):
    with open(exp_path, encoding="utf-8", errors="replace", newline="") as f:
        exp = f.read()
    with open(got_path, encoding="utf-8", errors="replace", newline="") as f:
        got = f.read()
    if mode == "n":
        exp, got = normalized(exp), normalized(got)
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


def cmd_ast(path, calls, imports):
    try:
        tree = parse(path)
    except SyntaxError as e:
        print("SYNTAX %s %s" % (e.lineno, e.msg))
        return 0
    if calls.startswith("-"):
        denied = set(calls[1:].split(","))
        allowed = {"*"}
    else:
        denied = set()
        allowed = set(calls.split(","))
    mods = set(imports.split(","))
    mine = bound_names(tree)
    bnames = set(dir(builtins))

    def check(name, line):
        if name in mine or name not in bnames or is_exception(name):
            return
        if name in denied or ("*" not in allowed and name not in allowed):
            print("CALL %s %s" % (name, line))

    def bad_module(name):
        return "*" not in mods and name not in mods and name.split(".")[0] not in mods

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            check(n.func.id, n.lineno)
        if isinstance(n, ast.Import):
            for a in n.names:
                if bad_module(a.name):
                    print("IMPORT %s %s" % (a.name, n.lineno))
        if isinstance(n, ast.ImportFrom) and n.level == 0:
            if bad_module(n.module):
                print("IMPORT %s %s" % (n.module, n.lineno))
            if n.module == "sys" and any(a.name == "path" for a in n.names):
                print("SYSPATH %s" % n.lineno)
        if isinstance(n, ast.Attribute) and n.attr == "path" \
                and isinstance(n.value, ast.Name) and n.value.id == "sys":
            print("SYSPATH %s" % n.lineno)
        if isinstance(n, ast.Constant) and n.value == "PYTHONPATH":
            print("SYSPATH %s" % n.lineno)
    return 0


def walk_imports(tree):
    """(node, top level?) for every import; top level = not inside a def"""
    out = []

    def visit(node, top):
        for c in ast.iter_child_nodes(node):
            if isinstance(c, (ast.Import, ast.ImportFrom)):
                out.append((c, top))
            inner = top and not isinstance(
                c, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))
            visit(c, inner)
    visit(tree, True)
    return out


def cmd_imports(path):
    for n, top in walk_imports(parse(path)):
        if isinstance(n, ast.Import):
            for a in n.names:
                print("import|%d|%d|0|%s|%s" % (
                    n.lineno, top, a.name, "as " + a.asname if a.asname else ""))
        else:
            names = ",".join(a.name + (" as " + a.asname if a.asname else "")
                             for a in n.names)
            print("from|%d|%d|%d|%s|%s" % (
                n.lineno, top, n.level, n.module or "", names))
    return 0


def cmd_idents(path):
    seen = set()
    for n in ast.walk(parse(path)):
        if isinstance(n, ast.Name):
            seen.add(n.id)
        elif isinstance(n, ast.Attribute):
            seen.add(n.attr)
        elif isinstance(n, ast.alias):
            seen.update(n.name.split("."))
        elif isinstance(n, ast.ImportFrom) and n.module:
            seen.update(n.module.split("."))
    for s in sorted(seen):
        print(s)
    return 0


def cmd_defs(path):
    for s in parse(path).body:
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
            print(s.name)
    return 0


def cmd_hints(path):
    tree = parse(path)
    methods = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.ClassDef):
            for s in n.body:
                if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    methods.add(s)
    for f in ast.walk(tree):
        if not isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        a = f.args
        params = a.posonlyargs + a.args
        static = any(isinstance(d, ast.Name) and d.id == "staticmethod"
                     for d in f.decorator_list)
        if f in methods and not static and params:
            params = params[1:]
        params = params + a.kwonlyargs
        params += [x for x in (a.vararg, a.kwarg) if x is not None]
        miss = [p.arg for p in params if p.annotation is None]
        if miss:
            print("%s:%d: %s(): no type hint for %s" % (
                os.path.basename(path), f.lineno, f.name,
                ", ".join(miss)))
        if f.returns is None and not (f.name == "__init__" and params):
            print("%s:%d: %s(): no return type hint (-> ...)" % (
                os.path.basename(path), f.lineno, f.name))
    return 0


# ------------------------------- exec mode --------------------------------- #
def emit(kind, text=""):
    print("%s\t%s" % (kind, text.replace("\n", "\\n")), flush=True)


def ok():
    emit("OK")


def fail(m):
    emit("FAIL", m)


def warn(m):
    emit("WARN", m)


def rep(v):
    if isinstance(v, str):
        return '"%s"' % short(v, 160)
    return short(repr(v), 160)


def call(fn, *args):
    """(value, printed text, exception)"""
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            got = fn(*args)
    except BaseException as e:
        return None, buf.getvalue(), e
    return got, buf.getvalue(), None


def check(what, fn, exp, args=(), pred=None, desc=None):
    """Calls fn(*args): FAIL if it raises or if the result is not exp
    (or if pred(result) is false). Returns the result."""
    if fn is None:
        return None
    got, printed, e = call(fn, *args)
    if e is not None:
        fail("%s raises %s" % (what, summary(e)))
        return None
    good = pred(got) if pred else got == exp
    if good:
        ok()
    else:
        fail("%s returns %s; expected %s" % (what, rep(got), desc or rep(exp)))
    if printed:
        warn("%s prints %s (it should only return its result)"
             % (what, rep(printed)))
    return got


def same_text(got, exp):
    return isinstance(got, str) \
        and got.replace("\u2019", "'").replace("\u2018", "'") == exp


def check_text(what, fn, exp, args=(), desc=None):
    """check() for a string; typographic quotes are accepted with a WARN"""
    got = check(what, fn, exp, args, pred=lambda g: same_text(g, exp), desc=desc)
    if got != exp and same_text(got, exp):
        warn("%s uses typographic quotes (\u2019): the subject example uses '" % what)
    return got


def imp(name):
    """imports a module, FAIL (and None) if it raises"""
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return importlib.import_module(name)
    except BaseException as e:
        fail("import %s raises %s" % (name, summary(e)))
        return None


def get(mod, attr, label=None):
    """mod.attr, FAIL (and None) if missing"""
    if mod is None:
        return None
    if not hasattr(mod, attr):
        fail("%s has no attribute %s" % (label or mod.__name__, attr))
        return None
    return getattr(mod, attr)


def patched_alchemy(values):
    """imports the alchemy package with the 4 element functions replaced
    (values: {"create_fire": "FIRE#", ...}) BEFORE the other modules of the
    package are loaded: a function that uses them must give the new values"""
    init = os.path.join(os.getcwd(), "alchemy", "__init__.py")
    spec = importlib.util.spec_from_file_location(
        "alchemy", init, submodule_search_locations=[os.path.dirname(init)])
    pkg = importlib.util.module_from_spec(spec)
    sys.modules["alchemy"] = pkg
    for name in ("elements", "alchemy.elements"):
        with contextlib.redirect_stdout(io.StringIO()):
            m = importlib.import_module(name)
        for k, v in values.items():
            if hasattr(m, k):
                setattr(m, k, (lambda v=v: v))
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(pkg)
    return pkg


def cmd_exec(root, code):
    root = os.path.abspath(root)
    os.chdir(root)
    sys.path.insert(0, root)
    g = {"__name__": "__pt__", "ok": ok, "fail": fail, "warn": warn,
         "check": check, "check_text": check_text, "call": call, "imp": imp, "get": get, "rep": rep,
         "summary": summary, "short": short, "patched_alchemy": patched_alchemy,
         "importlib": importlib, "sys": sys, "os": os}
    try:
        exec(compile(code, "<test>", "exec"), g)
    except BaseException as e:
        fail(summary(e))
    return 0


# ----------------------------- project files ------------------------------- #
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


REQ = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*(.*)$")


def cmd_reqs(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    for i, line in enumerate(lines, 1):
        line = re.sub(r"(^|\s)#.*$", "", line).strip()
        if not line:
            continue
        if line.startswith("-"):
            print("OPT\t%d\t%s" % (i, short(line, 60)))
            continue
        m = REQ.match(line)
        if m:
            print("PKG\t%s\t%s" % (norm(m.group(1)), m.group(3).strip()))
        else:
            print("BAD\t%d\t%s" % (i, short(line, 60)))
    return 0


def cmd_toml(path):
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            print("NOTOML")
            return 0
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except Exception as e:
        print("ERR\t%s" % short(str(e), 100))
        return 0
    project = data.get("project")
    tool = data.get("tool")
    poetry = tool.get("poetry") if isinstance(tool, dict) else None
    project = project if isinstance(project, dict) else None
    poetry = poetry if isinstance(poetry, dict) else None
    if project is not None:
        print("SECTION\tproject")
    if poetry is not None:
        print("SECTION\ttool.poetry")
    if "build-system" in data:
        print("SECTION\tbuild-system")
    for sec in (project, poetry):
        if sec and isinstance(sec.get("name"), str):
            print("NAME\t%s" % sec["name"])
        if sec and isinstance(sec.get("version"), str):
            print("VERSION\t%s" % sec["version"])

    def deps_list(lst, where):
        if isinstance(lst, list):
            for d in lst:
                m = REQ.match(str(d).strip())
                if m:
                    print("DEP\t%s\t%s" % (norm(m.group(1)), where))

    def deps_dict(dct, where):
        if isinstance(dct, dict):
            for k in dct:
                if norm(k) == "python":
                    print("PYTHON\t%s" % dct[k])
                else:
                    print("DEP\t%s\t%s" % (norm(k), where))
    if project:
        deps_list(project.get("dependencies"), "[project] dependencies")
        if isinstance(project.get("requires-python"), str):
            print("PYTHON\t%s" % project["requires-python"])
        opt = project.get("optional-dependencies")
        if isinstance(opt, dict):
            for k, v in opt.items():
                deps_list(v, "[project.optional-dependencies] " + k)
    if poetry:
        deps_dict(poetry.get("dependencies"), "[tool.poetry.dependencies]")
        deps_dict(poetry.get("dev-dependencies"), "[tool.poetry.dev-dependencies]")
        groups = poetry.get("group")
        if isinstance(groups, dict):
            for k, v in groups.items():
                if isinstance(v, dict):
                    deps_dict(v.get("dependencies"),
                              "[tool.poetry.group.%s.dependencies]" % k)
    return 0


def cmd_env(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    for i, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" in line:
            k, v = line.split("=", 1)
            v = re.sub(r"\s+#.*$", "", v.strip()).strip("'\"")
            print("KEY\t%s\t%s" % (k.strip(), v))
        else:
            print("BAD\t%d\t%s" % (i, short(line, 60)))
    return 0


SECRET = re.compile(r"KEY|SECRET|TOKEN|PASSWORD|PASSWD", re.I)


def cmd_secrets(path):
    for n in ast.walk(parse(path)):
        if isinstance(n, ast.Call) and len(n.args) >= 2:
            f = n.func
            name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
            k, v = n.args[0], n.args[1]
            if name in ("getenv", "get", "setdefault") \
                    and isinstance(k, ast.Constant) and isinstance(k.value, str) \
                    and SECRET.search(k.value) and isinstance(v, ast.Constant) \
                    and isinstance(v.value, str) and v.value.strip():
                print("DEFAULT\t%d\t%s\t%s" % (n.lineno, k.value, short(v.value, 40)))
        if isinstance(n, (ast.Assign, ast.AnnAssign)):
            targets = n.targets if isinstance(n, ast.Assign) else [n.target]
            v = n.value
            for t in targets:
                if isinstance(t, ast.Name) and SECRET.search(t.id) \
                        and t.id.isupper() and isinstance(v, ast.Constant) \
                        and isinstance(v.value, str) and len(v.value) >= 6:
                    print("CONST\t%d\t%s\t%s" % (n.lineno, t.id, short(v.value, 40)))
    return 0


def cmd_externals(path):
    here = os.path.dirname(os.path.abspath(path))
    std = set(getattr(sys, "stdlib_module_names", ()))
    seen = set()
    for n, _ in walk_imports(parse(path)):
        if isinstance(n, ast.ImportFrom) and n.level:
            continue
        names = [a.name for a in n.names] if isinstance(n, ast.Import) \
            else [n.module or ""]
        for name in names:
            r = name.split(".")[0]
            if not r or r in std or r in seen or r == "__future__":
                continue
            if os.path.exists(os.path.join(here, r + ".py")) \
                    or os.path.isdir(os.path.join(here, r)):
                continue
            seen.add(r)
            print("EXT\t%s\t%d" % (r, n.lineno))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"diff": cmd_diff, "ast": cmd_ast, "imports": cmd_imports,
              "idents": cmd_idents, "defs": cmd_defs, "hints": cmd_hints, "exec": cmd_exec,
              "reqs": cmd_reqs, "toml": cmd_toml, "env": cmd_env,
              "secrets": cmd_secrets, "externals": cmd_externals}[cmd](*sys.argv[2:]))
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
# (virtual environments found in your folder are not copied)
WORK="$TMP/work"
mkdir -p "$WORK"
VENV_DIRS=()
while IFS= read -r f; do VENV_DIRS+=("$(dirname "$f")"); done \
	< <(cd "$DIR" && find . -name .git -prune -o -name pyvenv.cfg -type f -print 2>/dev/null | sort)
EXCL=()
for f in "${VENV_DIRS[@]}"; do EXCL+=("--exclude=$f"); done
tar -C "$DIR" --exclude=.git --exclude=__pycache__ --exclude=.mypy_cache "${EXCL[@]}" -cf - . \
	| tar -C "$WORK" -xf -
export PT_ROOT="$WORK" PT_EXC="$TMP/exc"

# ----------------------------- Execution tools ------------------------------ #
# run_py <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err
# (10 s at most per test)
run_py() {
	local in=$1
	shift
	rm -f "$TMP/exc"
	( cd "$TMP" && exec timeout -k 1 10 python3 -I "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
}

# run_prog <folder> <seconds> <command...> → RC, $TMP/out, $TMP/err
# Runs a program like you do (python3 file.py) from <folder>, without stdin.
# PYTHONPATH and friends are removed, so that only your files are used.
run_prog() {
	local cwd=$1 t=$2
	shift 2
	( cd "$cwd" && exec env -u PYTHONPATH -u PYTHONHOME -u PYTHONSTARTUP -u PYTHONSAFEPATH \
		timeout -k 1 "$t" "$@" ) < /dev/null > "$TMP/out" 2> "$TMP/err"
	RC=$?
}

# Last exception line of a traceback in $TMP/err (empty if no traceback)
last_error() {
	grep -q '^Traceback' "$TMP/err" || return 0
	grep -E '^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception|Exit|Interrupt)\b|^[A-Za-z_][A-Za-z0-9_.]*: ' "$TMP/err" \
		| tail -1 | cut -c1-150
}

# has_module <module>: can python3 (the one on your PATH) import it?
has_module() { ( cd "$TMP" && env -u PYTHONPATH python3 -c "import $1" ) > /dev/null 2>&1; }

# Results of one test line
# (after a timeout, the other tests of the same line are skipped)
t_begin() { T_FAILS=(); T_WARNS=(); T_N=0; T_INFO=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_warn() { T_WARNS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
# t_end <label>: OK, or KO with at most 6 messages; warnings give a "!!" line
t_end() {
	local m i=0
	if t_ok; then
		if [ ${#T_WARNS[@]} -gt 0 ]; then
			line_warn "$1" "${T_WARNS[0]}"
			for m in "${T_WARNS[@]:1:4}"; do note "$m"; done
			[ ${#T_WARNS[@]} -gt 5 ] && note "… (${#T_WARNS[@]} warnings in total)"
			[ -n "$T_INFO" ] && note "$T_INFO"
		else
			line_ok "$1" "${T_INFO:-($T_N tests)}"
		fi
		return
	fi
	line_ko "$1"
	for m in "${T_FAILS[@]}"; do
		i=$((i + 1))
		if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
		msg "$m"
	done
	for m in "${T_WARNS[@]:0:2}"; do note "also: $m"; done
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# t_exec <folder> <python test code>
# Runs the test code (pt.py exec) in a new python3 process: each check()
# prints OK / FAIL / WARN.
t_exec() {
	local l n=0
	[ $T_TIMEOUT -eq 1 ] && return 1
	run_py /dev/null exec "$1" "$2"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
		return 1
	fi
	while IFS= read -r l; do
		case $l in
			OK$'\t'*) T_N=$((T_N + 1)); n=$((n + 1)) ;;
			FAIL$'\t'*) T_N=$((T_N + 1)); n=$((n + 1)); t_fail "${l#FAIL$'\t'}" ;;
			WARN$'\t'*) t_warn "${l#WARN$'\t'}" ;;
		esac
	done < "$TMP/out"
	[ $n -eq 0 ] && t_fail "the test crashed: $(tail -1 "$TMP/err" | cut -c1-120)"
	return 0
}

# flake8_line [--flake8-option...] <files...>: one line, OK / KO / skipped
flake8_line() {
	local out opts=()
	while [[ $1 == --* ]]; do opts+=("$1"); shift; done
	if [ ${#FLAKE8[@]} -eq 0 ]; then line_skip "flake8" "not installed"; return; fi
	out=$(cd "$WORK" && "${FLAKE8[@]}" "${opts[@]}" "$@" 2>&1)
	if [ -z "$out" ]; then line_ok "flake8" "${opts:+(${opts[*]})}"
	else
		line_ko "flake8"
		head -4 <<< "$out" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 4 ] && msg "… ($(wc -l <<< "$out") errors in total)"
		grep -q '__init__.py:.*F401' <<< "$out" \
			&& note "__init__.py: list the names you expose in __all__ (usual convention)"
	fi
}

# mypy_line <files...>
# Errors about packages that are not installed (or without type stubs) are
# ignored: they depend on your environment. Errors matching $MYPY_EXPECT are
# the ones the subject asks for ("A mypy error will also raise, on purpose").
MYPY_EXPECT='^$'
mypy_line() {
	local out errs exp ign
	if [ ${#MYPY[@]} -eq 0 ]; then line_skip "mypy" "not installed"; return; fi
	# (only the errors in these files: the others are reported with their own exercise)
	out=$(cd "$WORK" && "${MYPY[@]}" --cache-dir "$TMP/mypy_cache" --no-error-summary \
		--follow-imports=silent "$@" 2>&1 | grep -E 'error:' \
		| grep -F -f <(printf '%s:\n' "$@"))
	ign=$(grep -E '\[import(-not-found|-untyped)?\]|Library stubs not installed|missing library stubs' <<< "$out")
	exp=$(grep -vE '\[import(-not-found|-untyped)?\]|Library stubs not installed|missing library stubs' <<< "$out" \
		| grep -E "$MYPY_EXPECT")
	errs=$(grep -vE '\[import(-not-found|-untyped)?\]|Library stubs not installed|missing library stubs' <<< "$out" \
		| grep -vE "$MYPY_EXPECT")
	if [ -z "$errs" ]; then
		line_ok "mypy" "$([ -n "$exp" ] && printf '(+ %d expected error(s), on purpose)' "$(grep -c . <<< "$exp")")"
	else
		line_ko "mypy"
		head -4 <<< "$errs" | cut -c1-120 | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$errs")" -gt 4 ] && msg "… ($(wc -l <<< "$errs") errors in total)"
	fi
	[ -n "$ign" ] && note "ignored: $(grep -c . <<< "$ign") error(s) about packages not installed / without type stubs"
}

# hints_line <files...>: every parameter and return value has a type hint
hints_line() {
	local out f
	out=$(for f in "$@"; do python3 -I "$PT" hints "$WORK/$f"; done)
	if [ -z "$out" ]; then line_ok "type hints" "(every parameter and return value)"
	else
		line_ko "type hints"
		head -5 <<< "$out" | while IFS= read -r l; do msg "$l"; done
		[ "$(wc -l <<< "$out")" -gt 5 ] && msg "… ($(wc -l <<< "$out") missing in total)"
	fi
}

# files_line <dir> <files...>
# → 1 if no file exists ("not done"), 0 otherwise. A KO line lists the missing
# files and the files with a syntax error; the others are in FOK[path].
declare -A FOK=()
files_line() {
	local ex=$1 f p miss="" nmiss=0 e bad=() l
	shift
	for f in "$@"; do
		p=$f; [ "$ex" != . ] && p="$ex/$f"
		if [ -f "$WORK/$p" ]; then
			e=""
			[[ $p == *.py ]] && e=$(python3 -I "$PT" ast "$WORK/$p" '*' '*' | grep -m1 '^SYNTAX')
			if [ -n "$e" ]; then
				read -r _ l e <<< "$e"
				bad+=("$p: SyntaxError line $l: $e")
			else
				FOK[$p]=1
			fi
		else
			miss+="$p "; nmiss=$((nmiss + 1))
		fi
	done
	if [ $nmiss -eq $# ]; then
		line_skip "files" "not done (${miss% } not found)"
		return 1
	fi
	if [ $nmiss -eq 0 ] && [ ${#bad[@]} -eq 0 ]; then
		line_ok "files" "($# files)"
		return 0
	fi
	line_ko "files"
	[ $nmiss -gt 0 ] && msg "missing: ${miss% }"
	for e in "${bad[@]}"; do msg "$e"; done
	return 0
}
# fok <files...>: all of them exist and parse
fok() { local f; for f in "$@"; do [ -n "${FOK[$f]}" ] || return 1; done; }
# only_ok <files...> → OKF: the ones that exist and parse
only_ok() { local f; OKF=(); for f in "$@"; do [ -n "${FOK[$f]}" ] && OKF+=("$f"); done; }

# static_line <authorized text> <calls> <imports> <files...>
# Forbidden calls / imports and sys.path changes. typing / types imports are
# only a warning when they are not in the authorized list.
static_line() {
	local txt=$1 calls=$2 imps=$3 f kind a b bad=() soft=() sp=()
	shift 3
	for f in "$@"; do
		while read -r kind a b; do
			case $kind in
				CALL) bad+=("${f##*/}: $a() (line $b)") ;;
				IMPORT)
					case $a in
						typing|typing.*|types|__future__|collections.abc) soft+=("${f##*/}: import $a (line $b)") ;;
						*) bad+=("${f##*/}: import $a (line $b)") ;;
					esac ;;
				SYSPATH) sp+=("${f##*/}: line $a") ;;
			esac
		done < <(python3 -I "$PT" ast "$WORK/$f" "$calls" "$imps")
	done
	if [ ${#bad[@]} -eq 0 ] && [ ${#sp[@]} -eq 0 ]; then
		if [ ${#soft[@]} -eq 0 ]; then line_ok "authorized" "($txt)"
		else
			line_warn "authorized" "not in the authorized list: ${soft[*]}"
			note "authorized: $txt (built-in types like list[str] need no import since Python 3.9)"
		fi
		return
	fi
	line_ko "authorized"
	[ ${#bad[@]} -gt 0 ] && msg "forbidden: ${bad[*]:0:6}"
	[ ${#sp[@]} -gt 0 ] && msg "sys.path / PYTHONPATH is modified or used (forbidden): ${sp[*]:0:4}"
	[ ${#soft[@]} -gt 0 ] && note "also not authorized: ${soft[*]}"
	note "authorized: $txt"
}

# t_script <cwd> <script> <expected stdout> <essential strings> [mode]
# Runs "python3 <script>" from <cwd> (like the subject does) and checks:
#  - mode "ok" (default): exit status 0 and no traceback;
#    mode "raise:<what>:<regex>:<detail regex>": the error must be shown
#    (raised, or caught and printed: <regex> found in stdout / stderr);
#    stdout is then compared up to the line that raises;
#  - the essential strings (one per line) must all be in stdout: KO otherwise;
#  - stdout is compared with the subject example: a difference is only a
#    warning (the wording of the example is free).
t_script() {
	local cwd=$1 s=$2 exp=$3 ess=$4 mode=${5:-ok} e d l what re det all
	T_N=$((T_N + 1))
	run_prog "$cwd" 10 python3 "$s"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		t_fail "python3 $s: infinite loop or too slow (more than 10 s)"; return 1
	fi
	e=$(last_error)
	all=$(cat "$TMP/out" "$TMP/err")
	if [ "$mode" = ok ]; then
		if [ -n "$e" ]; then t_fail "python3 $s: raises $e"; return 1; fi
		if [ $RC -ne 0 ]; then t_fail "python3 $s: exit status $RC; expected 0"; return 1; fi
	else
		IFS=: read -r _ what re det <<< "$mode"
		if ! grep -qE "$re" <<< "$all"; then
			if [ -n "$e" ]; then t_fail "python3 $s: raises $e; expected an $what"
			else t_fail "python3 $s: no error shown (exit status $RC); expected an $what (raised, or caught and printed)"; fi
			return 1
		fi
		grep -qE "$det" <<< "$all" \
			|| t_warn "python3 $s: shows an error, but not the expected $what: ${e:-$(grep -m1 -E "$re" <<< "$all" | cut -c1-100)}"
	fi
	# essential strings (typographic quotes accepted)
	sed "s/[‘’]/'/g" "$TMP/out" > "$TMP/outn"
	while IFS= read -r l; do
		[ -z "$l" ] && continue
		grep -qF -- "$l" "$TMP/outn" || { t_fail "python3 $s: \"$(cut -c1-110 <<< "$l")\" not found in the output"; return 1; }
	done <<< "$ess"
	printf '%s' "$exp" > "$TMP/exp"
	if [ "$mode" != ok ]; then
		# compare only the complete lines printed before the exception
		head -n "$(grep -c '' "$TMP/exp")" "$TMP/out" > "$TMP/got"
		[ -s "$TMP/got" ] && [ -n "$(tail -c1 "$TMP/got")" ] && printf '\n' >> "$TMP/got"
		cp "$TMP/got" "$TMP/out"
	fi
	d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out")
	[ -n "$d" ] && t_warn "python3 $s: different from the subject example: $d"
	return 0
}

# py_lint <authorized text> <calls> <imports> [--flake8-option...] <files...>
# flake8, mypy, type hints and authorized lines for the .py files that exist
py_lint() {
	local txt=$1 calls=$2 imps=$3 opts=() f py=()
	shift 3
	while [[ $1 == --* ]]; do opts+=("$1"); shift; done
	for f in "$@"; do [[ $f == *.py ]] && [ -n "${FOK[$f]}" ] && py+=("$f"); done
	[ ${#py[@]} -eq 0 ] && return 1
	flake8_line "${opts[@]}" "${py[@]}"
	mypy_line "${py[@]}"
	hints_line "${py[@]}"
	static_line "$txt" "$calls" "$imps" "${py[@]}"
}

nl=$'\n'

# ================= Environments, dependencies, configuration ================ #

# The global python3 (outside any virtual environment): the interpreter your
# venv was created from.
BASE_PY=$(cd "$TMP" && env -u PYTHONPATH python3 -c \
	'import sys; print(getattr(sys, "_base_executable", "") or sys.executable)' 2>/dev/null)
if [ -z "$BASE_PY" ] || ! [ -x "$BASE_PY" ] \
	|| ! (cd "$TMP" && env -u PYTHONPATH "$BASE_PY" -c 'import sys; sys.exit(sys.prefix != sys.base_prefix)') 2>/dev/null; then
	BASE_PY=""
fi
NO_VENV=(env -u VIRTUAL_ENV -u VIRTUAL_ENV_PROMPT -u CONDA_PREFIX -u CONDA_DEFAULT_ENV)

# mentions <regex...>: are all these (case-insensitive) in stdout + stderr?
mentions() {
	local r
	for r in "$@"; do grep -qiE -- "$r" "$TMP/out" "$TMP/err" || return 1; done
}

# gitignored <.gitignore file> <name>: would git ignore <name> next to it?
gitignored() {
	local r="$TMP/gitignore_test"
	rm -rf "$r"; mkdir -p "$r"
	cp "$1" "$r/.gitignore"
	: > "$r/$2"
	if command -v git > /dev/null 2>&1 && git -C "$r" init -q > /dev/null 2>&1; then
		git -C "$r" -c core.excludesFile=/dev/null check-ignore -q -- "$2"
	else
		# no git: the usual patterns
		case $2 in
			.env) grep -qE '^[[:space:]]*(/|\*\*/)?(\.env|\*\.env|\.env\*|\.env/?)[[:space:]]*$' "$1" ;;
			*) grep -qxF "$2" "$1" ;;
		esac
	fi
}

# ------------------------------- construct.py ------------------------------- #
# env_construct <cwd> <script> <venv name> <other venv name>
# Runs the program outside any venv (global python3), inside a venv created
# with "python3 -m venv --without-pip" and activated, and with the venv's
# python without activation.
env_construct() {
	local cwd="$WORK/$1" s=$2 vname=$3 vname2=$4 venv venv2 sp exe out_g out_v e d label
	if [ -z "$BASE_PY" ]; then
		line_skip "outside a venv" "global python3 not found"
		line_skip "inside a venv" "global python3 not found"
		return
	fi
	venv="$TMP/$vname"; venv2="$TMP/$vname2"
	if [ "$MOD" = 08 ]; then label="MATRIX STATUS"; else label="LABORATORY STATUS"; fi

	# ---- outside ----
	t_begin
	run_prog "$cwd" 10 "${NO_VENV[@]}" "$BASE_PY" "$s"
	cp "$TMP/out" "$TMP/out_global"
	e=$(last_error)
	T_N=1
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then t_fail "python3 $s (global python): infinite loop or too slow"
	elif [ -n "$e" ]; then t_fail "python3 $s (global python $BASE_PY): raises $e"
	elif [ $RC -ne 0 ]; then t_fail "python3 $s (global python): exit status $RC; expected 0"
	else
		T_N=3
		mentions 'venv' || t_fail "python3 $s (global python): no instructions to create a virtual environment (python3 -m venv ...)"
		mentions 'activate' || t_fail "python3 $s (global python): no instructions to activate a virtual environment (source .../bin/activate)"
		grep -qF -- "$BASE_PY" "$TMP/out" \
			|| t_warn "python3 $s (global python): the current Python ($BASE_PY) is not shown"
		if [ "$MOD" = 08 ]; then
			printf '%s\n' "MATRIX STATUS: You're still plugged in" "" "Current Python: $BASE_PY" \
				"Virtual Environment: None detected" "" "WARNING: You're in the global environment!" \
				"The machines can see everything you install." "" "To enter the construct, run:" \
				"python -m venv matrix_env" "source matrix_env/bin/activate # On Unix" \
				'matrix_env\Scripts\activate # On Windows' "" "Then run this program again." > "$TMP/exp"
		else
			printf '%s\n' "LABORATORY STATUS: You are working in the open" "" "Current Python: $BASE_PY" \
				"Virtual Environment: None detected" "" "WARNING: You are in the global environment!" \
				"Every reagent you install here leaks into the whole system." "" "To seal the laboratory, run:" \
				"python3 -m venv lab_env" "source lab_env/bin/activate # On Unix" \
				'lab_env\Scripts\activate # On Windows' "" "Then run this program again." > "$TMP/exp"
		fi
		d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out" n)
		[ -n "$d" ] && t_warn "different from the subject example: $d"
	fi
	T_INFO="(global python: $BASE_PY, VIRTUAL_ENV unset)"
	t_end "outside a venv"

	# ---- inside (activated) ----
	t_begin
	if ! "$BASE_PY" -m venv --without-pip "$venv" > "$TMP/venv_err" 2>&1 \
		|| ! "$BASE_PY" -m venv --without-pip "$venv2" >> "$TMP/venv_err" 2>&1; then
		line_skip "inside a venv" "cannot create a venv: $(head -1 "$TMP/venv_err" | cut -c1-80)"
		return
	fi
	exe="$venv/bin/python3"
	sp=$(cd "$TMP" && "$exe" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
	run_prog "$cwd" 10 "${NO_VENV[@]}" VIRTUAL_ENV="$venv" VIRTUAL_ENV_PROMPT="$vname" PATH="$venv/bin:$PATH" "$exe" "$s"
	cp "$TMP/out" "$TMP/out_venv"
	e=$(last_error)
	T_N=1
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then t_fail "python3 $s (in $vname): infinite loop or too slow"
	elif [ -n "$e" ]; then t_fail "python3 $s (in the activated venv $vname): raises $e"
	elif [ $RC -ne 0 ]; then t_fail "python3 $s (in the activated venv $vname): exit status $RC; expected 0"
	else
		T_N=5
		grep -qF -- "$venv" "$TMP/out" || t_fail "python3 $s (in the activated venv): the venv path $venv is not shown"
		grep -F -- "$venv" "$TMP/out" | grep -q 'site-packages' \
			|| t_fail "python3 $s (in the activated venv): the package installation path ($sp) is not shown"
		cmp -s "$TMP/out_global" "$TMP/out_venv" \
			&& t_fail "python3 $s: same output inside and outside a venv; expected a clearly different output"
		if [ "$MOD" = 08 ]; then
			printf '%s\n' "MATRIX STATUS: Welcome to the construct" "" "Current Python: $exe" \
				"Virtual Environment: $vname" "Environment Path: $venv" "" \
				"SUCCESS: You're in an isolated environment!" "Safe to install packages without affecting" \
				"the global system." "" "Package installation path:" "$sp" > "$TMP/exp"
		else
			printf '%s\n' "LABORATORY STATUS: The laboratory is sealed" "" "Current Python: $exe" \
				"Virtual Environment: $vname" "Environment Path: $venv" "" \
				"SUCCESS: You are working in an isolated environment!" "Safe to install reagents without affecting" \
				"the global system." "" "Reagent installation path:" "$sp" > "$TMP/exp"
		fi
		d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out" n)
		[ -n "$d" ] && t_warn "different from the subject example: $d"
		# another name: the name must not be written in the code
		run_prog "$cwd" 10 "${NO_VENV[@]}" VIRTUAL_ENV="$venv2" VIRTUAL_ENV_PROMPT="$vname2" PATH="$venv2/bin:$PATH" "$venv2/bin/python3" "$s"
		# (the paths are removed: the name must be shown on its own)
		grep -vF -- "$venv2" "$TMP/out" > "$TMP/out_name"
		if ! grep -qF -- "$vname2" "$TMP/out_name"; then
			if grep -qF -- "$vname" "$TMP/out_name"; then
				t_fail "python3 $s (in a venv named $vname2): shows \"$vname\"; expected \"$vname2\" (the name must come from the environment, not be written in the code)"
			else
				t_warn "python3 $s (in a venv named $vname2): the venv name \"$vname2\" is not shown (example: Virtual Environment: $vname)"
			fi
		fi
	fi
	T_INFO="(venvs created with python3 -m venv --without-pip, then activated)"
	t_end "inside a venv"

	# ---- detection: python of the venv without activate / stale VIRTUAL_ENV ----
	t_begin
	T_N=2
	run_prog "$cwd" 10 "${NO_VENV[@]}" "$exe" "$s"
	if [ -n "$(last_error)" ] || ! grep -qF -- "$venv" "$TMP/out"; then
		t_warn "$exe $s (venv python, not activated): the venv is not detected (sys.prefix != sys.base_prefix tells it; VIRTUAL_ENV is only set by activate)"
	fi
	run_prog "$cwd" 10 "${NO_VENV[@]}" VIRTUAL_ENV="$venv" "$BASE_PY" "$s"
	if ! cmp -s "$TMP/out" "$TMP/out_global"; then
		t_warn "global python with VIRTUAL_ENV=$venv set: the output is not the 'outside' one (the running python is not the venv's)"
	fi
	T_INFO="(venv python run directly, and VIRTUAL_ENV set with the global python)"
	t_end "venv detection"
}

# -------------------------------- loading.py -------------------------------- #
# dist_name <import name>: package name to install
dist_name() {
	case $1 in
		dotenv) echo python-dotenv ;; sklearn) echo scikit-learn ;; PIL) echo pillow ;;
		yaml) echo pyyaml ;; bs4) echo beautifulsoup4 ;; *) tr 'A-Z_.' 'a-z--' <<< "$1" ;;
	esac
}
# pkg_version <package>: installed version for python3 ("" if not installed)
pkg_version() {
	(cd "$TMP" && env -u PYTHONPATH python3 -c 'import sys, importlib.metadata as m
try:
    print(m.version(sys.argv[1]))
except Exception:
    pass' "$1") 2>/dev/null
}

# env_loading <ex dir> <cwd> <script> <required packages...>
env_loading() {
	local ex=$1 cwd="$WORK/$2" s=$3 kind a b c p miss ver declared=() tdeclared=() ext=() sections=""
	local name="" e mark
	shift 3
	local req=("$@")

	# ---- requirements.txt ----
	if [ -f "$WORK/$ex/requirements.txt" ]; then
		t_begin
		while IFS=$'\t' read -r kind a b; do
			case $kind in
				PKG) declared+=("$a") ;;
				BAD) t_warn "requirements.txt line $a: \"$b\" is not a requirement" ;;
			esac
		done < <(python3 -I "$PT" reqs "$WORK/$ex/requirements.txt")
		for p in "${req[@]}"; do
			T_N=$((T_N + 1))
			[[ " ${declared[*]} " == *" $p "* ]] || t_fail "requirements.txt: $p is not declared (pip install -r requirements.txt must install it)"
		done
		T_INFO="(${declared[*]:-nothing declared})"
		t_end "requirements.txt"
	fi

	# ---- pyproject.toml ----
	if [ -f "$WORK/$ex/pyproject.toml" ]; then
		t_begin
		while IFS=$'\t' read -r kind a b; do
			case $kind in
				NOTOML) T_INFO="(no tomllib in this Python: not parsed)" ;;
				ERR) t_fail "pyproject.toml is not valid TOML: $a" ;;
				SECTION) sections+="[$a] " ;;
				NAME) name=$a ;;
				DEP) tdeclared+=("$a") ;;
			esac
		done < <(python3 -I "$PT" toml "$WORK/$ex/pyproject.toml")
		if t_ok && [ -z "$T_INFO" ]; then
			T_N=1
			if [[ $sections != *project* && $sections != *tool.poetry* ]]; then
				t_fail "pyproject.toml: no [tool.poetry] nor [project] section: Poetry cannot use it"
			else
				for p in "${req[@]}"; do
					T_N=$((T_N + 1))
					[[ " ${tdeclared[*]} " == *" $p "* ]] || t_fail "pyproject.toml: $p is not declared in the dependencies"
				done
				[ -z "$name" ] && t_warn "pyproject.toml: no project name (name = \"...\" in [project] or [tool.poetry])"
				for p in "${declared[@]}"; do
					[[ " ${tdeclared[*]} " == *" $p "* ]] || t_warn "pyproject.toml: $p is in requirements.txt but not in pyproject.toml (both should declare the same dependencies)"
				done
				for p in "${tdeclared[@]}"; do
					[ -f "$WORK/$ex/requirements.txt" ] && [[ " ${declared[*]} " != *" $p "* ]] \
						&& t_warn "pyproject.toml: $p is not in requirements.txt (both should declare the same dependencies)"
				done
				T_INFO="(${sections% }; dependencies: ${tdeclared[*]:-none})"
			fi
		fi
		if [[ $T_INFO == *tomllib* ]]; then
			# Python 3.10 without tomllib: the names must at least be in the file
			for p in "${req[@]}"; do
				T_N=$((T_N + 1))
				grep -qiw -- "$p" "$WORK/$ex/pyproject.toml" || t_fail "pyproject.toml: $p is not declared"
			done
		fi
		t_end "pyproject.toml"
		if command -v poetry > /dev/null 2>&1; then
			(cd "$WORK/$ex" && timeout 30 poetry check --no-interaction) > "$TMP/out" 2>&1
			if [ $? -eq 0 ]; then line_ok "poetry check"
			else line_warn "poetry check" "$(grep -m1 -iE 'error|invalid|must' "$TMP/out" | cut -c1-100)"; fi
		fi
	fi

	# ---- what loading.py imports is declared ----
	fok "$ex/loading.py" || return
	t_begin
	while IFS=$'\t' read -r kind a b; do
		[ "$kind" = EXT ] || continue
		p=$(dist_name "$a")
		ext+=("$a")
		T_N=$((T_N + 1))
		[ -f "$WORK/$ex/requirements.txt" ] && [[ " ${declared[*]} " != *" $p "* ]] \
			&& t_fail "loading.py imports $a (line $b), but $p is not in requirements.txt"
		[ -f "$WORK/$ex/pyproject.toml" ] && [ ${#tdeclared[@]} -gt 0 ] && [[ " ${tdeclared[*]} " != *" $p "* ]] \
			&& t_fail "loading.py imports $a (line $b), but $p is not in pyproject.toml"
	done < <(python3 -I "$PT" externals "$WORK/$ex/loading.py")
	if [ "$MOD" = 08 ]; then
		# pandas, numpy and matplotlib must be used (imported, or by name with importlib)
		for p in pandas numpy matplotlib; do
			T_N=$((T_N + 1))
			grep -qw "$p" "$WORK/$ex/loading.py" || t_fail "loading.py: $p is not used (the subject asks for pandas, numpy and matplotlib)"
		done
		grep -qE 'random|default_rng|linspace|arange|normal\(' "$WORK/$ex/loading.py" \
			|| t_warn "loading.py: no numpy data generation found (np.random...): numpy must be the source of the dataset"
	fi
	T_INFO="(external imports: ${ext[*]:-none found})"
	t_end "dependencies used"

	# ---- without the packages: python3 -S (no site-packages at all) ----
	t_begin
	run_prog "$cwd" 20 python3 -S "$s"
	e=$(last_error)
	T_N=1
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then t_fail "python3 -S $s: infinite loop or too slow"
	elif [ -n "$e" ]; then t_fail "python3 -S $s (no package installed): raises $e; expected a clear message, not a traceback"
	else
		for p in "${req[@]}"; do
			T_N=$((T_N + 1))
			mentions "$p" || t_fail "python3 -S $s (no package installed): $p is not reported as missing"
		done
		T_N=$((T_N + 2))
		mentions 'pip3? install' || t_fail "python3 -S $s (no package installed): no pip install command (pip install -r requirements.txt)"
		mentions 'poetry' || t_fail "python3 -S $s (no package installed): no Poetry install command (poetry install)"
		[ ! -s "$TMP/out" ] && [ -s "$TMP/err" ] && t_warn "the messages are printed on stderr only"
	fi
	T_INFO="(python3 -S: site-packages disabled, exit status $RC)"
	t_ok || T_INFO=""
	t_end "missing packages"

	# ---- with the packages ----
	miss=""
	for p in "${req[@]}"; do has_module "$p" || miss+="$p "; done
	if [ -n "$miss" ]; then
		line_skip "with packages" "${miss% } not installed in this python3: activate your venv (pip install -r $ex/requirements.txt)"
		return
	fi
	t_begin
	mark="$TMP/mark"; : > "$mark"
	run_prog "$cwd" 60 env MPLBACKEND=Agg python3 "$s"
	e=$(last_error)
	T_N=1
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then t_fail "python3 $s: infinite loop or too slow (more than 60 s)"
	elif [ -n "$e" ]; then t_fail "python3 $s (packages installed): raises $e"
	elif [ $RC -ne 0 ]; then t_fail "python3 $s (packages installed): exit status $RC; expected 0"
	else
		local vlist=("${req[@]}")
		for p in "${ext[@]}"; do
			p=$(dist_name "$p")
			[[ " ${vlist[*]} " == *" $p "* ]] || vlist+=("$p")
		done
		for p in "${vlist[@]}"; do
			ver=$(pkg_version "$p")
			[ -z "$ver" ] && continue
			T_N=$((T_N + 1))
			mentions "$(sed 's/[.+]/\\&/g' <<< "$ver")" || t_fail "python3 $s: the installed version of $p ($ver) is not shown"
		done
		T_N=$((T_N + 1))
		mentions 'pip' 'poetry' || t_fail "python3 $s: the output does not show the difference between pip and Poetry (neither 'pip' nor 'Poetry' is mentioned)"
		if [ "$MOD" = 08 ]; then
			p=$(find "$WORK" -newer "$mark" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.svg' -o -name '*.pdf' \) 2>/dev/null | head -1)
			if [ -z "$p" ]; then t_warn "python3 $s: no image file created (the subject example saves matrix_analysis.png)"
			else T_INFO="(visualization saved: ${p#$WORK/})"; fi
		fi
	fi
	[ -z "$T_INFO" ] && T_INFO="(versions shown: $(for p in "${req[@]}"; do printf '%s %s, ' "$p" "$(pkg_version "$p")"; done | sed 's/, $//'))"
	t_end "with packages"
}

# --------------------------------- oracle.py -------------------------------- #
ORA_VARS=(-u MATRIX_MODE -u DATABASE_URL -u API_KEY -u LOG_LEVEL -u ZION_ENDPOINT)
DEV_ENV="MATRIX_MODE=development
DATABASE_URL=sqlite:///tester_local.db
API_KEY=tester-api-key-7f3a9c
LOG_LEVEL=DEBUG
ZION_ENDPOINT=http://localhost:4242/zion"
# oracle_run [VAR=value...]: runs the oracle without the 5 variables (+ these)
# ($TMP/outall: stdout + stderr, used to compare two runs)
oracle_run() {
	run_prog "$ORA_CWD" 10 env "${ORA_VARS[@]}" "$@" python3 "$ORA_S"
	cat "$TMP/out" "$TMP/err" > "$TMP/outall"
}
# more_prod <reference output>: "production" shown, and stdout differs from
# the reference run (where the mode is not production)
more_prod() { mentions production && ! cmp -s "$TMP/outall" "$1"; }
# oracle_ok <what>: no timeout / traceback (t_fail otherwise)
oracle_ok() {
	local e
	T_N=$((T_N + 1))
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then t_fail "$1: infinite loop or too slow"; return 1; fi
	e=$(last_error)
	if [ -n "$e" ]; then t_fail "$1: raises $e"; return 1; fi
	if [ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ]; then t_fail "$1: prints nothing"; return 1; fi
	return 0
}

# env_oracle <ex dir> <cwd> <script>
env_oracle() {
	local ex=$1 s=$3 kind a b c keys=() k e f
	ORA_CWD="$WORK/$2"; ORA_S=$s
	local envf="$WORK/$ex/.env" what="python3 $s"

	# ---- requirements.txt ----
	if fok "$ex/requirements.txt"; then
		t_begin
		T_N=1
		f=$(python3 -I "$PT" reqs "$WORK/$ex/requirements.txt" | cut -f2)
		if grep -qx 'dotenv' <<< "$f" && ! grep -qx 'python-dotenv' <<< "$f"; then
			t_fail "requirements.txt: dotenv is declared, but it is another package on PyPI: 'import dotenv' comes from python-dotenv"
		elif ! grep -qx 'python-dotenv' <<< "$f"; then
			t_fail "requirements.txt: python-dotenv is not declared"
		fi
		T_INFO="($(tr '\n' ' ' <<< "$f" | sed 's/ $//'))"
		t_end "requirements.txt"
	fi

	# ---- .env.example ----
	if [ -f "$WORK/$ex/.env.example" ]; then
		t_begin
		while IFS=$'\t' read -r kind a b; do
			case $kind in
				KEY) keys+=("$a") ;;
				BAD) t_warn ".env.example line $a: \"$b\" is not a KEY=value line" ;;
			esac
		done < <(python3 -I "$PT" env "$WORK/$ex/.env.example")
		for k in MATRIX_MODE DATABASE_URL API_KEY LOG_LEVEL ZION_ENDPOINT; do
			T_N=$((T_N + 1))
			[[ " ${keys[*]} " == *" $k "* ]] || t_warn ".env.example: no $k= line (the template should list every variable)"
		done
		t_end ".env.example"
	fi

	# ---- .gitignore ----
	if [ -f "$WORK/$ex/.gitignore" ]; then
		t_begin
		T_N=2
		gitignored "$WORK/$ex/.gitignore" .env || t_fail ".gitignore: .env is not ignored (add a line .env)"
		gitignored "$WORK/$ex/.gitignore" .env.example \
			&& t_warn ".gitignore: .env.example is ignored too: the template must be committed"
		t_end ".gitignore"
	fi

	# ---- source: python-dotenv, no secret in the code ----
	fok "$ex/oracle.py" || return
	t_begin
	T_N=2
	python3 -I "$PT" externals "$WORK/$ex/oracle.py" | cut -f2 | grep -qx dotenv \
		|| t_fail "oracle.py: python-dotenv is not used (the subject asks for load_dotenv, not a custom parser)"
	while IFS=$'\t' read -r kind a b c; do
		case $kind in
			DEFAULT) t_fail "oracle.py line $a: default value \"$c\" for $b written in the code (hardcoded secret)" ;;
			CONST) t_fail "oracle.py line $a: $b = \"$c\" (hardcoded secret)" ;;
		esac
	done < <(python3 -I "$PT" secrets "$WORK/$ex/oracle.py")
	t_end "no hardcoded secret"

	if ! has_module dotenv; then
		line_skip "runtime" "python-dotenv not installed in this python3: activate your venv (pip install -r $ex/requirements.txt)"
		t_begin
		find "$WORK" -name .env -type f -delete
		oracle_run MATRIX_MODE=production
		oracle_ok "$what (python-dotenv not installed)" || { T_WARNS=("${T_FAILS[@]}"); T_FAILS=(); }
		t_end "without dotenv"
		return
	fi

	# your own .env files are not used: the tester writes its own
	find "$WORK" -name .env -type f -delete

	# ---- no configuration at all ----
	t_begin
	oracle_run
	cp "$TMP/outall" "$TMP/out_none"
	if oracle_ok "$what (no .env, no variable)"; then
		mentions 'missing|not set|warning|default|not found|not configured|undefined|unset|no \.env|none' \
			|| t_warn "$what (no .env, no variable): no warning about the missing configuration"
	fi
	oracle_run MATRIX_MODE=production
	if oracle_ok "MATRIX_MODE=production $what (no other variable)"; then
		T_N=$((T_N + 1))
		more_prod "$TMP/out_none" || t_fail "MATRIX_MODE=production $what (no other variable): \"production\" not shown (the mode must be visible)"
	fi
	: > "$envf"
	oracle_run
	oracle_ok "$what (empty .env)"
	rm -f "$envf"
	t_end "missing config"

	# ---- the .env file ----
	t_begin
	printf '%s\n' "$DEV_ENV" > "$envf"
	oracle_run
	cp "$TMP/outall" "$TMP/out_dev"
	if oracle_ok "$what (with $ex/.env, MATRIX_MODE=development)"; then
		T_N=$((T_N + 2))
		if cmp -s "$TMP/out_none" "$TMP/out_dev"; then
			if [ "$MOD" = 05bis ]; then
				run_prog "$WORK/$ex" 10 env "${ORA_VARS[@]}" python3 oracle.py
				cat "$TMP/out" "$TMP/err" > "$TMP/outall"
				if ! cmp -s "$TMP/out_none" "$TMP/outall"; then
					t_fail "$what: $ex/.env is not loaded when run from the root (only from $ex/): use load_dotenv() without a path, or a path built from __file__"
				else
					t_fail "$what: same output with and without $ex/.env (the .env file is not loaded)"
				fi
			else
				t_fail "$what: same output with and without .env (the .env file is not loaded)"
			fi
		else
			mentions 'development' || t_fail "$what (with .env, MATRIX_MODE=development): \"development\" not shown"
			mentions 'DEBUG' || t_warn "$what (with .env, LOG_LEVEL=DEBUG): the log level \"DEBUG\" is not shown"
		fi
		mentions 'tester-api-key-7f3a9c' && t_warn "$what: the API key is printed in clear (\"tester-api-key-7f3a9c\")"
	fi
	T_INFO="(.env: MATRIX_MODE=development, LOG_LEVEL=DEBUG, API_KEY=...)"
	t_ok || T_INFO=""
	t_end ".env file"

	# ---- the environment wins over the .env file ----
	t_begin
	oracle_run MATRIX_MODE=production API_KEY=secret123
	if oracle_ok "MATRIX_MODE=production API_KEY=secret123 $what (with the development .env)"; then
		T_N=$((T_N + 1))
		more_prod "$TMP/out_dev" \
			|| t_fail "MATRIX_MODE=production API_KEY=secret123 $what: the production mode is not shown (the environment must win over .env: load_dotenv() without override=True)"
		mentions 'secret123' && t_warn "MATRIX_MODE=production API_KEY=secret123 $what: the API key is printed in clear"
	fi
	rm -f "$envf"
	oracle_run MATRIX_MODE=production DATABASE_URL=postgresql://db.zion/prod API_KEY=prod-key-42 \
		LOG_LEVEL=WARNING ZION_ENDPOINT=https://zion.example/api
	cp "$TMP/outall" "$TMP/out_prod"
	if oracle_ok "$what (no .env, the 5 variables set, production)"; then
		oracle_run MATRIX_MODE=development DATABASE_URL=postgresql://db.zion/prod API_KEY=prod-key-42 \
			LOG_LEVEL=WARNING ZION_ENDPOINT=https://zion.example/api
		T_N=$((T_N + 1))
		cmp -s "$TMP/outall" "$TMP/out_prod" \
			&& t_fail "$what: same output with MATRIX_MODE=development and MATRIX_MODE=production (the difference must be visible)"
	fi
	oracle_run MATRIX_MODE=banana
	oracle_ok "MATRIX_MODE=banana $what" || { t_warn "${T_FAILS[-1]} (invalid mode)"; unset 'T_FAILS[-1]'; }
	t_end "environment"

	# ---- python-dotenv not installed (python3 -S) ----
	t_begin
	run_prog "$ORA_CWD" 10 env "${ORA_VARS[@]}" MATRIX_MODE=production python3 -S "$s"
	oracle_ok "python3 -S $s (python-dotenv not importable)" || { T_WARNS=("${T_FAILS[@]}"); T_FAILS=(); }
	T_INFO="(python3 -S: no site-packages, so no dotenv)"
	t_end "without dotenv"
}


# git: is the module folder in a git repository? tracked <path>: is it committed?
IN_GIT=0
command -v git > /dev/null 2>&1 && git -C "$DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1 && IN_GIT=1
tracked() { [ $IN_GIT -eq 1 ] && [ -n "$(git -C "$DIR" ls-files -- "$1" 2>/dev/null | head -1)" ]; }

# ------------------------------- Submission --------------------------------- #
# submission <KO for venv/.env 0|1> <expected files...>
submission() {
	local strict=$1 f extra="" bad=() v
	shift
	declare -A EXPECTED=()
	for f in "$@"; do EXPECTED[$f]=1; done
	section "Submission"
	while IFS= read -r f; do
		f=${f#./}
		[ -n "${EXPECTED[$f]}" ] || extra+="$f "
	done < <(cd "$DIR" && find . \( -name .git -o -name __pycache__ -o -name .mypy_cache -o -name .env \) -prune -o -type f -print 2>/dev/null \
		| grep -vE '^\./(\.gitignore|.*/poetry\.lock)$' | while IFS= read -r f; do
			for v in "${VENV_DIRS[@]}"; do [[ $f == "$v"/* ]] && continue 2; done
			printf '%s\n' "$f"
		done | sort)
	if [ -z "$extra" ]; then line_ok "files" "(only the requested files)"
	else
		line_warn "files" "files that are not in the subject's tree:"
		note "$(cut -c1-300 <<< "${extra% }")"
	fi
	# virtual environments and .env files
	for v in "${VENV_DIRS[@]}"; do
		if tracked "$v"; then bad+=("${v#./}/ (virtual environment, committed in git)")
		elif [ $IN_GIT -eq 1 ] && git -C "$DIR" check-ignore -q "$v" 2>/dev/null; then :
		else bad+=("${v#./}/ (virtual environment: do not push it, add it to .gitignore)"); fi
	done
	while IFS= read -r f; do
		f=${f#./}
		if tracked "$f"; then bad+=("$f (secrets, committed in git)")
		elif [ $IN_GIT -eq 1 ] && git -C "$DIR" check-ignore -q "$f" 2>/dev/null; then :
		else bad+=("$f (secrets: do not push it)"); fi
	done < <(cd "$DIR" && find . -name .git -prune -o -name .env -type f -print 2>/dev/null)
	if [ ${#bad[@]} -eq 0 ]; then
		line_ok "venv / .env" "(none submitted)"
	elif [ "$strict" = 1 ] && [[ "${bad[*]}" == *"committed in git"* ]]; then
		line_ko "venv / .env"
		for f in "${bad[@]}"; do msg "$f"; done
	else
		line_warn "venv / .env" "${bad[0]}"
		for f in "${bad[@]:1}"; do note "$f"; done
	fi
	if [ -n "$(cd "$DIR" && find . -name __pycache__ -o -name .mypy_cache 2>/dev/null | head -1)" ]; then
		line_warn "caches" "__pycache__ / .mypy_cache folders found: do not push them"
	fi
}

# ================================ Exercises ================================= #

# ------------------------------ ex0: construct ------------------------------ #
if wanted 0; then
	section "ex0 - construct"
	if files_line ex0 construct.py; then
		py_lint "sys, os, site, built-in functions" '*' sys,os,site ex0/construct.py
		fok ex0/construct.py && env_construct ex0 construct.py matrix_env neo_env
	fi
fi

# ------------------------------- ex1: loading ------------------------------- #
if wanted 1; then
	section "ex1 - loading"
	if files_line ex1 loading.py requirements.txt pyproject.toml; then
		# "flake8 and mypy errors are allowed for this exercise, only for import errors"
		py_lint "pandas, requests, matplotlib, numpy, sys, importlib, built-in functions" '*' \
			pandas,requests,matplotlib,numpy,sys,importlib --extend-ignore=E402,F401,F811 ex1/loading.py
		env_loading ex1 ex1 loading.py pandas numpy matplotlib
	fi
fi

# -------------------------------- ex2: oracle ------------------------------- #
if wanted 2; then
	section "ex2 - oracle"
	if files_line ex2 oracle.py requirements.txt .env.example .gitignore; then
		py_lint "os, sys, python-dotenv, file operations, built-in functions" '*' os,sys,dotenv ex2/oracle.py
		env_oracle ex2 ex2 oracle.py
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	submission 1 ex0/construct.py ex1/loading.py ex1/requirements.txt ex1/pyproject.toml \
		ex2/oracle.py ex2/requirements.txt ex2/.env.example ex2/.gitignore
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
