#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_04.sh - single-file tester for Python Module 4 (Data Archivist) #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_04.sh               -> test everything              #
#      bash ../test_python_04.sh 2 ex3         -> only these exercises         #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Each test runs in its own python3 process: a crash or an infinite loop    #
#    in one test does not stop the others.                                     #
#  - The test files (missing, unreadable, directories, empty, big, unicode,    #
#    binary...) are created in /tmp, never in your folder.                     #
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
banner "Python Module 4 tester (Data Archivist)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 4 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_04.XXXXXX)
# (some test files are chmod 000: give the rights back before removing them)
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
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
EXS=(0 1 2 3)
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
# ast <file> <calls> <imports> <only-functions 0|1> [<sys attributes> <file methods>]
#                                : forbidden calls / imports / sys.X / file methods,
#                                  code outside functions, with statements, open() calls
# hints <file>                   : parameters and returns without a type hint
# script <file> [args]           : runs the file like "python3 file args" (sys.argv[0] is
#                                  the file name), and lists the files it never closed
# check <ex> <file> <case> [args]: checks the output of the last "script" run (ex0-ex3)
# vault <file> <group> <root 0|1>: tests secure_archive() (ex3)
# The checks print lines "FAIL <message>", "COSM <message>" (cosmetic difference),
# "INFO <text>" and "COUNT <number of tests>".
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import importlib.util
import inspect
import io
import os
import shlex
import sys
import traceback

ROOT = os.path.realpath(os.environ.get("PT_ROOT", "."))
TMP = os.environ.get("PT_TMP", ".")
DATA = os.environ.get("PT_DATA", ".")
REAL_OPEN = builtins.open
# file methods: only those of the "Authorized" line of each exercise may be called
IO_METHODS = {"read", "readline", "readlines", "write", "writelines", "close", "flush",
              "seek", "tell", "truncate", "fileno", "readable", "writable",
              "seekable", "isatty", "detach", "reconfigure"}


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


def rshort(v, n=60):
    s = repr(v)
    return s if len(s) <= n else s[:n] + "…"


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
        with REAL_OPEN(path, "w", encoding="utf-8") as f:
            f.write(text + "\n")


def rd(path, newline=""):
    try:
        with REAL_OPEN(path, encoding="utf-8", errors="replace", newline=newline) as f:
            return f.read()
    except OSError:
        return ""


def load(path):
    path = os.path.abspath(path)
    sys.path.insert(0, os.path.dirname(path))
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def first_diff(exp, got):
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


def file_diff(exp, got):
    """first_diff() for a file content or a returned string."""
    return first_diff(exp, got).replace("prints nothing", "empty") \
        .replace("extra output", "extra content").replace("output stops", "content stops")


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


def is_open(node):
    return (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == "open")


