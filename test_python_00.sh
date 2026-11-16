#!/usr/bin/env bash
# **************************************************************************** #
#  test_python_00.sh - single-file tester for Python Module 0 (Growing Code)   #
#                                                                              #
#  Usage (from your module folder, the one that contains ex0/ ex1/ ...):       #
#      bash ../test_python_00.sh               -> test everything              #
#      bash ../test_python_00.sh 2 ex6         -> only these exercises         #
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
banner "Python Module 0 tester (Growing Code)" "$DIR"
if ! compgen -G "$DIR/ex[0-9]*" > /dev/null; then
	echo "Error: no ex0/, ex1/, ... folder here. Run this script from your Python Module 0 folder." >&2
	exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	echo "Error: the subject requires Python 3.10 or later ($(python3 --version 2>&1) found)." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_python_00.XXXXXX)
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
EXS=(0 1 2 3 4 5 6 7)
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
# call <file> <function> [args]  : imports the file and calls the function
#                                  (the exception, if any, goes to $PT_EXC)
# diff <expected> <got>          : first difference between two outputs
# ast <file> <calls> <imports> <only-functions 0|1>
#                                : forbidden calls / imports, code outside functions
# sig <file> <function>          : signature with its type hints
# rec <file>                     : loops and recursive functions
cat > "$TMP/pt.py" <<'EOF'
import ast
import builtins
import importlib.util
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
            else:
                print("TOP %s %s" % (s.lineno, short(ast.unparse(s).split("\n")[0], 50)))
    return 0


def cmd_sig(path, func):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    for s in tree.body:
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)) and s.name == func:
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
            print("(%s)%s" % (", ".join(parts), ret))
            return 0
    print("NONE")
    return 0


def cmd_rec(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        tree = ast.parse(f.read(), path)
    loops = sum(isinstance(n, (ast.For, ast.While, ast.AsyncFor, ast.comprehension))
                for n in ast.walk(tree))
    rec = []
    for fn in ast.walk(tree):
        if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for n in ast.walk(fn):
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) \
                        and n.func.id == fn.name:
                    rec.append(fn.name)
                    break
    print("loops %d" % loops)
    print("recursive %s" % " ".join(rec))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    sys.exit({"call": cmd_call, "diff": cmd_diff, "ast": cmd_ast,
              "sig": cmd_sig, "rec": cmd_rec}[cmd](*sys.argv[2:]))
EOF
PT="$TMP/pt.py"

