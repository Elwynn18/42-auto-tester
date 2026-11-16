#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_06.sh - single-file tester for Python Module 6 (The Codex)      #
#                                                                              #
#  Usage (from your module folder, the one that contains alchemy/):            #
#      bash ../test_python_06.sh               -> test everything              #
#      bash ../test_python_06.sh 2 kaboom      -> only these parts             #
#      (parts: 1 alembic, 2 distillation, 3 transmutation, 4 kaboom)           #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - Every program is run from your folder (python3 ft_alembic_0.py),          #
#    and imports are checked statically (import / from, absolute /             #
#    relative) and at run time (exposed names, circular imports).              #
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
banner "Python Module 6 tester (The Codex)" "$DIR"
if [ ! -d "$DIR/alchemy" ] && ! compgen -G "$DIR/ft_*.py" > /dev/null; then
	echo "Error: no alchemy/ folder and no ft_*.py file here. Run this script from your Python Module 6 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_06.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1
MOD=06

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 22 ? 22 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }

# Parts to test: 1 = The Alembic, 2 = Distillation, 3 = The Great
# Transmutation, 4 = Avoid the Explosion (or their names)
declare -A WANTED=()
for a in "$@"; do
	a=${a,,}; a=${a#ex}; a=${a#part}
	case $a in
		1|alembic) WANTED[1]=1 ;;
		2|distillation) WANTED[2]=1 ;;
		3|transmutation) WANTED[3]=1 ;;
		4|kaboom|grimoire|explosion) WANTED[4]=1 ;;
		*) echo "Unknown part: '$a'. Parts: 1 2 3 4 (or alembic distillation transmutation kaboom)" >&2; exit 1 ;;
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

# ========================= The alchemy package tests ======================== #
# Everything runs from the root of the copy, like "python3 ft_alembic_0.py".

FIRE="Fire element created"; WATER="Water element created"
EARTH="Earth element created"; AIR="Air element created"
HEAL="Healing potion brewed with '$EARTH' and '$AIR'"
STRENGTH="Strength potion brewed with '$FIRE' and '$WATER'"
GOLD="Recipe transmuting Lead to Gold: brew '$AIR' and '$STRENGTH' mixed with '$FIRE'"
SPELL="Spell recorded: Fantasy (Earth, wind and fire - VALID)"
ALCH_AUTH="built-in functions except eval() / exec(); only imports of your own modules"
ALCH_IMPORTS="elements,alchemy"

# Python constants for the test code
PY_CONST='FIRE = "Fire element created"
WATER = "Water element created"
EARTH = "Earth element created"
AIR = "Air element created"
HEAL = "Healing potion brewed with '"'%s' and '%s'"'" % (EARTH, AIR)
STRENGTH = "Strength potion brewed with '"'%s' and '%s'"'" % (FIRE, WATER)
GOLD = ("Recipe transmuting Lead to Gold: brew '"'%s' and '%s' mixed with '%s'"'"
        % (AIR, STRENGTH, FIRE))
FAKE = {"create_fire": "FIRE#", "create_water": "WATER#",
        "create_earth": "EARTH#", "create_air": "AIR#"}'
# code <<'EOF' ... EOF → CODE = the constants + the test code
code() { CODE="$PY_CONST$nl$(cat)"; }