def cmd_ast(path, calls, imports, only_functions, sysattrs="*", methods="*"):
    with REAL_OPEN(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    try:
        tree = ast.parse(src, path)
    except SyntaxError as e:
        print("SYNTAX %s %s" % (e.lineno, e.msg))
        return 0
    allowed = set(calls.split(","))
    mods = set(imports.split(","))
    attrs = set(sysattrs.split(","))
    meths = set(methods.split(","))
    mine = bound_names(tree)
    bnames = set(dir(builtins))
    sys_names = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name == "sys":
                    sys_names.add(a.asname or "sys")

    def check(name, line):
        if (name in bnames and name not in mine and "*" not in allowed
                and name not in allowed and not is_exception(name)):
            print("CALL %s %s" % (name, line))

    def check_sys(name, line):
        print("SYSUSE %s %s" % (name, line))
        if "*" not in attrs and name not in attrs:
            print("ATTR sys.%s %s" % (name, line))

    in_with = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            check(n.func.id, n.lineno)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                and n.func.attr in IO_METHODS and "*" not in meths \
                and n.func.attr not in meths:
            print("METHOD %s %s" % (n.func.attr, n.lineno))
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) \
                and n.value.id in sys_names:
            check_sys(n.attr, n.lineno)
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
            elif n.module == "sys":
                for a in n.names:
                    check_sys(a.name, n.lineno)
        if isinstance(n, (ast.With, ast.AsyncWith)):
            opens = [it.context_expr for it in n.items if is_open(it.context_expr)]
            in_with.update(id(o) for o in opens)
            print("WITH %s %d" % (n.lineno, len(opens)))
    for n in ast.walk(tree):
        if is_open(n) and id(n) not in in_with:
            print("OPEN %s" % n.lineno)
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
    with REAL_OPEN(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    methods = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.ClassDef):
            for b in n.body:
                if isinstance(b, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    methods.add(id(b))
    nb = 0
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        nb += 1
        a = fn.args
        params = a.posonlyargs + a.args
        static = any(isinstance(d, ast.Name) and d.id == "staticmethod"
                     for d in fn.decorator_list)
        if id(fn) in methods and params and not static:
            params = params[1:]
        params = params + a.kwonlyargs + [x for x in (a.vararg, a.kwarg) if x]
        for x in params:
            if x.annotation is None:
                print("MISSING %s %d parameter '%s'" % (fn.name, fn.lineno, x.arg))
        if fn.returns is None:
            print("MISSING %s %d return" % (fn.name, fn.lineno))
    print("FUNCS %d" % nb)
    return 0


def cmd_script(path, *args):
    """Run the file like python3 does, with a tracked open()."""
    path = os.path.abspath(path)
    sys.argv = [os.path.basename(path)] + list(args)
    sys.path.insert(0, os.path.dirname(path))
    opened = []

    def tracked(*a, **k):
        f = REAL_OPEN(*a, **k)
        name = a[0] if a else k.get("file", "?")
        mode = a[1] if len(a) > 1 else k.get("mode", "r")
        opened.append(("'%s' (mode '%s')" % (name, mode), f))
        return f

    builtins.open = tracked
    code, err = 0, None
    try:
        # (not runpy.run_path(): it would change sys.argv[0])
        with REAL_OPEN(path, "rb") as f:
            code_obj = compile(f.read(), path, "exec")
        exec(code_obj, {"__name__": "__main__", "__file__": path,
                        "__builtins__": builtins})
    except SystemExit as e:
        if e.code is None:
            code = 0
        elif isinstance(e.code, int):
            code = e.code
        else:
            print(e.code, file=sys.stderr)
            code = 1
    except BaseException as e:
        err = e
    builtins.open = REAL_OPEN
    if err is not None:
        traceback.print_exception(err)
        report(summary(err))
        code = 1
    try:
        sys.stdout.flush()
    except Exception:
        pass
    left = [name for name, f in opened if not getattr(f, "closed", True)]
    with REAL_OPEN(os.path.join(TMP, "open"), "w", encoding="utf-8") as f:
        f.write("".join(n + "\n" for n in left))
    return code


# ------------------------- checks of ex0 / ex1 / ex2 ------------------------ #
HEADERS = {"0": "=== Cyber Archives Recovery ===",
           "1": "=== Cyber Archives Recovery & Preservation ===",
           "2": "=== Cyber Archives Recovery & Preservation ===",
           "3": "=== Cyber Archives Security ==="}
PROMPT = "Enter new file name (or empty): "
# files that are always in the folder where the programs run
KEEP = {"ancient_fragment.txt", "existing.txt", "data", "sub"}


def transform(content):
    """Add '#' at the end of each line (also the last one without newline)."""
    parts = content.split("\n")
    last = parts.pop()
    return "".join(p + "#\n" for p in parts) + (last + "#" if last else "")


def original(name):
    """Content of a test file (before the run), read as open() would."""
    if "/" not in name:
        name = os.path.join(DATA, name)
    with REAL_OPEN(name, encoding="utf-8") as f:
        return f.read()


def open_error(name, mode):
    try:
        f = REAL_OPEN(name, mode)
    except OSError as e:
        return e
    f.close()
    if "w" in mode:
        os.remove(name)
    return None


def cmd_check(ex, script, case, *argv):
    out = rd(os.path.join(TMP, "out"))
    err = rd(os.path.join(TMP, "err"))
    stdin = rd(os.path.join(TMP, "in"))
    left = [x for x in rd(os.path.join(TMP, "open")).split("\n") if x]
    target = stdin.split("\n")[0]
    what = "python3 " + " ".join([script] + [shlex.quote(a) for a in argv])
    if ex in "12" and case not in ("usage", "args"):
        what += ", no input (EOF)" if stdin == "" else ', input "%s"' % short(target, 30)
    hdr = HEADERS[ex]
    errs = err if ex == "2" else out + err      # where error messages must be
    where = "stderr" if ex == "2" else "the output"

    def fail(m):
        print("FAIL %s: %s" % (what, m))

    def cosm(m):
        print("COSM %s: %s" % (what, m))

    if "Traceback (most recent call last)" in err:
        exc = rd(os.path.join(TMP, "exc")).strip()
        exc = exc or [x for x in err.split("\n") if x.strip()][-1]
        m = "crashes with %s (exceptions must be handled)" % exc
        if case == "binary" or (case == "eof" and ex == "1"):
            cosm(m)
        else:
            fail(m)
        return 0
    for name in left:
        fail("the file %s is never closed" % name)

    if case == "usage":
        exp = "Usage: %s <file>" % script
        lines = (out + err).splitlines()
        use = [x for x in lines if "usage" in x.lower()]
        if exp in lines:
            pass
        elif use:
            cosm('usage line "%s"; the subject example gives "%s"' % (short(use[0]), exp))
        elif ex == "0":
            fail('prints "%s"; expected "%s"' % (short(out + err), exp) if out + err
                 else 'prints nothing; expected "%s"' % exp)
        else:
            cosm('no usage message (like "%s")' % exp)
        if ex == "0" and hdr in out.splitlines():
            cosm("prints the header before the usage line (the subject example does not)")
        return 0
    if case in ("args", "binary"):
        return 0
    if case == "demo":
        if hdr not in out.splitlines():
            cosm('no "%s" line (subject example)' % hdr)
        if "(True, " not in out or "(False, " not in out:
            cosm("the demo should print secure_archive() results, like (True, '...') "
                 "and (False, '...') in the subject example")
        if err:
            cosm('writes to stderr: "%s"' % short(err))
        return 0

    src = argv[0]
    created = sorted(set(os.listdir(".")) - KEEP)

    if case in ("show", "eof"):
        content = original(src)
        new = transform(content)
        exp = hdr + "\nAccessing file '%s'\n---\n\n%s\n---\nFile '%s' closed.\n" \
            % (src, content, src)
        if ex != "0":
            exp += "\nTransform data:\n---\n\n%s\n---\n%s" % (new, PROMPT)
            if target:
                exp += "Saving data to '%s'\nData saved in file '%s'.\n" % (target, target)
            else:
                exp += "Not saving data.\n"
        if content and content not in out:
            fail("the content of the file is not displayed as it is (%s)"
                 % first_diff(exp, out))
        elif ex != "0" and new and new not in out:
            m = "the content with '#' at the end of each line is not displayed (%s)" \
                % first_diff(exp, out)
            (fail if content.endswith("\n") else cosm)(m)
        elif out != exp:
            cosm(first_diff(exp, out))
        if err:
            cosm('writes to stderr: "%s"' % short(err))
        if ex == "0" or not target:
            if created:
                fail("creates the file(s) %s" % ", ".join(repr(x) for x in created))
            return 0
        if not os.path.isfile(target):
            m = "the file '%s' is not created" % target
            if os.path.exists(target + "\n"):
                m += " (a file named %r is: remove the newline)" % (target + "\n")
            fail(m)
            return 0
        got = rd(target)
        if got != new:
            m = "saved file '%s': %s" % (target, file_diff(new, got))
            if content.endswith("\n") and got.rstrip("\n") != new.rstrip("\n"):
                fail(m)
            else:
                cosm(m)
        return 0

    if case == "openerr":
        e = open_error(src, "r")
        line = ("[STDERR] " if ex == "2" else "") \
            + "Error opening file '%s': %s" % (src, e)
        if e is None:
            fail("(tester error: '%s' can be opened)" % src)
        elif ex == "2" and e.strerror in out:
            fail('the error message "%s" is printed to stdout: it must go to stderr'
                 % short([x for x in out.splitlines() if e.strerror in x][0]))
        elif e.strerror not in errs:
            fail('no "%s" error message in %s (expected "%s")' % (e.strerror, where, line))
        elif line not in errs.splitlines():
            got = [x for x in errs.splitlines() if e.strerror in x][0]
            cosm('error line "%s"; the subject example gives "%s"' % (short(got), short(line)))
        head = "".join(out.splitlines(True)[:2])
        exp = hdr + "\nAccessing file '%s'\n" % src
        if head != exp:
            cosm(first_diff(exp, head))
        if ex != "0" and "Transform data" in out:
            cosm('goes on after the error ("Transform data" is printed)')
        if created:
            fail("creates the file(s) %s" % ", ".join(repr(x) for x in created))
        return 0

    if case == "saveerr":
        content = original(src)
        e = open_error(target, "w")
        line = ("[STDERR] " if ex == "2" else "") \
            + "Error opening file '%s': %s" % (target, e)
        if content and content not in out:
            fail("the content of the file is not displayed as it is")
        if e is None:
            fail("(tester error: '%s' can be written)" % target)
        elif ex == "2" and e.strerror in out:
            fail('the error message "%s" is printed to stdout: it must go to stderr'
                 % short([x for x in out.splitlines() if e.strerror in x][0]))
        elif e.strerror not in errs:
            (fail if ex == "2" else cosm)(
                'no "%s" error message in %s (expected "%s")' % (e.strerror, where, line))
        elif ex == "2" and line not in err.splitlines():
            got = [x for x in err.splitlines() if e.strerror in x][0]
            cosm('error line "%s"; the subject example gives "%s"' % (short(got), short(line)))
        if "Data saved in file" in out:
            fail('prints "Data saved in file" although the file could not be written')
        elif ex == "2" and "Data not saved." not in (out + err).splitlines():
            cosm('no "Data not saved." line (subject example)')
        return 0
    print("FAIL tester error: unknown case %s" % case)
    return 0


# ------------------------------ ex3: secure_archive ------------------------- #
SUBJECT = ("[FRAGMENT 001] Digital preservation protocols established 2087\n"
           "[FRAGMENT 002] Knowledge must survive the entropy wars\n"
           "[FRAGMENT 003] Every byte saved is a victory against oblivion\n")
WRITE_MSG = "Content successfully written to file"
MISSING = object()


def candidates(path):
    """Values of the 'action' parameter: the constants that the student's
    code compares it with or passes it, then the usual ones."""
    with REAL_OPEN(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    vals = []

    def add(node):
        if isinstance(node, ast.Constant) and not isinstance(node.value, bool) \
                and isinstance(node.value, (int, str)) and len(str(node.value)) <= 12:
            vals.append(node.value)

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) \
                and n.func.id == "secure_archive" and len(n.args) >= 2:
            add(n.args[1])
        if isinstance(n, ast.FunctionDef) and n.name == "secure_archive":
            for d in n.args.defaults:
                add(d)
            for m in ast.walk(n):
                if isinstance(m, ast.Compare):
                    for c in [m.left] + m.comparators:
                        add(c)
                        if isinstance(c, (ast.Tuple, ast.List, ast.Set)):
                            for x in c.elts:
                                add(x)
                if isinstance(m, ast.MatchValue):
                    add(m.value)
    vals += ["r", "read", "R", "READ", "Read", "w", "write", "W", "WRITE", "Write", 0, 1, 2]
    res = []
    for v in vals:
        if not any(type(v) is type(x) and v == x for x in res):
            res.append(v)
    return res


class Vault:
    def __init__(self, fn, path, root):
        self.fn = fn
        self.n = 0
        self.root = root
        self.opened = []
        self.cands = candidates(path)
        self.read_args = None
        self.write_val = MISSING
        self.told_list = False
        builtins.open = self.tracked
        os.makedirs("probe", exist_ok=True)

    def tracked(self, *a, **k):
        f = REAL_OPEN(*a, **k)
        self.opened.append((a[0] if a else k.get("file", "?"), f))
        return f

    def fail(self, m):
        print("FAIL " + m)

    def cosm(self, m):
        print("COSM " + m)

    def raw(self, *a):
        start = len(self.opened)
        saved = sys.stdout
        sys.stdout = io.StringIO()
        try:
            r, exc = self.fn(*a), None
        except BaseException as e:
            r, exc = None, summary(e)
        finally:
            sys.stdout = saved
        left = ["'%s'" % n for n, f in self.opened[start:] if not f.closed]
        return r, exc, left

    def call(self, *a):
        self.n += 1
        r, exc, left = self.raw(*a)
        what = "secure_archive(%s)" % ", ".join(rshort(x, 40) for x in a)
        if left:
            self.fail("%s: the file %s is still open after the call" % (what, ", ".join(left)))
        if isinstance(r, list) and len(r) == 2:
            if not self.told_list:
                self.fail("%s returns the list %s; expected a tuple (bool, str)"
                          % (what, rshort(r)))
                self.told_list = True
            r = tuple(r)
        return what, r, exc

    def valid(self, what, r, exc, expected, soft=False):
        if exc is not None:
            (self.cosm if soft else self.fail)("%s raises %s; expected %s"
                                               % (what, exc, expected))
            return False
        if not (isinstance(r, tuple) and len(r) == 2 and isinstance(r[0], bool)
                and isinstance(r[1], str)):
            self.fail("%s returns %s; expected a tuple (bool, str)" % (what, rshort(r)))
            return False
        return True

    def find_read(self):
        text = "probe read 42\n"
        for args in [()] + [(c,) for c in self.cands] + [(c, "") for c in self.cands]:
            with REAL_OPEN("probe/r.txt", "w", encoding="utf-8") as f:
                f.write(text)
            r = self.raw("probe/r.txt", *args)[0]
            if isinstance(r, (tuple, list)) and len(r) == 2 and r[0] is True \
                    and r[1] == text:
                return args
        return None

    def find_write(self):
        for i, c in enumerate(self.cands):
            p = "probe/w%d.txt" % i
            self.raw(p, c, "probe write 42\n")
            if os.path.isfile(p) and rd(p) == "probe write 42\n":
                return c
        return MISSING

    def need_read(self):
        self.read_args = self.find_read()
        if self.read_args is None:
            self.fail("secure_archive(file) and secure_archive(file, X) never return "
                      "(True, <content>) for a regular file (X tried: %s)"
                      % ", ".join(repr(c) for c in self.cands))
            return False
        return True

    def need_write(self):
        self.write_val = self.find_write()
        if self.write_val is MISSING:
            self.cosm("could not find how to write: secure_archive(file, X, content) never "
                      "writes content (X tried: %s): check by hand"
                      % ", ".join(repr(c) for c in self.cands))
            return False
        return True

    def read_ok(self, name):
        content = original(name)
        what, r, exc = self.call(name, *self.read_args)
        if not self.valid(what, r, exc, "(True, <the file content>)"):
            return None
        if r[0] is not True:
            self.fail("%s returns %s; expected (True, <the file content>)"
                      % (what, rshort(r, 70)))
        elif r[1] != content:
            self.fail("%s: content %s" % (what, file_diff(content, r[1])))
        if original(name) != content:
            self.fail("%s modifies the file" % what)
        return r

    def error(self, name, mode, args, soft=False):
        e = open_error(name, mode)
        exp = (False, str(e))
        what, r, exc = self.call(*args)
        if not self.valid(what, r, exc, "(False, <error message>)", soft):
            return
        if r == exp:
            return
        if r[0] is False and e.strerror in r[1]:
            self.cosm("%s returns %s; the subject example gives %s"
                      % (what, rshort(r, 60), rshort(exp, 60)))
        else:
            (self.cosm if soft else self.fail)("%s returns %s; expected %s"
                                               % (what, rshort(r, 60),
                                                  rshort(exp, 60)))

    # ------- groups of tests -------
    def g_sig(self):
        self.n += 1
        try:
            params = list(inspect.signature(self.fn).parameters.values())
        except (TypeError, ValueError):
            params = []
        pos = [p for p in params if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
        var = any(p.kind == p.VAR_POSITIONAL for p in params)
        sig = "secure_archive(%s)" % ", ".join(p.name for p in params)
        empty = inspect.Parameter.empty
        if len(pos) < 3 and not var:
            self.fail("%s: expected 3 parameters (file name, optional action, "
                      "optional content)" % sig)
        elif pos:
            if pos[0].default is not empty:
                self.fail("%s: the file name must be mandatory (no default value)" % sig)
            for p in pos[1:3]:
                if p.default is empty:
                    self.fail("%s: the parameter '%s' must be optional (default value)"
                              % (sig, p.name))
            for p in pos[3:]:
                if p.default is empty:
                    self.fail("%s: extra mandatory parameter '%s'" % (sig, p.name))
        rd_args = self.find_read()
        wr = self.find_write()
        info = "read: secure_archive(%s)" % ", ".join(["file"] + [repr(x) for x in rd_args or ()])
        if rd_args is None:
            info = "read: not found"
        info += ", write: " + ("not found" if wr is MISSING
                               else "secure_archive(file, %r, content)" % wr)
        print("INFO (%s)" % info)

    def g_read(self):
        if not self.need_read():
            return
        for name in ["ancient_fragment.txt", "data/empty.txt", "data/one_line.txt",
                     "data/no_final_newline.txt", "data/unicode.txt",
                     "data/blank_lines.txt", "data/tabs.txt", "data/file with spaces.txt",
                     "data/fragment_é✓.txt", os.path.join(DATA, "existing.txt"),
                     "data/big.txt"]:
            self.read_ok(name)
        r1 = self.read_ok("ancient_fragment.txt")
        r2 = self.read_ok("ancient_fragment.txt")
        if r1 is not None and r2 is not None and r1 != r2:
            self.fail("two calls on the same file give different results")

    def g_rerr(self):
        args = self.find_read() or ()
        self.error("/not/existing/file", "r", ("/not/existing/file",) + args)
        for name in ["nope.txt", "nodir/x.txt", "data/adir", ".", "data/nope/"]:
            self.error(name, "r", (name,) + args)
        if not self.root:
            self.error("data/locked.txt", "r", ("data/locked.txt",) + args)
        what, r, exc = self.call("data/binary.bin", *args)
        self.valid(what, r, exc, "(False, <error message>) for a file that is not "
                   "valid UTF-8", soft=True)

    def g_write(self):
        if not self.need_write():
            return
        w = self.write_val
        big = "".join("[ARCHIVE %06d] %s\n" % (i, "#" * (i % 50)) for i in range(30000))
        cases = [("new_fragment.txt", SUBJECT), ("sub/unicode.txt", original("data/unicode.txt")),
                 ("empty_out.txt", ""), ("file with spaces.txt", "spaces\n"),
                 ("no_newline.txt", "no final newline"), ("archivé_✓.txt", "é✓🚀\n"),
                 ("big_out.txt", big)]
        for name, text in cases:
            what, r, exc = self.call(name, w, text)
            if not self.valid(what, r, exc, "(True, <message>)"):
                continue
            if r[0] is not True:
                self.fail("%s returns %s; expected (True, ...)" % (what, rshort(r, 60)))
            elif not os.path.isfile(name):
                self.fail("%s: the file is not created" % what)
            elif rd(name) != text:
                self.fail("%s: written file: %s" % (what, file_diff(text, rd(name))))
            elif name == "new_fragment.txt" and r[1] != WRITE_MSG:
                self.cosm("%s returns %s; the subject example gives %s"
                          % (what, rshort(r, 50), repr((True, WRITE_MSG))))
        old = rd("existing.txt")
        what, r, exc = self.call("existing.txt", w, "short\n")
        got = rd("existing.txt")
        if self.valid(what, r, exc, "(True, <message>)") and got != "short\n":
            if got.startswith(old):
                self.cosm("%s appends to the file instead of replacing its content" % what)
            else:
                self.fail("%s: written file: %s" % (what, file_diff("short\n", got)))
        rargs = self.find_read()
        if rargs is not None:
            what, r, exc = self.call("roundtrip.txt", w, SUBJECT)
            what2, r2, exc2 = self.call("roundtrip.txt", *rargs)
            if exc is None and exc2 is None and r2 != (True, SUBJECT):
                self.fail("%s then %s returns %s; expected %s" % (
                    what, what2, rshort(r2, 40), rshort((True, SUBJECT), 40)))

    def g_werr(self):
        if not self.need_write():
            return
        w = self.write_val
        targets = ["nodir/out.txt", "data/adir", "sub", "", "data/nope/x/y.txt"]
        if not self.root:
            targets.append("data/ro/out.txt")
        for t in targets:
            self.error(t, "w", (t, w, "data\n"))
        if os.path.exists(os.path.join(DATA, "ro", "out.txt")):
            self.fail("a file was created in a read-only folder")

    def g_edge(self):
        if not self.need_write():
            return
        w = self.write_val
        what, r, exc = self.call("nocontent.txt", w)
        self.valid(what, r, exc, "a tuple (bool, str): the content is optional", soft=True)
        bad = "bogus_action" if isinstance(w, str) else 42
        before = rd("ancient_fragment.txt")
        what, r, exc = self.call("ancient_fragment.txt", bad)
        self.valid(what, r, exc, "a tuple (bool, str) for an unknown action", soft=True)
        if rd("ancient_fragment.txt") != before:
            self.cosm("%s modifies the file" % what)
        what, r, exc = self.call("ancient_fragment.txt", bad, "x\n")
        self.valid(what, r, exc, "a tuple (bool, str) for an unknown action", soft=True)
        rargs = self.find_read()
        if rargs is not None:
            for i in range(3):
                self.call("loop.txt", w, "round %d\n" % i)
                what, r, exc = self.call("loop.txt", *rargs)
                if exc is None and r != (True, "round %d\n" % i):
                    self.fail("write then read of loop.txt, round %d: %s returns %s"
                              % (i, what, rshort(r, 50)))
                    break

    def finish(self, group):
        print("COUNT %d" % self.n)
        if self.root and group in ("rerr", "werr"):
            print("INFO (%d tests; permission tests skipped: running as root)" % self.n)


def cmd_vault(path, group, root):
    base = os.path.basename(path)
    saved = sys.stdout
    sys.stdout = io.StringIO()      # the demo, if it runs at import
    try:
        mod = load(path)
        err = None
    except BaseException as e:
        err = e
    finally:
        sys.stdout = saved
    if err is not None:
        print("FAIL importing %s raises %s" % (base, summary(err)))
        return 0
    fn = getattr(mod, "secure_archive", None)
    if not callable(fn):
        print("FAIL no function secure_archive() in %s" % base)
        return 0
    v = Vault(fn, path, root == "1")
    getattr(v, "g_" + group)()
    builtins.open = REAL_OPEN
    v.finish(group)
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"ast": cmd_ast, "hints": cmd_hints, "script": cmd_script,
              "check": cmd_check, "vault": cmd_vault}[cmd](*sys.argv[2:]))
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
export PT_ROOT="$WORK" PT_EXC="$TMP/exc" PT_TMP="$TMP"