# --------------------------------- Linters ---------------------------------- #
FLAKE8=(); MYPY=()
if command -v flake8 > /dev/null 2>&1; then FLAKE8=(flake8)
elif python3 -m flake8 --version > /dev/null 2>&1; then FLAKE8=(python3 -m flake8); fi
if command -v mypy > /dev/null 2>&1; then MYPY=(mypy)
elif python3 -m mypy --version > /dev/null 2>&1; then MYPY=(python3 -m mypy); fi
[ ${#FLAKE8[@]} -eq 0 ] && printf "${Y}flake8 not installed (pip install flake8): the flake8 checks are skipped.${N}\n"
[ ${#MYPY[@]} -eq 0 ] && printf "${Y}mypy not installed (pip install mypy): the mypy check is skipped.${N}\n"

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
t_begin() { T_FAILS=(); T_N=0; T_INFO=""; T_TIMEOUT=0; }
t_fail() { T_FAILS+=("$1"); }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ]; }
t_end() {
	local m i=0
	if t_ok; then
		line_ok "$1" "${T_INFO:-($T_N tests)}"
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

# Inputs, shown on one line: "5", "3"
show_input() {
	local s="" l
	[ -z "$1" ] && { printf 'no input'; return; }
	while IFS= read -r l; do s+="\"$l\", "; done <<< "${1%$'\n'}"
	s=${s%, }
	[ ${#s} -gt 60 ] && s="${s:0:55}…"
	printf 'input %s' "$s"
}

# t_call <file> <function> <args> <stdin text> <expected stdout>
# Calls the function in a new python3 process and compares its output.
t_call() {
	local f=$1 fn=$2 args=$3 in=$4 exp=$5 what d
	[ $T_TIMEOUT -eq 1 ] && return 1
	printf '%s' "$in" > "$TMP/in"
	printf '%s' "$exp" > "$TMP/exp"
	run_py "$TMP/in" call "$f" "$fn" "$args"
	T_N=$((T_N + 1))
	if [ "$args" = "()" ]; then what="$fn() with $(show_input "$in")"; else what="$fn$args"; fi
	if [ $RC -eq 124 ] || [ $RC -eq 137 ]; then
		T_TIMEOUT=1
		t_fail "$what: infinite loop or too slow (more than 10 s); the next tests of this line are skipped"
		return 1
	fi
	if [ $RC -eq 4 ] || [ $RC -eq 5 ]; then t_fail "$EXC"; return 1; fi
	if [ $RC -eq 3 ]; then
		case $EXC in
			EOFError*) t_fail "$what: reads more input than given ($EXC)" ;;
			*) t_fail "$what: raises $EXC" ;;
		esac
		return 1
	fi
	if [ $RC -ne 0 ]; then t_fail "$what: python3 exits with status $RC $(grep -m1 -E 'Error' "$TMP/err" | cut -c1-100)"; return 1; fi
	d=$(python3 -I "$PT" diff "$TMP/exp" "$TMP/out")
	if [ -n "$d" ]; then t_fail "$what: $d"; return 1; fi
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

# static_checks <file> <allowed calls> <allowed imports> <functions...>
# Two lines: "only the function" (no code outside, no main) and "authorized"
STATIC_DEFS=()
static_checks() {
	local f=$1 calls=$2 imps=$3 kind a b c m=() w=() bad=() fn
	shift 3
	local base
	base=$(basename "$f")
	STATIC_DEFS=()
	while read -r kind a b c; do
		case $kind in
			DEF) STATIC_DEFS+=("$a") ;;
			CLASS) w+=("$base:$b: class $a (only the requested function is expected)") ;;
			MAIN) m+=("$base:$a: if __name__ == \"__main__\": block (forbidden: write only the function)") ;;
			TOP) m+=("$base:$a: code outside the function: $b${c:+ $c}") ;;
			CALL) bad+=("$a() (line $b)") ;;
			IMPORT) bad+=("import $a (line $b)") ;;
		esac
	done < <(python3 -I "$PT" ast "$f" "$calls" "$imps" 1)
	for fn in "$@"; do
		[[ " ${STATIC_DEFS[*]} " == *" $fn "* ]] || m+=("$base: no function named $fn() (the name must match exactly)")
	done
	for a in "${STATIC_DEFS[@]}"; do
		[[ " $* " == *" $a "* ]] || w+=("$base: extra function $a() (the file should only contain the requested function)")
	done
	S_STRUCT=("${m[@]}"); S_WARN=("${w[@]}"); S_BAD=("${bad[@]}")
}