# imports_of <file> → IMPS: "kind|line|top|level|module|names" (pt.py imports)
imports_of() { mapfile -t IMPS < <(python3 -I "$PT" imports "$WORK/$1"); }
# has_import <module>: "import <module> [as x]"
has_import() {
	local x k l t v m n
	for x in "${IMPS[@]}"; do
		IFS='|' read -r k l t v m n <<< "$x"
		[ "$k" = import ] && [ "$m" = "$1" ] && return 0
	done
	return 1
}
# has_from <module> [name]: "from <module> import ..." (absolute, with <name>)
has_from() {
	local x k l t v m n
	for x in "${IMPS[@]}"; do
		IFS='|' read -r k l t v m n <<< "$x"
		[ "$k" = from ] && [ "$v" = 0 ] && [ "$m" = "$1" ] || continue
		[ -z "$2" ] && return 0
		[[ ",$n," =~ ,$2(\ as\ [A-Za-z0-9_]+)?, ]] && return 0
	done
	return 1
}
# imports_module <module name> → where the imports of IMPS reach a module
# named <module name> (alchemy.grimoire.X, .X, from . import X):
# prints "top <line>" or "late <line>" (late = inside a function)
imports_module() {
	local x k l t v m n
	for x in "${IMPS[@]}"; do
		IFS='|' read -r k l t v m n <<< "$x"
		if [ "$m" = "$1" ] || [[ $m == *."$1" ]] || [[ ",$n," =~ ,$1(\ as\ [A-Za-z0-9_]+)?, ]]; then
			if [ "$t" = 1 ]; then echo "top $l"; else echo "late $l"; fi
		fi
	done
}
# style <file> <description> import|from <module> [name] → one test
style() {
	local f=$1 desc=$2 kind=$3 mod=$4 name=$5
	fok "$f" || return 1
	imports_of "$f"
	T_N=$((T_N + 1))
	if [ "$kind" = import ]; then
		has_import "$mod" && return 0
		t_fail "$f: no \"import $mod\" ($desc)"
	else
		has_from "$mod" "$name" && return 0
		t_fail "$f: no \"from $mod import ${name:-...}\" ($desc)"
	fi
	return 1
}
# script_line <script> <expected stdout> <essential strings> [mode]
script_line() {
	fok "$1" || return
	t_begin
	t_script "$WORK" "$1" "$2" "$3" "$4"
	if [ -n "$4" ]; then T_INFO="(python3 $1: the expected error is shown)"
	else T_INFO="(python3 $1: exit status 0, output as in the subject)"; fi
	t_ok && [ ${#T_WARNS[@]} -eq 0 ] || T_INFO=""
	t_end "$1"
}

# alch_lint <files...>: flake8, mypy, type hints, authorized (own modules only)
alch_lint() { py_lint "$ALCH_AUTH" "-eval,exec" "$ALCH_IMPORTS" "$@"; }

# ---------------------------- The Alembic ----------------------------------- #
alch_alembic() {
	local scripts files hidden x k l t v m n others
	if [ "$MOD" = 06 ]; then
		scripts=(ft_alembic_0.py ft_alembic_1.py ft_alembic_2.py ft_alembic_3.py ft_alembic_4.py ft_alembic_5.py)
		hidden=ft_alembic_4.py
	else
		scripts=(ft_alembic_0.py ft_alembic_1.py)
		hidden=ft_alembic_1.py
	fi
	files=(elements.py alchemy/__init__.py alchemy/elements.py "${scripts[@]}")
	files_line . "${files[@]}" || return
	MYPY_EXPECT="${hidden//./\\.}:.*create_earth"
	alch_lint "${files[@]}" || return
	MYPY_EXPECT='^$'

	# the 4 element functions
	t_begin
	if fok elements.py; then
		code <<'EOF'
e = imp("elements")
for name, val in (("create_fire", FIRE), ("create_water", WATER)):
    f = get(e, name, "elements.py")
    check_text("elements.%s()" % name, f, val)
    check_text("elements.%s() (2nd call)" % name, f, val)
EOF
		t_exec "$WORK" "$CODE"
	fi
	if fok alchemy/__init__.py alchemy/elements.py; then
		code <<'EOF'
e = imp("alchemy.elements")
for name, val in (("create_earth", EARTH), ("create_air", AIR)):
    f = get(e, name, "alchemy/elements.py")
    check_text("alchemy.elements.%s()" % name, f, val)
    check_text("alchemy.elements.%s() (2nd call)" % name, f, val)
EOF
		t_exec "$WORK" "$CODE"
	fi
	t_end "elements"

	# what "import alchemy" exposes
	if fok alchemy/__init__.py alchemy/elements.py; then
		t_begin
		code <<'EOF'
alchemy = imp("alchemy")
if alchemy is not None:
    air = getattr(alchemy, "create_air", None)
    if air is None:
        fail("import alchemy; alchemy.create_air: AttributeError; expected the "
             "create_air() of alchemy/elements.py (expose it in __init__.py)")
    else:
        check_text("alchemy.create_air()", air, AIR)
    if hasattr(alchemy, "create_earth"):
        fail("import alchemy; alchemy.create_earth exists; expected an "
             "AttributeError (__init__.py must not expose create_earth)")
    else:
        ok()
    if "create_earth" in (getattr(alchemy, "__all__", None) or []):
        fail("alchemy.__all__ contains create_earth: it must stay hidden")
    e = imp("alchemy.elements")
    if air is not None and e is not None:
        if air is getattr(e, "create_air", None):
            ok()
        else:
            fail("alchemy.create_air is not the function of alchemy/elements.py"
                 " (__init__.py must import it, not define its own)")
    check_text("alchemy.elements.create_earth() (still in alchemy/elements.py)",
               get(e, "create_earth", "alchemy/elements.py"), EARTH)
EOF
		t_exec "$WORK" "$CODE"
		t_end "import alchemy"
	fi

	# import styles (static)
	t_begin
	if style ft_alembic_0.py "the subject asks for the 'import ...' structure" import elements; then
		has_from elements && t_warn "ft_alembic_0.py: uses 'from elements import ...' too ('import ...' structure expected)"
	fi
	if [ "$MOD" = 06 ]; then
		style ft_alembic_1.py "the subject asks for the 'from ... import ...' structure" from elements
		style ft_alembic_2.py "the subject asks for the 'import ...' structure" import alchemy.elements
		style ft_alembic_3.py "the subject asks for the 'from ... import ...' structure" from alchemy.elements
		style ft_alembic_5.py "the subject asks for 'from alchemy import ...'" from alchemy \
			&& ! has_from alchemy create_air \
			&& t_warn "ft_alembic_5.py: create_air is not imported with 'from alchemy import create_air'"
	fi
	if style "$hidden" "the subject asks for 'import alchemy'" import alchemy; then
		others=""
		for x in "${IMPS[@]}"; do
			IFS='|' read -r k l t v m n <<< "$x"
			[[ $m == alchemy.* ]] || { [ "$k" = from ] && [ "$m" = alchemy ]; } && others+="line $l "
		done
		[ -n "$others" ] && t_warn "$hidden: other imports of alchemy (${others% }): create_earth must be reached only through 'import alchemy'"
	fi
	t_end "import styles"

	# the programs, run from the root like in the subject
	script_line ft_alembic_0.py "=== Alembic 0 ===${nl}Using: 'import ...' structure to access elements.py${nl}Testing create_fire: $FIRE$nl" \
		"$FIRE"
	if [ "$MOD" = 06 ]; then
		script_line ft_alembic_1.py "=== Alembic 1 ===${nl}Using: 'from ... import ...' structure to access elements.py${nl}Testing create_water: $WATER$nl" \
			"$WATER"
		script_line ft_alembic_2.py "=== Alembic 2 ===${nl}Accessing alchemy/elements.py using 'import ...' structure${nl}Testing create_earth: $EARTH$nl" \
			"$EARTH"
		script_line ft_alembic_3.py "=== Alembic 3 ===${nl}Accessing alchemy/elements.py using 'from ... import ...' structure${nl}Testing create_air: $AIR$nl" \
			"$AIR"
	fi
	script_line "$hidden" "=== Alembic ${hidden//[^0-9]/} ===${nl}Accessing the alchemy module using 'import alchemy'${nl}Testing create_air: $AIR${nl}Now show that not all functions can be reached${nl}This will raise an exception!$nl" \
		"$AIR" "raise:AttributeError on create_earth:AttributeError|has no attribute:create_earth"
	[ "$MOD" = 06 ] && script_line ft_alembic_5.py \
		"=== Alembic 5 ===${nl}Accessing the alchemy module using 'from alchemy import ...'${nl}Testing create_air: $AIR$nl" "$AIR"
}

# ---------------------------- Distillation ---------------------------------- #
# alch_potions: tests of alchemy/potions.py and of the distillation scripts
alch_potions() {
	if fok alchemy/potions.py; then
		t_begin
		code <<'EOF'
p = imp("alchemy.potions")
check_text("alchemy.potions.healing_potion()", get(p, "healing_potion", "alchemy/potions.py"), HEAL)
check_text("alchemy.potions.strength_potion()", get(p, "strength_potion", "alchemy/potions.py"), STRENGTH)
check_text("alchemy.potions.strength_potion() (2nd call)", get(p, "strength_potion", "alchemy/potions.py"), STRENGTH)
EOF
		t_exec "$WORK" "$CODE"
		t_end "potions"

		# the potions must be brewed with the element functions
		t_begin
		code <<'EOF'
try:
    patched_alchemy(FAKE)
except BaseException as e:
    fail("import alchemy (with fake element functions) raises %s" % summary(e))
else:
    p = imp("alchemy.potions")
    h = "Healing potion brewed with 'EARTH#' and 'AIR#'"
    s = "Strength potion brewed with 'FIRE#' and 'WATER#'"
    check_text("healing_potion() with fake create_earth() / create_air()",
               get(p, "healing_potion"), h,
               desc=rep(h) + ": it must call create_earth() and create_air(), not copy their text")
    check_text("strength_potion() with fake create_fire() / create_water()",
               get(p, "strength_potion"), s,
               desc=rep(s) + ": it must call create_fire() and create_water(), not copy their text")
EOF
		t_exec "$WORK" "$CODE"
		T_INFO="(the element functions are replaced by fakes: the potions must change)"
		t_ok || T_INFO=""
		t_end "uses the elements"
	fi

	if [ "$MOD" = 06 ] && fok alchemy/__init__.py alchemy/potions.py; then
		t_begin
		code <<'EOF'
alchemy = imp("alchemy")
if alchemy is not None:
    sp = getattr(alchemy, "strength_potion", None) \
        or getattr(getattr(alchemy, "potions", None), "strength_potion", None)
    if sp is None:
        fail("import alchemy: neither alchemy.strength_potion nor "
             "alchemy.potions.strength_potion exists (ft_distillation_1.py "
             "must reach the strength potion with 'import alchemy' only)")
    else:
        check_text("strength potion through import alchemy", sp, STRENGTH)
    heal = getattr(alchemy, "heal", None)
    if heal is None:
        fail("import alchemy; alchemy.heal: AttributeError; expected the alias "
             "of healing_potion (in __init__.py: from .potions import "
             "healing_potion as heal)")
    else:
        check_text("alchemy.heal()", heal, HEAL)
        p = imp("alchemy.potions")
        if p is not None and heal is not getattr(p, "healing_potion", None):
            warn("alchemy.heal is not alchemy.potions.healing_potion: a "
                 "package alias is usually the same function")
    if hasattr(alchemy, "create_earth"):
        fail("import alchemy; alchemy.create_earth exists: it must stay hidden")
EOF
		t_exec "$WORK" "$CODE"
		t_end "heal alias"
	fi

	t_begin
	style ft_distillation_0.py "the subject asks for 'from ... import ...' on alchemy/potions.py" from alchemy.potions
	if [ "$MOD" = 06 ]; then
		if style ft_distillation_1.py "the subject asks for the 'import alchemy' structure" import alchemy; then
			python3 -I "$PT" idents "$WORK/ft_distillation_1.py" | grep -qx heal \
				|| t_warn "ft_distillation_1.py: does not use the heal alias (alchemy.heal())"
		fi
	fi
	t_end "styles: distillation"

	script_line ft_distillation_0.py "=== Distillation 0 ===${nl}Direct access to alchemy/potions.py${nl}Testing strength_potion: $STRENGTH${nl}Testing healing_potion: $HEAL$nl" \
		"$STRENGTH$nl$HEAL"
	[ "$MOD" = 06 ] && script_line ft_distillation_1.py \
		"=== Distillation 1 ===${nl}Using: 'import alchemy' structure to access potions${nl}Testing strength_potion: $STRENGTH${nl}Testing heal alias: $HEAL$nl" \
		"$STRENGTH$nl$HEAL"
}

# -------------------------- The Great Transmutation ------------------------- #
alch_recipes() {
	local x k l t v m n abs="" rel=""
	if fok alchemy/transmutation/recipes.py; then
		t_begin
		code <<'EOF'
r = imp("alchemy.transmutation.recipes")
f = get(r, "lead_to_gold", "alchemy/transmutation/recipes.py")
check_text("recipes.lead_to_gold()", f, GOLD)
check_text("recipes.lead_to_gold() (2nd call)", f, GOLD)
EOF
		t_exec "$WORK" "$CODE"
		code <<'EOF'
try:
    patched_alchemy(FAKE)
except BaseException as e:
    fail("import alchemy (with fake element functions) raises %s" % summary(e))
else:
    r = imp("alchemy.transmutation.recipes")
    g = ("Recipe transmuting Lead to Gold: brew 'AIR#' and 'Strength potion "
         "brewed with 'FIRE#' and 'WATER#'' mixed with 'FIRE#'")
    check_text("lead_to_gold() with fake element functions",
               get(r, "lead_to_gold"), g,
               desc=rep(g) + ": it must call create_air(), strength_potion() and create_fire()")
EOF
		t_exec "$WORK" "$CODE"
		t_end "lead_to_gold"

		# at least one absolute and one relative import
		imports_of alchemy/transmutation/recipes.py
		for x in "${IMPS[@]}"; do
			IFS='|' read -r k l t v m n <<< "$x"
			if [ "$v" -gt 0 ]; then rel+="$l, "
			elif [[ $m == alchemy* || $m == elements ]]; then abs+="$l, "
			fi
		done
		t_begin
		T_N=2
		[ -z "$abs" ] && t_fail "recipes.py: no absolute import of your modules (like 'from alchemy.potions import ...' or 'import elements')"
		[ -z "$rel" ] && t_fail "recipes.py: no relative import (like 'from ..elements import ...')"
		T_INFO="(absolute: line ${abs%, }; relative: line ${rel%, })"
		t_ok || T_INFO=""
		t_end "absolute + relative"
	fi

	t_begin
	style ft_transmutation_0.py "the subject asks for 'import ...' on alchemy/transmutation/recipes.py" import alchemy.transmutation.recipes
	if [ "$MOD" = 06 ]; then
		style ft_transmutation_1.py "the subject asks for 'import ...' on the transmutation module" import alchemy.transmutation
		if style ft_transmutation_2.py "the subject asks for 'import alchemy'" import alchemy; then
			for x in "${IMPS[@]}"; do
				IFS='|' read -r k l t v m n <<< "$x"
				if [[ $m == alchemy.* ]] || { [ "$k" = from ] && [ "$m" = alchemy ]; }; then
					t_warn "ft_transmutation_2.py: line $l imports $m${n:+ ($n)}: the subject asks for the alchemy module only"
				fi
			done
		fi
	fi
	t_end "styles: transmutation"

	script_line ft_transmutation_0.py "=== Transmutation 0 ===${nl}Using file alchemy/transmutation/recipes.py directly${nl}Testing lead to gold: $GOLD$nl" "$GOLD"
	if [ "$MOD" = 06 ]; then
		script_line ft_transmutation_1.py "=== Transmutation 1 ===${nl}Import transmutation module directly${nl}Testing lead to gold: $GOLD$nl" "$GOLD"
		script_line ft_transmutation_2.py "=== Transmutation 2 ===${nl}Import alchemy module only${nl}Testing lead to gold: $GOLD$nl" "$GOLD"
	fi
}

# ------------------------------ Avoid the Explosion -------------------------- #
alch_grimoire() {
	local GR=alchemy/grimoire f d top late kind="" defs w
	if fok $GR/__init__.py $GR/light_spellbook.py $GR/light_validator.py; then
		# the light grimoire works whatever the import order
		t_begin
		for f in alchemy.grimoire.light_spellbook alchemy.grimoire.light_validator alchemy.grimoire alchemy; do
			code <<EOF
try:
    import $f
    import alchemy.grimoire.light_spellbook as sb
    sb.light_spell_record("Fantasy", "fire")
except BaseException as e:
    fail("new python3, import $f first, then light_spell_record(): raises %s"
         % summary(e))
else:
    ok()
EOF
			t_exec "$WORK" "$CODE"
		done
		T_INFO="(4 fresh imports: spellbook first, validator first, grimoire, alchemy)"
		t_ok || T_INFO="the light pair must work whatever module is imported first"
		t_end "light: no explosion"

		t_begin
		code <<'EOF'
sb = imp("alchemy.grimoire.light_spellbook")
va = imp("alchemy.grimoire.light_validator")
LIGHT = ["earth", "air", "fire", "water"]
check("light_spell_allowed_ingredients()",
      get(sb, "light_spell_allowed_ingredients", "light_spellbook.py"), None,
      pred=lambda g: isinstance(g, list) and sorted(str(x).lower() for x in g) == sorted(LIGHT),
      desc='a list with "earth", "air", "fire", "water"')
val = get(va, "validate_ingredients", "light_validator.py")
cases = [("Earth, wind and fire", True), ("fire", True), ("WATER", True),
         ("AiR and salt", True), ("earth", True), ("salt, fire", True),
         ("dragon scales", False), ("", False), ("bats, frogs", False),
         ("ice and stone", False)]
for ing, good in cases:
    exp = ("contains %s and %s" % (rep(ing), "VALID" if good else "INVALID"))
    got = check("validate_ingredients(%s)" % rep(ing), val, None, args=(ing,),
                pred=lambda g: isinstance(g, str) and ing in g and "VALID" in g
                and ("INVALID" in g) != good, desc="a string that " + exp)
    if good and ing == "Earth, wind and fire" and isinstance(got, str) \
            and got != "Earth, wind and fire - VALID":
        warn("validate_ingredients(%s) returns %s; the subject example shows "
             "\"Earth, wind and fire - VALID\"" % (rep(ing), rep(got)))
rec = get(sb, "light_spell_record", "light_spellbook.py")
want = "Spell recorded: Fantasy (Earth, wind and fire - VALID)"
got = check('light_spell_record("Fantasy", "Earth, wind and fire")', rec, None,
            args=("Fantasy", "Earth, wind and fire"),
            pred=lambda g: isinstance(g, str) and "Fantasy" in g
            and "recorded" in g.lower() and "VALID" in g and "INVALID" not in g,
            desc="a string with Fantasy, recorded and VALID (example: %s)" % rep(want))
if isinstance(got, str) and got != want and "recorded" in got.lower():
    warn('light_spell_record("Fantasy", "Earth, wind and fire") returns %s; '
         "the subject example shows %s" % (rep(got), rep(want)))
check('light_spell_record("Sunrise", "FIRE")', rec, None, args=("Sunrise", "FIRE"),
      pred=lambda g: isinstance(g, str) and "Sunrise" in g and "recorded" in g.lower()
      and "INVALID" not in g, desc="a recorded spell (FIRE is a light ingredient)")
for name, ing in (("Nightmare", "bats and frogs"), ("Void", "")):
    check("light_spell_record(%s, %s)" % (rep(name), rep(ing)), rec, None,
          args=(name, ing),
          pred=lambda g: isinstance(g, str) and name in g
          and ("reject" in g.lower() or "not recorded" in g.lower() or "INVALID" in g)
          and not g.lower().startswith("spell recorded"),
          desc="a rejected spell (no light ingredient)")
EOF
		t_exec "$WORK" "$CODE"
		t_end "light grimoire"

		# how the light pair avoids the cycle (information)
		imports_of $GR/light_validator.py
		top=$(imports_module light_spellbook | grep -c '^top'); late=$(imports_module light_spellbook | grep -c '^late')
		imports_of $GR/light_spellbook.py
		top=$((top + $(imports_module light_validator | grep -c '^top')))
		late=$((late + $(imports_module light_validator | grep -c '^late')))
		if [ $late -gt 0 ]; then kind="import inside a function (late import)"
		elif [ $top -ge 2 ]; then kind="both files import each other at the top"
		elif [ $top -eq 1 ]; then kind="one-way dependency (only one file imports the other)"
		else kind="the two files do not import each other"; fi
		t_begin
		T_N=2
		python3 -I "$PT" idents "$WORK/$GR/light_validator.py" | grep -qxE 'light_spell_allowed_ingredients|light_spellbook' \
			|| t_warn "light_validator.py never uses the spellbook (light_spell_allowed_ingredients): the subject says the validator needs the spellbook"
		python3 -I "$PT" idents "$WORK/$GR/light_spellbook.py" | grep -qxE 'validate_ingredients|light_validator' \
			|| t_warn "light_spellbook.py never uses validate_ingredients(): the decision must come from the validator"
		T_INFO="(how the cycle is avoided: $kind)"
		t_end "light: dependencies"
	fi

	if fok $GR/__init__.py $GR/dark_spellbook.py $GR/dark_validator.py; then
		t_begin
		for f in dark_spellbook dark_validator; do
			code <<EOF
try:
    import alchemy.grimoire.$f
except ImportError as e:
    if ("circular" in str(e) or "partially initiali" in str(e)) and "dark" in str(e):
        ok()
    else:
        fail("import alchemy.grimoire.$f raises %s; expected an ImportError "
             "caused by the circular import of the dark pair" % summary(e))
except AttributeError as e:
    if "partially initiali" in str(e) and "dark" in str(e):
        ok()
    else:
        fail("import alchemy.grimoire.$f raises %s; expected an ImportError "
             "caused by the circular import" % summary(e))
except BaseException as e:
    fail("import alchemy.grimoire.$f raises %s; expected an ImportError "
         "caused by the circular import" % summary(e))
else:
    fail("import alchemy.grimoire.$f works; expected an ImportError (the dark "
         "pair must explode: circular import)")
EOF
			if [ $f = dark_spellbook ]; then t_exec "$WORK" "$CODE"
			else
				# the validator first: only a warning if it does not explode
				local save=("${T_FAILS[@]}")
				t_exec "$WORK" "$CODE"
				if [ ${#T_FAILS[@]} -gt ${#save[@]} ]; then
					t_warn "${T_FAILS[-1]}"
					T_FAILS=("${save[@]}")
				fi
			fi
		done
		code <<'EOF'
for m in ("alchemy", "alchemy.grimoire"):
    if imp(m) is not None:
        ok()
    if "alchemy.grimoire.dark_spellbook" in sys.modules:
        fail("import %s loads dark_spellbook: only ft_kaboom_1.py may touch the dark grimoire" % m)
EOF
		t_exec "$WORK" "$CODE"
		t_end "dark: explodes"

		# the dark pair, written the naive way
		t_begin
		defs=$(python3 -I "$PT" defs "$WORK/$GR/dark_spellbook.py")
		for f in dark_spell_allowed_ingredients dark_spell_record; do
			T_N=$((T_N + 1))
			grep -qx "$f" <<< "$defs" || t_fail "dark_spellbook.py: no function $f() (dark_-prefixed names)"
		done
		T_N=$((T_N + 1))
		python3 -I "$PT" defs "$WORK/$GR/dark_validator.py" | grep -q validate \
			|| t_fail "dark_validator.py: no validation function (like validate_ingredients())"
		for w in bats frogs arsenic eyeball; do
			grep -qi "$w" "$WORK/$GR/dark_spellbook.py" "$WORK/$GR/dark_validator.py" \
				|| t_warn "\"$w\" not found in the dark grimoire (dark ingredients: bats, frogs, arsenic, eyeball)"
		done
		imports_of $GR/dark_spellbook.py
		d=$(imports_module dark_validator | grep -m1 '^top' | sed 's/^top/line/')
		imports_of $GR/dark_validator.py
		top=$(imports_module dark_spellbook | grep -m1 '^top' | sed 's/^top/line/')
		T_N=$((T_N + 1))
		if [ -z "$d" ] || [ -z "$top" ]; then
			if [ "$MOD" = 05bis ]; then
				t_fail "the dark pair must import each other at the top of both files (dark_spellbook.py: ${d:-no top-level import of dark_validator}, dark_validator.py: ${top:-no top-level import of dark_spellbook})"
			else
				t_warn "the dark pair does not import each other at the top of both files (dark_spellbook.py: ${d:-no}, dark_validator.py: ${top:-no})"
			fi
		fi
		T_INFO=""
		[ -n "$d" ] && [ -n "$top" ] \
			&& T_INFO="(dark_spellbook.py $d, dark_validator.py $top: mutual imports at the top)"
		t_end "dark: the naive way"
	fi

	t_begin
	if fok ft_kaboom_0.py; then
		imports_of ft_kaboom_0.py
		T_N=$((T_N + 1))
		if has_import alchemy.grimoire || has_from alchemy.grimoire || has_from alchemy grimoire; then :
		elif has_import alchemy.grimoire.light_spellbook || has_from alchemy.grimoire.light_spellbook; then
			t_warn "ft_kaboom_0.py: imports light_spellbook directly; the subject asks to access the grimoire package"
		else
			t_fail "ft_kaboom_0.py: no import of the grimoire package (import alchemy.grimoire / from alchemy.grimoire import ...)"
		fi
	fi
	if fok ft_kaboom_1.py; then
		imports_of ft_kaboom_1.py
		T_N=$((T_N + 1))
		has_import alchemy.grimoire.dark_spellbook || has_from alchemy.grimoire.dark_spellbook \
			|| has_from alchemy.grimoire dark_spellbook \
			|| t_fail "ft_kaboom_1.py: no direct import of alchemy.grimoire.dark_spellbook"
	fi
	t_end "styles: kaboom"

	script_line ft_kaboom_0.py "=== Kaboom 0 ===${nl}Using grimoire module directly${nl}Testing record light spell: $SPELL$nl" \
		"VALID"
	script_line ft_kaboom_1.py "=== Kaboom 1 ===${nl}Access to alchemy/grimoire/dark_spellbook.py directly${nl}Test import now - THIS WILL RAISE AN UNCAUGHT EXCEPTION$nl" \
		"" "raise:ImportError (circular import):ImportError|circular|partially initiali:circular|partially initiali"
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

# ================================== Parts =================================== #
# The whole tree lives at the root of your folder: every program is run from
# there, like "python3 ft_alembic_0.py" in the subject.

# ---------------------------- Part I: The Alembic --------------------------- #
if wanted 1; then
	section "Part I - The Alembic"
	alch_alembic
fi

# ---------------------------- Part II: Distillation ------------------------- #
if wanted 2; then
	section "Part II - Distillation"
	P2=(alchemy/potions.py ft_distillation_0.py ft_distillation_1.py)
	if files_line . "${P2[@]}"; then
		alch_lint "${P2[@]}"
		alch_potions
	fi
fi

# ----------------------- Part III: The Great Transmutation ------------------ #
if wanted 3; then
	section "Part III - The Great Transmutation"
	P3=(alchemy/transmutation/__init__.py alchemy/transmutation/recipes.py
		ft_transmutation_0.py ft_transmutation_1.py ft_transmutation_2.py)
	if files_line . "${P3[@]}"; then
		alch_lint "${P3[@]}"
		alch_recipes
	fi
fi

# ------------------------- Part IV: Avoid the Explosion --------------------- #
if wanted 4; then
	section "Part IV - Avoid the Explosion"
	P4=(alchemy/grimoire/__init__.py alchemy/grimoire/light_spellbook.py alchemy/grimoire/light_validator.py
		alchemy/grimoire/dark_spellbook.py alchemy/grimoire/dark_validator.py ft_kaboom_0.py ft_kaboom_1.py)
	if files_line . "${P4[@]}"; then
		alch_lint "${P4[@]}"
		alch_grimoire
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	submission 0 alchemy/__init__.py alchemy/elements.py alchemy/potions.py \
		alchemy/grimoire/__init__.py alchemy/grimoire/dark_spellbook.py alchemy/grimoire/dark_validator.py \
		alchemy/grimoire/light_spellbook.py alchemy/grimoire/light_validator.py \
		alchemy/transmutation/__init__.py alchemy/transmutation/recipes.py elements.py \
		ft_alembic_0.py ft_alembic_1.py ft_alembic_2.py ft_alembic_3.py ft_alembic_4.py ft_alembic_5.py \
		ft_distillation_0.py ft_distillation_1.py ft_kaboom_0.py ft_kaboom_1.py \
		ft_transmutation_0.py ft_transmutation_1.py ft_transmutation_2.py
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