# ------------------------------- Test files --------------------------------- #
# $DATA: the test files. $RUN: the folder where the programs run (rebuilt for each
# test) with ancient_fragment.txt, existing.txt, an empty sub/ folder and data/ → $DATA
DATA="$TMP/data"; RUN="$TMP/run"
export PT_DATA="$DATA"
mkdir -p "$DATA/adir" "$DATA/ro"
python3 -I - "$DATA" <<'EOF'
import os
import sys

d = sys.argv[1]
files = {
    "ancient_fragment.txt":
        "[FRAGMENT 001] Digital preservation protocols established 2087\n"
        "[FRAGMENT 002] Knowledge must survive the entropy wars\n"
        "[FRAGMENT 003] Every byte saved is a victory against oblivion\n",
    "empty.txt": "",
    "one_line.txt": "A single line without final newline",
    "no_final_newline.txt": "line one\nline two\nline three",
    "unicode.txt": "Données archivées : é à ü ç ✓\n日本語のテキスト 🚀\nλόγος « quotes » “smart”\n",
    "blank_lines.txt": "\n\nline 3 after two blank lines\n\n\nline 6\n",
    "tabs.txt": "\tleading tab\ntrailing spaces   \n  # already a hash #\n"
                "back\\slash 'quote' \"dq\" {braces} %s %d\n",
    "big.txt": "".join("[FRAGMENT %05d] %s\n" % (i, "data " * (i % 20))
                       for i in range(1, 20001)),
    "file with spaces.txt": "content of a file whose name has spaces\n",
    "fragment_é✓.txt": "file with a unicode name\n",
    "existing.txt": "OLD CONTENT THAT MUST BE REPLACED\n" * 100,
    "locked.txt": "secret\n",
}
for name, text in files.items():
    with open(os.path.join(d, name), "w", encoding="utf-8", newline="") as f:
        f.write(text)