# report_static <label of the authorized list> [warn about extra functions 0|1]
report_static() {
	local m
	if [ ${#S_STRUCT[@]} -eq 0 ]; then line_ok "only the function"
	else line_ko "only the function"; for m in "${S_STRUCT[@]}"; do msg "$m"; done; fi
	if [ "${2:-1}" = 1 ] && [ ${#S_WARN[@]} -gt 0 ]; then
		line_warn "extra code" "${S_WARN[0]}"
		for m in "${S_WARN[@]:1}"; do note "$m"; done
	fi
	if [ ${#S_BAD[@]} -eq 0 ]; then line_ok "authorized" "($1)"
	else
		line_ko "authorized"
		msg "forbidden: ${S_BAD[*]}"
		note "authorized: $1"
	fi
}

nl=$'\n'

# ================================ Exercises ================================= #

# ----------------------------- ex0: hello garden ---------------------------- #
if wanted 0; then
	section "ex0 - ft_hello_garden"
	if ex_files ex0 ft_hello_garden.py; then
		F="$WORK/ex0/ft_hello_garden.py"
		flake8_line ex0/ft_hello_garden.py
		static_checks "$F" print '' ft_hello_garden
		report_static "print()"
		t_begin
		t_call "$F" ft_hello_garden "()" "" "Hello, Garden Community!$nl"
		t_call "$F" ft_hello_garden "()" "ignored input$nl" "Hello, Garden Community!$nl"
		t_end "output"
	fi
fi

# ------------------------------ ex1: garden name ---------------------------- #
if wanted 1; then
	section "ex1 - ft_garden_name"
	if ex_files ex1 ft_garden_name.py; then
		F="$WORK/ex1/ft_garden_name.py"
		flake8_line ex1/ft_garden_name.py
		static_checks "$F" input,print '' ft_garden_name
		report_static "input(), print()"
		t_begin
		for name in "Community Garden" "Rose" "My  garden  42" "  spaces around  " "" \
			"Jardin de l'école" "UPPER lower 123" "a" "$(printf 'x%.0s' {1..200})" \
			"tab	inside" "Garden: Status" '"quoted"'; do
			t_call "$F" ft_garden_name "()" "$name$nl" \
				"Enter garden name: Garden: $name${nl}Status: Growing well!$nl"
		done
		t_end "output"
	fi
fi

# ------------------------------ ex2: plot area ------------------------------ #
if wanted 2; then
	section "ex2 - ft_plot_area"
	if ex_files ex2 ft_plot_area.py; then
		F="$WORK/ex2/ft_plot_area.py"
		flake8_line ex2/ft_plot_area.py
		static_checks "$F" input,int,print '' ft_plot_area
		report_static "input(), int(), print()"
		t_begin
		for c in "5 3" "3 5" "0 7" "7 0" "0 0" "1 1" "10 10" "12 25" "100 250" "999 1" \
			"123456 654321" "99999999999 99999999999"; do
			read -r l w <<< "$c"
			t_call "$F" ft_plot_area "()" "$l$nl$w$nl" \
				"Enter length: Enter width: Plot area: $(python3 -c "print($l * $w)")$nl"
		done
		t_call "$F" ft_plot_area "()" " 8 $nl 4$nl" "Enter length: Enter width: Plot area: 32$nl"
		t_call "$F" ft_plot_area "()" "007${nl}2$nl" "Enter length: Enter width: Plot area: 14$nl"
		t_end "output"
	fi
fi

# ----------------------------- ex3: harvest total --------------------------- #
if wanted 3; then
	section "ex3 - ft_harvest_total"
	if ex_files ex3 ft_harvest_total.py; then
		F="$WORK/ex3/ft_harvest_total.py"
		flake8_line ex3/ft_harvest_total.py
		static_checks "$F" input,int,print '' ft_harvest_total
		report_static "input(), int(), print()"
		t_begin
		for c in "5 8 3" "0 0 0" "1 2 3" "3 2 1" "10 0 0" "0 0 10" "100 200 300" \
			"7 7 7" "1 10 100" "999999 1 0" "123456789 987654321 1"; do
			read -r a b d <<< "$c"
			t_call "$F" ft_harvest_total "()" "$a$nl$b$nl$d$nl" \
				"Day 1 harvest: Day 2 harvest: Day 3 harvest: Total harvest: $((a + b + d))$nl"
		done
		t_end "output"
	fi
fi

# ------------------------------ ex4: plant age ------------------------------ #
if wanted 4; then
	section "ex4 - ft_plant_age"
	if ex_files ex4 ft_plant_age.py; then
		F="$WORK/ex4/ft_plant_age.py"
		flake8_line ex4/ft_plant_age.py
		static_checks "$F" input,int,print '' ft_plant_age
		report_static "input(), int(), print()"
		t_begin
		for age in 75 45 0 1 30 59 60 61 62 100 365 10000; do
			if [ "$age" -gt 60 ]; then r="Plant is ready to harvest!"; else r="Plant needs more time to grow."; fi
			t_call "$F" ft_plant_age "()" "$age$nl" "Enter plant age in days: $r$nl"
		done
		t_ok || T_INFO='reminder: 60 days is not enough ("strictly more than 60 days")'
		t_end "output"
	fi
fi

# ---------------------------- ex5: water reminder --------------------------- #
if wanted 5; then
	section "ex5 - ft_water_reminder"
	if ex_files ex5 ft_water_reminder.py; then
		F="$WORK/ex5/ft_water_reminder.py"
		flake8_line ex5/ft_water_reminder.py
		static_checks "$F" input,int,print '' ft_water_reminder
		report_static "input(), int(), print()"
		t_begin
		for d in 4 1 0 2 3 5 7 30 1000; do
			if [ "$d" -gt 2 ]; then r="Water the plants!"; else r="Plants are fine"; fi
			t_call "$F" ft_water_reminder "()" "$d$nl" "Days since last watering: $r$nl"
		done
		t_end "output"
	fi
fi

# ----------------------------- ex6: count harvest --------------------------- #
# count_out <n> → COUNT_OUT (a variable: $(...) would drop the final newline)
count_out() {
	local i
	COUNT_OUT="Days until harvest: "
	for ((i = 1; i <= $1; i++)); do COUNT_OUT+="Day $i$nl"; done
	COUNT_OUT+="Harvest time!$nl"
}

if wanted 6; then
	section "ex6 - ft_count_harvest"
	if ex_files ex6 ft_count_harvest_iterative.py ft_count_harvest_recursive.py; then
		FI="$WORK/ex6/ft_count_harvest_iterative.py"
		FR="$WORK/ex6/ft_count_harvest_recursive.py"
		flake8_line ex6/ft_count_harvest_iterative.py ex6/ft_count_harvest_recursive.py
		ALLOWED="input(), int(), print(), range(), helper functions for the recursion"
		static_checks "$FI" input,int,print,range '' ft_count_harvest_iterative
		S1=("${S_STRUCT[@]}"); W1=("${S_WARN[@]}"); B1=()
		for b in "${S_BAD[@]}"; do B1+=("iterative: $b"); done
		static_checks "$FR" input,int,print,range '' ft_count_harvest_recursive
		for b in "${S_BAD[@]}"; do B1+=("recursive: $b"); done
		# helper functions are allowed in the recursive version: only warn for the iterative one
		S_STRUCT=("${S1[@]}" "${S_STRUCT[@]}"); S_WARN=("${W1[@]}"); S_BAD=("${B1[@]}")
		report_static "$ALLOWED"

		read -r _ loops_i < <(python3 -I "$PT" rec "$FI" | grep '^loops')
		mapfile -t RI < <(python3 -I "$PT" rec "$FR")
		loops_r=${RI[0]#loops }; rec_r=${RI[1]#recursive}
		t_begin
		[ "$loops_i" -eq 0 ] && t_fail "ft_count_harvest_iterative.py: no loop (for / while) found"
		for n in 5 0 1 2 3 10 42 100 500; do
			count_out "$n"
			t_call "$FI" ft_count_harvest_iterative "()" "$n$nl" "$COUNT_OUT"
		done
		t_end "iterative"
		t_begin
		[ "$loops_r" -gt 0 ] && t_fail "ft_count_harvest_recursive.py: uses a loop ($loops_r for / while / comprehension): it must be recursive"
		[ -z "${rec_r// /}" ] && t_fail "ft_count_harvest_recursive.py: no function calls itself (no recursion found)"
		for n in 5 0 1 2 3 10 42 100 500; do
			count_out "$n"
			t_call "$FR" ft_count_harvest_recursive "()" "$n$nl" "$COUNT_OUT"
		done
		T_INFO=""
		[ -n "${rec_r// /}" ] && T_INFO="($T_N tests, recursive function:${rec_r})"
		t_end "recursive"
	fi
fi

# ---------------------------- ex7: seed inventory --------------------------- #
seed_out() {
	local cap
	cap=$(python3 -c 'import sys; print(sys.argv[1].capitalize())' "$1")
	case $3 in
		packets) printf '%s seeds: %s packets available\n' "$cap" "$2" ;;
		grams) printf '%s seeds: %s grams total\n' "$cap" "$2" ;;
		area) printf '%s seeds: covers %s square meters\n' "$cap" "$2" ;;
		*) printf 'Unknown unit type\n' ;;
	esac
}

if wanted 7; then
	section "ex7 - ft_seed_inventory"
	if ex_files ex7 ft_seed_inventory.py; then
		F="$WORK/ex7/ft_seed_inventory.py"
		flake8_line ex7/ft_seed_inventory.py
		static_checks "$F" print '' ft_seed_inventory
		report_static "print(), string methods"
		SIG=$(python3 -I "$PT" sig "$F" ft_seed_inventory)
		WANT_SIG="(seed_type: str, quantity: int, unit: str) -> None"
		if [ "$SIG" = "$WANT_SIG" ]; then line_ok "type hints" "$WANT_SIG"
		elif [ "$SIG" = NONE ]; then line_ko "type hints"; msg "function ft_seed_inventory() not found"
		else
			line_ko "type hints"
			msg "signature: def ft_seed_inventory$SIG"
			note "expected:  def ft_seed_inventory$WANT_SIG"
		fi
		mypy_line ex7/ft_seed_inventory.py

		t_begin
		for c in "tomato 15 packets" "carrot 8 grams" "lettuce 12 area" "basil 0 packets" \
			"sunflower 1 grams" "pumpkin 1000 area" "radish 3 area" "pepper 42 packets" \
			"onion 250 grams" "tomato 15 kilograms" "tomato 15 packet" "carrot 8 gram" \
			"lettuce 12 m2" "basil 5 Packets" "basil 5 GRAMS" "mint 2 unknown"; do
			read -r s q u <<< "$c"
			t_call "$F" ft_seed_inventory "('$s', $q, '$u')" "" "$(seed_out "$s" "$q" "$u")$nl"
		done
		t_call "$F" ft_seed_inventory "('tomato', 15, '')" "" "Unknown unit type$nl"
		t_call "$F" ft_seed_inventory "('Tomato', 15, 'packets')" "" "Tomato seeds: 15 packets available$nl"
		t_end "output"

		# Capital letter on words that are not all lowercase: depends on the method used
		t_begin
		for s in "TOMATO" "cherry tomato" "bELL pepper"; do
			t_call "$F" ft_seed_inventory "('$s', 2, 'packets')" "" "$(seed_out "$s" 2 packets)$nl"
		done
		if ! t_ok; then
			line_warn "capital letter" "with str.capitalize(), \"cherry tomato\" gives \"Cherry tomato\""
			for m in "${T_FAILS[@]:0:3}"; do note "$m"; done
			note "(not checked by the subject examples: just make sure you can explain your choice)"
		else
			line_ok "capital letter" "(same result as str.capitalize())"
		fi
	fi
fi

# -------------------------------- Submission -------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Submission"
	declare -A EXPECTED=(
		[ex0/ft_hello_garden.py]=1 [ex1/ft_garden_name.py]=1 [ex2/ft_plot_area.py]=1
		[ex3/ft_harvest_total.py]=1 [ex4/ft_plant_age.py]=1 [ex5/ft_water_reminder.py]=1
		[ex6/ft_count_harvest_iterative.py]=1 [ex6/ft_count_harvest_recursive.py]=1
		[ex7/ft_seed_inventory.py]=1
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