with open(os.path.join(d, "binary.bin"), "wb") as f:
    f.write(bytes(range(256)) * 4)
EOF
chmod 000 "$DATA/locked.txt"; chmod 555 "$DATA/ro"
IS_ROOT=0
[ "$(id -u)" = 0 ] && IS_ROOT=1

reset_run() {
	chmod -R u+rwx "$RUN" 2>/dev/null
	rm -rf "$RUN"
	mkdir -p "$RUN/sub"
	cp "$DATA/ancient_fragment.txt" "$DATA/existing.txt" "$RUN/"
	ln -s "$DATA" "$RUN/data"
}

# ----------------------------- Execution tools ------------------------------ #
# run_in <folder> <stdin file> <pt.py arguments...> → RC, $TMP/out, $TMP/err, EXC
# (10 s at most per test)
run_in() {
	local cwd=$1 in=$2
	shift 2
	rm -f "$TMP/exc" "$TMP/open"
	( cd "$cwd" && exec timeout -k 1 10 python3 -I -X utf8 "$PT" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
	EXC=""
	[ -f "$TMP/exc" ] && EXC=$(head -1 "$TMP/exc")
}
run_py() { local in=$1; shift; run_in "$TMP" "$in" "$@"; }

# Results of one test line
# (after a timeout, the other tests of the same line are skipped)
# t_cosm: a difference with the subject example that is only cosmetic → !! line
t_begin() { T_FAILS=(); T_COSM=(); T_N=0; T_INFO=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_cosm() { T_COSM+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
t_end() {
	local m i=0
	if t_ok; then
		if [ ${#T_COSM[@]} -eq 0 ]; then
			line_ok "$1" "${T_INFO:-($T_N tests)}"
			return
		fi
		line_warn "$1" "no error, but differences with the subject (check by hand):"
	else
		line_ko "$1"
		for m in "${T_FAILS[@]}"; do
			i=$((i + 1))
			if [ $i -gt 6 ]; then msg "… (${#T_FAILS[@]} errors in total)"; break; fi
			msg "$m"
		done
	fi
	i=0
	for m in "${T_COSM[@]}"; do
		i=$((i + 1))
		if [ $i -gt 3 ]; then note "… (${#T_COSM[@]} differences in total)"; break; fi
		note "!! $m"
	done
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# t_parse <file>: reads the FAIL / COSM / INFO / COUNT lines of a pt.py check
t_parse() {
	local l
	while IFS= read -r l; do
		case $l in
			"FAIL "*) t_fail "${l#FAIL }" ;;
			"COSM "*) t_cosm "${l#COSM }" ;;
			"INFO "*) T_INFO=${l#INFO } ;;
			"COUNT "*) T_N=$((T_N + ${l#COUNT })) ;;
			"") ;;
			*) t_fail "tester error: $(cut -c1-100 <<< "$l")" ;;
		esac
	done < "$1"
}

# t_case <case> <stdin text> <args...>
# Runs "python3 $EX_FILE args" (in a fresh $RUN folder) with this input, then checks
# its output for the given case: usage, args, show, eof, openerr, saveerr, binary, demo
t_case() {
	local case=$1 in=$2
	shift 2
	[ $T_TIMEOUT -eq 1 ] && return 1
	reset_run
	printf '%s' "$in" > "$TMP/in"
	run_in "$RUN" "$TMP/in" script "$WORK/$EX_DIR/$EX_FILE" "$@"
	T_N=$((T_N + 1))
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "python3 $EX_FILE $*: infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
		return 1
	fi
	( cd "$RUN" && python3 -I -X utf8 "$PT" check "$EX_NUM" "$EX_FILE" "$case" "$@" ) \
		< /dev/null > "$TMP/chk" 2>&1
	t_parse "$TMP/chk"
}

# t_vault <group> <label>: one line of secure_archive() tests (ex3)
t_vault() {
	t_begin
	reset_run
	run_in "$RUN" /dev/null vault "$WORK/ex3/ft_vault_security.py" "$1" "$IS_ROOT"
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		t_fail "secure_archive(): infinite loop or too slow (more than 10 s for this line)"
	elif [ $RC -ne 0 ]; then
		t_fail "the tests stop: python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"
	fi
	t_parse "$TMP/out"
	t_end "$2"
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
	fi
}

# hints_line <file>: every parameter and every return has a type hint
hints_line() {
	local f=$1 kind fn l what n=0 m=()
	while read -r kind fn l what; do
		case $kind in
			MISSING) m+=("$(basename "$f"):$l: $fn(): $what has no type hint") ;;
			FUNCS) n=$fn ;;
		esac
	done < <(python3 -I "$PT" hints "$f")
	if [ ${#m[@]} -eq 0 ]; then line_ok "type hints" "($n functions)"
	else
		line_ko "type hints"
		for l in "${m[@]:0:6}"; do msg "$l"; done
		[ ${#m[@]} -gt 6 ] && msg "… (${#m[@]} in total)"
		note "\"All functions and methods must include type hints\""
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

# static_checks <file> <allowed calls> <allowed imports> <allowed sys.X> <allowed file methods>
# → S_BAD (forbidden calls / imports / sys attributes / file methods), STATIC_DEFS,
#   S_TOP (code outside functions and outside the main guard), S_MAIN (main guard),
#   S_WITH ("line number-of-open()" per with statement), S_OPEN (open() outside a with),
#   S_SYS (sys attributes used)
STATIC_DEFS=()
static_checks() {
	local f=$1 kind a b c base
	local -A seen=()
	base=$(basename "$f")
	STATIC_DEFS=(); S_BAD=(); S_TOP=(); S_MAIN=0; S_WITH=(); S_OPEN=(); S_SYS=" "
	while read -r kind a b c; do
		case $kind in
			DEF) STATIC_DEFS+=("$a") ;;
			MAIN) S_MAIN=1 ;;
			TOP) S_TOP+=("$base:$a: $b${c:+ $c}") ;;
			CALL) [ -z "${seen[c$a]}" ] && S_BAD+=("$a() (line $b)"); seen[c$a]=1 ;;
			IMPORT) S_BAD+=("import $a (line $b)") ;;
			ATTR) [ -z "${seen[a$a]}" ] && S_BAD+=("$a (line $b)"); seen[a$a]=1 ;;
			METHOD) [ -z "${seen[m$a]}" ] && S_BAD+=(".$a() (line $b)"); seen[m$a]=1 ;;
			WITH) S_WITH+=("$a $b") ;;
			OPEN) S_OPEN+=("$a") ;;
			SYSUSE) S_SYS+="$a " ;;
		esac
	done < <(python3 -I "$PT" ast "$f" "$2" "$3" 1 "$4" "$5")
}

# report_static <label of the authorized list> [extra note]
report_static() {
	local m s=""
	if [ ${#S_BAD[@]} -eq 0 ]; then line_ok "authorized" "($1)"
	else
		line_ko "authorized"
		for m in "${S_BAD[@]}"; do s+="$m, "; done
		msg "forbidden: ${s%, }"
		note "authorized: $1"
		[ -n "$2" ] && note "$2"
	fi
}

# no_with_line: ex0-ex2 must not use the with statement
no_with_line() {
	local w l=""
	if [ ${#S_WITH[@]} -eq 0 ]; then line_ok "no with statement"; return; fi
	for w in "${S_WITH[@]}"; do l+="${w%% *}, "; done
	line_ko "no with statement"
	msg "with statement at line ${l%, }: \"You must not use it before\" exercise 3"
}

# The standard types are allowed in every exercise
TYPES="str,int,float,list,dict,set,tuple"
TYPES_TXT="str/int/float/list/dict/set/tuple"
nl=$'\n'

# common_static <ex> <file> <calls> <imports> <sys.X> <file methods> <label> [note]
# flake8, mypy, type hints, authorized, no with statement (ex0-ex2)
common_static() {
	local ex=$1 file=$2
	flake8_line "$ex/$file"
	mypy_line "$ex/$file"
	hints_line "$WORK/$ex/$file"
	static_checks "$WORK/$ex/$file" "$3" "$4" "$5" "$6"
	report_static "$7" "$8"
	[ "$ex" != ex3 ] && no_with_line
}

# Tests shared by ex1 and ex2 (same program, different streams)
# archive_tests: lines "usage" ... "binary file"
archive_tests() {
	local f
	t_begin
	t_case usage "$nl"
	t_case args "$nl" ancient_fragment.txt data/empty.txt
	t_end "usage"

	t_begin
	t_case show "$nl" ancient_fragment.txt
	t_case show "new_fragment.txt$nl" ancient_fragment.txt
	t_end "subject example"

	t_begin
	for f in data/empty.txt data/one_line.txt data/no_final_newline.txt data/unicode.txt \
		data/blank_lines.txt data/tabs.txt "data/file with spaces.txt" \
		"data/fragment_é✓.txt" "$DATA/existing.txt"; do
		t_case show "out.txt$nl" "$f"
	done
	t_case show "$nl" data/unicode.txt
	t_case show "$nl" data/tabs.txt
	t_end "transform & save"

	t_begin
	t_case show "my archive.txt$nl" ancient_fragment.txt
	t_case show "archivé_✓.txt$nl" ancient_fragment.txt
	t_case show "sub/out.txt$nl" ancient_fragment.txt
	t_case show "$RUN/sub/absolute.txt$nl" ancient_fragment.txt
	t_case show "existing.txt$nl" ancient_fragment.txt
	t_case show "ancient_fragment.txt$nl" ancient_fragment.txt
	t_ok || T_INFO="the file must be created, or replaced if it already exists"
	t_end "save targets"

	t_begin
	t_case saveerr "nodir/out.txt$nl" ancient_fragment.txt
	t_case saveerr "sub$nl" ancient_fragment.txt
	t_case saveerr "data/adir$nl" ancient_fragment.txt
	[ $IS_ROOT -eq 0 ] && t_case saveerr "data/ro/out.txt$nl" ancient_fragment.txt
	[ $IS_ROOT -eq 1 ] && T_INFO="($T_N tests; read-only folder skipped: running as root)"
	t_end "$1"

	t_begin
	t_case openerr "$nl" foo
	t_case openerr "$nl" nodir/x.txt
	t_case openerr "$nl" data/adir
	t_case openerr "$nl" .
	if [ $IS_ROOT -eq 0 ]; then t_case openerr "$nl" data/locked.txt
	else T_INFO="($T_N tests; chmod 000 file skipped: running as root)"; fi
	t_end "$2"

	t_begin
	t_case show "big_out.txt$nl" data/big.txt
	t_end "big file"

	t_begin
	t_case binary "$nl" data/binary.bin
	t_end "binary file"
}

# ================================ Exercises ================================= #

# --------------------------- ex0: ancient text ------------------------------ #
if wanted 0; then
	section "ex0 - ft_ancient_text"
	if ex_files ex0 ft_ancient_text.py; then
		EX_NUM=0; EX_DIR=ex0; EX_FILE=ft_ancient_text.py
		common_static ex0 ft_ancient_text.py "len,open,print,$TYPES" sys,typing argv read,close \
			"import sys, sys.argv, len(), open(), import typing, typing.IO, .read(), .close(), print(), $TYPES_TXT"

		t_begin
		t_case usage ""
		t_case args "" ancient_fragment.txt data/empty.txt
		t_end "usage"

		t_begin
		t_case show "" ancient_fragment.txt
		t_end "subject example"

		t_begin
		for f in data/empty.txt data/one_line.txt data/no_final_newline.txt data/unicode.txt \
			data/blank_lines.txt data/tabs.txt "data/file with spaces.txt" \
			"data/fragment_é✓.txt" "$DATA/existing.txt"; do
			t_case show "" "$f"
		done
		t_end "display"

		t_begin
		t_case show "" data/big.txt
		t_end "big file"

		t_begin
		t_case openerr "" foo
		t_case openerr "" nodir/x.txt
		t_case openerr "" "/not/existing/file"
		t_end "nonexistent file"

		if [ $IS_ROOT -eq 1 ]; then
			line_skip "permission denied" "running as root: chmod 000 has no effect"
		else
			t_begin
			t_case openerr "" data/locked.txt
			t_end "permission denied"
		fi

		t_begin
		t_case openerr "" data/adir
		t_case openerr "" .
		t_case openerr "" data/
		t_end "directory"

		t_begin
		t_case binary "" data/binary.bin
		t_end "binary file"
	fi
fi

# --------------------------- ex1: archive creation -------------------------- #
if wanted 1; then
	section "ex1 - ft_archive_creation"
	if ex_files ex1 ft_archive_creation.py; then
		EX_NUM=1; EX_DIR=ex1; EX_FILE=ft_archive_creation.py
		common_static ex1 ft_archive_creation.py "len,open,print,input,$TYPES" sys,typing argv \
			read,write,close \
			"import sys, sys.argv, len(), open(), import typing, typing.IO, .read(), .write(), .close(), print(), input(), $TYPES_TXT"
		archive_tests "save errors" "read errors"

		t_begin
		t_case eof "" ancient_fragment.txt
		t_end "end of input (EOF)"
	fi
fi

# -------------------------- ex2: stream management -------------------------- #
if wanted 2; then
	section "ex2 - ft_stream_management"
	if ex_files ex2 ft_stream_management.py; then
		EX_NUM=2; EX_DIR=ex2; EX_FILE=ft_stream_management.py
		common_static ex2 ft_stream_management.py "len,open,print,$TYPES" sys,typing \
			argv,stdin,stdout,stderr read,readline,write,flush,close \
			"import sys, sys.argv, sys.stdin, sys.stdout, sys.stderr, len(), open(), import typing, typing.IO, .read(), .readline(), .write(), .flush(), .close(), print(), $TYPES_TXT" \
			"\"Get user input without using the input() built-in function\": use sys.stdin"
		if [[ $S_SYS == *" stdin "* ]]; then line_ok "sys.stdin" "(used for the input)"
		else line_warn "sys.stdin" "sys.stdin is not used: how is the input read?"; fi
		archive_tests "save errors -> stderr" "read errors -> stderr"

		t_begin
		t_case show "no_newline.txt" ancient_fragment.txt
		t_case show "" ancient_fragment.txt
		t_case eof "" ancient_fragment.txt
		t_case show "$nl$nl" ancient_fragment.txt
		t_ok || T_INFO="sys.stdin.readline() keeps the '\n' and returns '' at the end of the input"
		t_end "stdin input"
	fi
fi

# --------------------------- ex3: vault security ---------------------------- #
if wanted 3; then
	section "ex3 - ft_vault_security"
	if ex_files ex3 ft_vault_security.py; then
		EX_NUM=3; EX_DIR=ex3; EX_FILE=ft_vault_security.py
		common_static ex3 ft_vault_security.py "open,print,$TYPES" typing "*" read,write,close \
			"open(), .read(), .write(), print(), $TYPES_TXT (+ import typing for the type hints)"

		# secure_archive(): a function of the file
		if [[ " ${STATIC_DEFS[*]} " == *" secure_archive "* ]]; then line_ok "secure_archive()"
		else line_ko "secure_archive()"; msg "no function secure_archive() in ft_vault_security.py"; fi

		# with statement: required
		if [ ${#S_WITH[@]} -eq 0 ]; then
			line_ko "with statement"
			msg "no with statement: \"This exercise requires the use of the with statement\""
		else
			wo=0
			for w in "${S_WITH[@]}"; do [ "${w#* }" -gt 0 ] && wo=1; done
			if [ ${#S_OPEN[@]} -gt 0 ]; then
				line_warn "with statement" "open() outside a with statement at line ${S_OPEN[*]}"
			elif [ $wo -eq 0 ]; then
				line_warn "with statement" "no \"with open(...) as f:\": are the files really managed by with?"
			else
				line_ok "with statement" "(${#S_WITH[@]} with open(...))"
			fi
		fi

		# main guard: not required, but importing the file should not run the demo
		if [ ${#S_TOP[@]} -eq 0 ]; then line_ok "main guard"
		else
			line_warn "main guard" "code outside functions: importing the file runs it"
			for m in "${S_TOP[@]:0:3}"; do note "$m"; done
			note "(use if __name__ == \"__main__\": for the demo)"
		fi

		if [[ " ${STATIC_DEFS[*]} " == *" secure_archive "* ]]; then
			t_vault sig "signature"
			t_vault read "read"
			t_vault rerr "read errors"
			t_vault write "write"
			t_vault werr "write errors"
			t_vault edge "edge cases"
		fi

		t_begin
		t_case demo ""
		t_end "demo (main)"
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/ft_ancient_text.py]=1 [ex1/ft_archive_creation.py]=1
		[ex2/ft_stream_management.py]=1 [ex3/ft_vault_security.py]=1
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
