#!/usr/bin/env bash
# **************************************************************************** #
#  test_push_swap.sh - single-file push_swap tester                            #
#                                                                              #
#  Usage (from your push_swap folder):                                         #
#      bash ../test_push_swap.sh               -> test everything              #
#      bash ../test_push_swap.sh sort perf     -> only these parts             #
#      (parts: makefile submission errors sort perf bench bonus)               #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - push_swap is built with YOUR Makefile, then every output is checked by    #
#    a checker built into the script (no need for checker_linux).              #
#  - The 4 strategies (--simple --medium --complex --adaptive), --bench mode,  #
#    errors, performance and the bonus checker are tested.                     #
#  - AddressSanitizer detects crashes, memory overflows and leaks.             #
#  - Do NOT put this file in your repository.                                  #
# **************************************************************************** #

# ------ Relaunch in WSL if there is no compiler (Git Bash on Windows) ------- #
if ! command -v cc >/dev/null 2>&1; then
	if command -v wsl.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		MSYS_NO_PATHCONV=1 exec wsl.exe --cd "$(pwd -W)" -e bash -c \
			'exec bash "$(wslpath "$0")" "$@"' "$(cygpath -m "$0")" "$@"
	fi
	echo "Error: 'cc' not found. Run this script on Linux / WSL." >&2
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
banner "push_swap tester" "$DIR"
if [ ! -f "$DIR/Makefile" ]; then
	echo "Error: Makefile not found. Run this script from your push_swap folder." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_push_swap.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/asanlog"

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 22 ? 22 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }
# ("erreur" too: cc prints its messages in French on a French locale)
first_error() { grep -m1 -E "error|erreur|undefined|No rule|\*\*\*" "$1" | sed -E 's|^.*/||; s/^[[:space:]]+//' | cut -c1-150; }

# Parts to test
PARTS=(makefile submission errors sort perf bench bonus)
declare -A WANTED=()
for a in "$@"; do
	case " ${PARTS[*]} " in
		*" $a "*) WANTED[$a]=1 ;;
		*) echo "Unknown part: '$a'. Parts: ${PARTS[*]}" >&2; exit 1 ;;
	esac
done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# -------------------- Reference checker / generator (C) --------------------- #
cat > "$TMP/pscheck.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char			*g_ops[11] = {"sa", "sb", "ss", "pa", "pb", "ra",
	"rb", "rr", "rra", "rrb", "rrr"};
static long					*g_a;
static long					*g_b;
static int					g_na;
static int					g_nb;
static unsigned long long	g_s = 88172645463325252ULL;

static unsigned long long	rnd(void)
{
	g_s ^= g_s << 13;
	g_s ^= g_s >> 7;
	g_s ^= g_s << 17;
	return (g_s);
}

static void	sw(long *s, int n)
{
	long	t;

	if (n < 2)
		return ;
	t = s[0];
	s[0] = s[1];
	s[1] = t;
}

static void	rot(long *s, int n)
{
	long	t;

	if (n < 2)
		return ;
	t = s[0];
	memmove(s, s + 1, (n - 1) * sizeof(long));
	s[n - 1] = t;
}

static void	rrot(long *s, int n)
{
	long	t;

	if (n < 2)
		return ;
	t = s[n - 1];
	memmove(s + 1, s, (n - 1) * sizeof(long));
	s[0] = t;
}

static void	push(long *d, int *nd, long *s, int *ns)
{
	if (*ns == 0)
		return ;
	memmove(d + 1, d, *nd * sizeof(long));
	d[0] = s[0];
	memmove(s, s + 1, (*ns - 1) * sizeof(long));
	(*nd)++;
	(*ns)--;
}

static void	apply(int op)
{
	if (op == 0 || op == 2)
		sw(g_a, g_na);
	if (op == 1 || op == 2)
		sw(g_b, g_nb);
	if (op == 3)
		push(g_a, &g_na, g_b, &g_nb);
	if (op == 4)
		push(g_b, &g_nb, g_a, &g_na);
	if (op == 5 || op == 7)
		rot(g_a, g_na);
	if (op == 6 || op == 7)
		rot(g_b, g_nb);
	if (op == 8 || op == 10)
		rrot(g_a, g_na);
	if (op == 9 || op == 10)
		rrot(g_b, g_nb);
}

static void	init(int n, long *v)
{
	g_a = malloc((n + 1) * sizeof(long));
	g_b = malloc((n + 1) * sizeof(long));
	memcpy(g_a, v, n * sizeof(long));
	g_na = n;
	g_nb = 0;
}

static long	*parse(int n, char **s)
{
	long	*v = malloc((n + 1) * sizeof(long));

	for (int i = 0; i < n; i++)
		v[i] = strtol(s[i], NULL, 10);
	return (v);
}

static int	is_sorted(void)
{
	if (g_nb)
		return (0);
	for (int i = 0; i + 1 < g_na; i++)
		if (g_a[i] > g_a[i + 1])
			return (0);
	return (1);
}

static void	put_esc(const char *s, size_t n)
{
	putchar('"');
	for (size_t i = 0; i < n && i < 30; i++)
	{
		unsigned char c = s[i];
		if (c == '\r')
			printf("\\r");
		else if (c == '\t')
			printf("\\t");
		else if (c < 32 || c > 126)
			printf("\\x%02x", c);
		else
			putchar(c);
	}
	if (n > 30)
		printf("…");
	putchar('"');
}

/* check <numbers> < operations: "OK n c0..c10" / "KO n c0..c10" / "ERR ..." */
static int	cmd_check(int n, char **s)
{
	size_t	cap = 1 << 16;
	size_t	len = 0;
	size_t	r;
	size_t	i = 0;
	size_t	e;
	char	*buf = malloc(cap);
	long	cnt[11] = {0};
	long	nops = 0;
	int		line = 0;
	int		op;

	init(n, parse(n, s));
	while ((r = fread(buf + len, 1, cap - len, stdin)) > 0)
	{
		len += r;
		if (len == cap)
			buf = realloc(buf, cap *= 2);
	}
	while (i < len)
	{
		e = i;
		while (e < len && buf[e] != '\n')
			e++;
		line++;
		for (op = 10; op >= 0; op--)
			if (strlen(g_ops[op]) == e - i && !memcmp(g_ops[op], buf + i, e - i))
				break ;
		if (op < 0)
		{
			printf("ERR %d: ", line);
			put_esc(buf + i, e - i);
			printf(" is not a valid operation\n");
			return (0);
		}
		if (e == len)
		{
			printf("ERR %d: the last operation (%s) is not followed by \\n\n", line, g_ops[op]);
			return (0);
		}
		apply(op);
		cnt[op]++;
		nops++;
		i = e + 1;
	}
	printf("%s %ld", is_sorted() ? "OK" : "KO", nops);
	for (int k = 0; k < 11; k++)
		printf(" %ld", cnt[k]);
	printf("\n");
	return (0);
}

static long	mistakes(long *v, int n)
{
	long	m = 0;

	for (int i = 0; i < n; i++)
		for (int j = i + 1; j < n; j++)
			if (v[i] > v[j])
				m++;
	return (m);
}

/* disorder <numbers>: disorder in % (rounded, then truncated) */
static int	cmd_disorder(int n, char **s)
{
	long long	t = (long long)n * (n - 1) / 2;
	long long	m = mistakes(parse(n, s), n);
	long long	r;
	long long	tr;

	if (t == 0)
	{
		printf("0.00 0.00\n");
		return (0);
	}
	r = (m * 20000 + t) / (2 * t);
	tr = m * 10000 / t;
	printf("%lld.%02lld %lld.%02lld\n", r / 100, r % 100, tr / 100, tr % 100);
	return (0);
}

static int	cmp(const void *a, const void *b)
{
	long	x = *(const long *)a;
	long	y = *(const long *)b;

	return ((x > y) - (x < y));
}

static long	*random_values(int n, long range)
{
	long	*v = malloc((n + 1) * sizeof(long));
	long	x;
	int		dup;

	for (int i = 0; i < n; i++)
	{
		do
		{
			x = (long)(rnd() % (2 * range + 1)) - range;
			dup = 0;
			for (int j = 0; j < i && !dup; j++)
				dup = (v[j] == x);
		} while (dup);
		v[i] = x;
	}
	return (v);
}

/* values over the whole int range, INT_MIN, INT_MAX, 0 and -1 included */
static long	*extreme_values(int n)
{
	const long	sp[4] = {-2147483648L, 2147483647L, 0, -1};
	long		*v = malloc((n + 1) * sizeof(long));
	long		x;
	int			dup;

	for (int i = 0; i < n; i++)
	{
		do
		{
			x = i < 4 ? sp[i] : (long)(rnd() % 4294967296ULL) - 2147483648L;
			dup = 0;
			for (int j = 0; j < i && !dup; j++)
				dup = (v[j] == x);
		} while (dup);
		v[i] = x;
	}
	for (int i = n - 1; i > 0; i--)
	{
		int		j = rnd() % (i + 1);

		x = v[i];
		v[i] = v[j];
		v[j] = x;
	}
	return (v);
}

/* rand <seed> <n> <random|extreme|sorted|reverse|nearly|medium|rotated|swapends|pairs> */
static int	cmd_rand(unsigned long long seed, int n, const char *mode)
{
	long	*v;
	long	total = (long)n * (n - 1) / 2;
	long	t;
	int		near = !strcmp(mode, "nearly");

	g_s ^= seed * 0x9E3779B97F4A7C15ULL;
	if (!g_s)
		g_s = 1;
	v = !strcmp(mode, "extreme") ? extreme_values(n) : random_values(n, 1000000);
	if (strcmp(mode, "random") && strcmp(mode, "extreme"))
		qsort(v, n, sizeof(long), cmp);
	if (!strcmp(mode, "rotated") && n > 1)
		for (int k = 1 + rnd() % (n - 1); k > 0; k--)
			rot(v, n);
	if (!strcmp(mode, "swapends") && n > 1)
	{
		t = v[0];
		v[0] = v[n - 1];
		v[n - 1] = t;
	}
	if (!strcmp(mode, "pairs"))
		for (int i = 0; i + 1 < n; i += 2)
		{
			t = v[i];
			v[i] = v[i + 1];
			v[i + 1] = t;
		}
	if (!strcmp(mode, "reverse"))
		for (int i = 0; i < n / 2; i++)
		{
			t = v[i];
			v[i] = v[n - 1 - i];
			v[n - 1 - i] = t;
		}
	if (n > 2 && (near || !strcmp(mode, "medium")))
		while ((double)mistakes(v, n) / total < (near ? 0.05 : 0.30))
			for (int k = 0; k < (near ? n / 10 + 1 : 1); k++)
			{
				int i = rnd() % n;
				int j = near ? i + 1 + (int)(rnd() % 5) : (int)(rnd() % n);
				if (j >= n)
					j = n - 1;
				t = v[i];
				v[i] = v[j];
				v[j] = t;
			}
	for (int i = 0; i < n; i++)
		printf(i ? " %ld" : "%ld", v[i]);
	printf("\n");
	return (0);
}

/* perms <n>: every permutation of 1..n */
static int	cmd_perms(int n)
{
	int	p[16];
	int	i;
	int	j;
	int	t;

	for (i = 0; i < n; i++)
		p[i] = i + 1;
	while (1)
	{
		for (i = 0; i < n; i++)
			printf(i ? " %d" : "%d", p[i]);
		printf("\n");
		i = n - 2;
		while (i >= 0 && p[i] >= p[i + 1])
			i--;
		if (i < 0)
			return (0);
		j = n - 1;
		while (p[j] <= p[i])
			j--;
		t = p[i];
		p[i] = p[j];
		p[j] = t;
		for (int a = i + 1, b = n - 1; a < b; a++, b--)
		{
			t = p[a];
			p[a] = p[b];
			p[b] = t;
		}
	}
}

/* gen <seed> <n> <k>: the numbers, then k random operations, then
   operations that sort them (the whole sequence must give OK) */
static int	cmd_gen(unsigned long long seed, int n, int k)
{
	long	*v;
	int		pushed = 0;
	int		mi;
	int		op;

	g_s ^= seed * 0x9E3779B97F4A7C15ULL;
	if (!g_s)
		g_s = 1;
	v = random_values(n, 1000);
	for (int i = 0; i < n; i++)
		printf(i ? " %ld" : "%ld", v[i]);
	printf("\n");
	init(n, v);
	for (int i = 0; i < k; i++)
	{
		op = rnd() % 11;
		puts(g_ops[op]);
		apply(op);
	}
	while (g_nb)
	{
		puts("pa");
		apply(3);
	}
	while (g_na > 0)
	{
		mi = 0;
		for (int i = 0; i < g_na; i++)
			if (g_a[i] < g_a[mi])
				mi = i;
		if (mi <= g_na / 2)
			while (mi-- > 0)
			{
				puts("ra");
				apply(5);
			}
		else
			for (int r = g_na - mi; r > 0; r--)
			{
				puts("rra");
				apply(8);
			}
		puts("pb");
		apply(4);
		pushed++;
	}
	while (pushed-- > 0)
	{
		puts("pa");
		apply(3);
	}
	return (0);
}

int	main(int argc, char **argv)
{
	if (argc >= 2 && !strcmp(argv[1], "check"))
		return (cmd_check(argc - 2, argv + 2));
	if (argc >= 2 && !strcmp(argv[1], "disorder"))
		return (cmd_disorder(argc - 2, argv + 2));
	if (argc == 5 && !strcmp(argv[1], "rand"))
		return (cmd_rand(strtoull(argv[2], NULL, 10), atoi(argv[3]), argv[4]));
	if (argc == 3 && !strcmp(argv[1], "perms"))
		return (cmd_perms(atoi(argv[2])));
	if (argc == 5 && !strcmp(argv[1], "gen"))
		return (cmd_gen(strtoull(argv[2], NULL, 10), atoi(argv[3]), atoi(argv[4])));
	return (1);
}
EOF
if ! cc -O2 -w "$TMP/pscheck.c" -o "$TMP/pscheck" 2> "$TMP/err"; then
	echo "Internal error: the tester's checker does not compile: $(first_error "$TMP/err")" >&2
	exit 1
fi
PSCHECK="$TMP/pscheck"
for n in 3 4 5 6; do "$PSCHECK" perms $n > "$TMP/perms$n"; done

# ----------------------------- Execution tools ------------------------------ #
# Short display of an argument list
qargs() {
	local a s=""
	for a in "$@"; do
		if [ -z "$a" ] || [[ $a == *[[:space:]]* ]]; then s+="\"$a\" "; else s+="$a "; fi
	done
	s=${s% }
	[ ${#s} -gt 70 ] && s="${s:0:55}… ($# arguments)"
	printf '%s' "$s"
}

# Content of a file, on one line
show_file() {
	if [ ! -s "$1" ]; then printf '(nothing)'
	else printf '"%s"' "$(awk 'BEGIN { ORS = "\\n" } { print }' "$1" | head -c 70)"; fi
}

# Saves a big failing input, so you can replay it → SAVED (file name)
# (not called in $(...): the counter must survive)
N_SAVED=0
save_args() {
	N_SAVED=$((N_SAVED + 1))
	SAVED="/tmp/push_swap_ko_$N_SAVED.txt"
	printf '%s ' "$@" > "$SAVED"
}

user_frame() {
	grep -E "^[[:space:]]+#[0-9]+ .* in [^ ]+ $BUILD/" | head -1 \
		| sed -E "s|.* in ([^ ]+) $BUILD/([^ ]+).*|\2 (\1)|"
}

# One-line summary of the AddressSanitizer reports
asan_summary() {
	local f type loc
	f=$(cat "$@")
	if grep -q "ERROR: AddressSanitizer" <<< "$f"; then
		type=$(grep -m1 -oE "ERROR: AddressSanitizer: [a-zA-Z_-]+" <<< "$f" | awk '{print $3}')
		loc=$(sed -n '/ERROR: AddressSanitizer/,/^$/p' <<< "$f" | user_frame)
		printf 'memory error (%s)%s' "$type" "${loc:+ in $loc}"
	elif grep -q "ERROR: LeakSanitizer" <<< "$f"; then
		loc=$(sed -n '/leak of/,/^$/p' <<< "$f" | user_frame)
		printf 'memory leak: %s%s' "$(grep -m1 -oE '[0-9]+ byte\(s\) leaked in [0-9]+ allocation\(s\)' <<< "$f")" \
			"${loc:+, malloc in $loc}"
	fi
}

# run <stdin file> <program> <args...> → RC, $TMP/out, $TMP/err, MEM
# (10 s of CPU at most: ulimit is much faster than timeout)
run() {
	local in=$1 bin=$2
	shift 2
	( ulimit -t 10; exec "$bin" "$@" ) < "$in" > "$TMP/out" 2> "$TMP/err"
	RC=$?
	MEM=""
	if compgen -G "$TMP/asanlog/log.*" > /dev/null; then
		MEM=$(asan_summary "$TMP"/asanlog/log.*)
		rm -f "$TMP"/asanlog/log.*
	fi
}

# Results of one test line
t_begin() { T_FAILS=(); T_N=0; T_MEM=""; T_INFO=""; }
t_fail() { T_FAILS+=("$1"); }
t_mem() { [ -z "$T_MEM" ] && [ -n "$MEM" ] && T_MEM="$MEM (with: $1)"; }
t_ok() { [ ${#T_FAILS[@]} -eq 0 ] && [ -z "$T_MEM" ]; }
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
	# (not twice when a failure already shows this memory error)
	if [ -n "$T_MEM" ] && ! printf '%s\n' "${T_FAILS[@]}" | grep -qF -- "${T_MEM% (with: *}"; then
		msg "$T_MEM"
	fi
	[ -n "$T_INFO" ] && note "$T_INFO"
}

# Checks for a crash / timeout; returns 0 (true) if the program did not finish cleanly
crashed() {
	if [ $RC -eq 152 ] || [ $RC -eq 137 ]; then t_fail "$1: infinite loop or too slow (more than 10 s)"; return 0; fi
	if [ $RC -ge 128 ]; then t_fail "$1: crash (signal $((RC - 128)))"; return 0; fi
	if [ -n "$MEM" ] && grep -q "memory error" <<< "$MEM"; then t_fail "$1: $MEM"; return 0; fi
	return 1
}

# sort_check <option or ""> <numbers...>: runs push_swap and checks the sort
# → NOPS (number of operations), CNTS (count per operation), returns 0 if sorted
sort_check() {
	local f=$1 cmd res st pre=()
	shift
	[ -n "$f" ] && pre=("$f")
	run /dev/null "$PS" "${pre[@]}" "$@"
	T_N=$((T_N + 1))
	if [ -z "$MEM" ] && [ $RC -lt 128 ] && [ ! -s "$TMP/err" ]; then
		res=$("$PSCHECK" check "$@" < "$TMP/out")
		read -r st NOPS CNTS <<< "$res"
		[ "$st" = OK ] && return 0
	fi
	cmd="./push_swap ${f:+$f }$(qargs "$@")"
	t_mem "$cmd"
	crashed "$cmd" && return 1
	if [ -s "$TMP/err" ]; then
		t_fail "$cmd: writes $(show_file "$TMP/err") on stderr"
		return 1
	fi
	res=$("$PSCHECK" check "$@" < "$TMP/out")
	read -r st NOPS CNTS <<< "$res"
	case $res in
		OK*) return 0 ;;
		KO*) res="the stack is not sorted after your $NOPS operations" ;;
		*) res="invalid output, line ${res#ERR }" ;;
	esac
	if [ $# -gt 12 ]; then
		save_args "$@"
		t_fail "$cmd: $res (replay with: ARG=\$(cat $SAVED); ./push_swap ${f:+$f }\$ARG)"
	else
		t_fail "$cmd: $res"
	fi
	return 1
}

# expect_error <args...>: nothing on stdout, "Error\n" on stderr
expect_error() {
	local cmd="./push_swap $(qargs "$@")"
	run /dev/null "$PS" "$@"
	T_N=$((T_N + 1))
	t_mem "$cmd"
	crashed "$cmd" && return
	if [ -s "$TMP/out" ] || ! printf 'Error\n' | cmp -s - "$TMP/err"; then
		t_fail "$cmd → stdout $(show_file "$TMP/out"), stderr $(show_file "$TMP/err"); expected: \"Error\\n\" on stderr only"
	fi
}

copy_repo() { mkdir -p "$1" && tar -C "$DIR" --exclude=.git -cf - . | tar -C "$1" -xf -; }
has_rule() { grep -qE "^$1[[:space:]]*:" "$DIR/Makefile" 2>/dev/null; }
relinks() { grep -qE '(^|[[:space:]/])(cc|gcc|clang|ar)[[:space:]]' <<< "$1"; }

# Builds <binary> in <folder> with AddressSanitizer if possible
# build_bin <folder> <make target> <binary> → BIN (empty on failure), BIN_SAN=1 with ASan
build_bin() {
	BIN=""; BIN_SAN=0
	copy_repo "$1"
	make -C "$1" fclean > /dev/null 2>&1
	if [ -n "$SAN" ] && make -C "$1" $2 CC="cc $SAN -g" > "$1.log" 2>&1 && [ -x "$1/$3" ] \
		&& nm "$1/$3" 2>/dev/null | grep -q __asan_init; then
		BIN="$1/$3"; BIN_SAN=1
		return 0
	fi
	make -C "$1" fclean > /dev/null 2>&1
	make -C "$1" $2 > "$1.log" 2>&1 && [ -x "$1/$3" ] && BIN="$1/$3"
	[ -n "$BIN" ]
}

# ================================== Start =================================== #
SAN="-fsanitize=address"
echo 'int main(void){return 0;}' > "$TMP/probe.c"
if ! cc $SAN "$TMP/probe.c" -o "$TMP/probe" 2>/dev/null || ! "$TMP/probe" 2>/dev/null; then
	SAN=""
	printf "${Y}AddressSanitizer unavailable: leaks and buffer overflows will not be detected.${N}\n"
fi
export ASAN_OPTIONS="detect_leaks=1:log_path=$TMP/asanlog/log"

# --------------------------------- Makefile --------------------------------- #
# "Normal" build (without ASan): used by the Makefile and Submission checks
copy_repo "$TMP/mk"
mk() { make -C "$TMP/mk" "$@" 2>&1; }
mk fclean > /dev/null
MK_OUT=$(mk); MK_RC=$?
PLAIN_OK=0
if [ $MK_RC -eq 0 ] && [ -x "$TMP/mk/push_swap" ]; then
	PLAIN_OK=1
	cp "$TMP/mk/push_swap" "$TMP/ps_plain"
	find "$TMP/mk" -name '*.o' -exec nm {} + > "$TMP/objs.nm" 2> /dev/null
fi

if wanted makefile; then
	section "Makefile"
	if [ $PLAIN_OK -eq 1 ]; then
		line_ok "make"
		grep -qE '(^|[[:space:]])(gcc|clang)[[:space:]]' <<< "$MK_OUT" && CC_BAD=1
		if relinks "$(mk)"; then line_ko "relink"; msg "a 2nd 'make' rebuilds although nothing changed"
		else line_ok "relink"; fi
		mk clean > /dev/null
		if [ -n "$(find "$TMP/mk" -name '*.o')" ] || [ ! -x "$TMP/mk/push_swap" ]; then
			line_ko "make clean"; msg "must delete every .o (libft included) and keep push_swap"
		else line_ok "make clean"; fi
		mk fclean > /dev/null
		if [ -e "$TMP/mk/push_swap" ]; then line_ko "make fclean"; msg "push_swap is not deleted"
		else line_ok "make fclean"; fi
		if mk re > /dev/null && [ -x "$TMP/mk/push_swap" ]; then line_ok "make re"
		else line_ko "make re"; fi
		if has_rule bonus; then
			out=$(mk bonus)
			if [ $? -eq 0 ] && [ -x "$TMP/mk/checker" ]; then
				line_ok "make bonus"
				cp "$TMP/mk/checker" "$TMP/ck_plain"
				if relinks "$(mk bonus)"; then line_ko "relink bonus"; msg "a 2nd 'make bonus' rebuilds although nothing changed"
				else line_ok "relink bonus"; fi
			else
				line_ko "make bonus"
				if [ -x "$TMP/mk/checker" ]; then msg "$(grep -m1 -E 'error|\*\*\*' <<< "$out" | sed -E 's|^/[^ ]*/||' | cut -c1-150)"
				else msg "make bonus must create the checker program at the root"; fi
			fi
		fi
	else
		line_ko "make"
		grep -E 'error:|undefined reference|No rule|^make.*\*\*\*' <<< "$MK_OUT" | head -3 \
			| sed -E 's|^/[^ ]*/||' | cut -c1-150 | while IFS= read -r m; do msg "$m"; done
		[ $MK_RC -eq 0 ] && msg "make does not create the push_swap program at the root"
	fi
	m=()
	for r in all clean fclean re; do
		grep -qE "^$r[[:space:]]*:" "$DIR/Makefile" || m+=("$r")
	done
	grep -qE '^\$[({]NAME[)}][[:space:]]*:' "$DIR/Makefile" || m+=('$(NAME)')
	if [ ${#m[@]} -eq 0 ]; then line_ok "rules"
	else line_ko "rules"; msg "missing rule(s): ${m[*]}"; fi
	flags=""
	for fl in -Wall -Wextra -Werror; do grep -q -- "$fl" "$DIR/Makefile" || flags+="$fl "; done
	if [ -z "$flags" ] && [ -z "$CC_BAD" ]; then line_ok "flags"
	else
		line_ko "flags"
		[ -n "$flags" ] && msg "missing flags: $flags"
		[ -n "$CC_BAD" ] && msg "the subject requires cc (not gcc / clang)"
	fi
fi

# -------------------------------- Submission -------------------------------- #
if wanted submission; then
	section "Submission"
	if [ -f "$DIR/README.md" ]; then
		m=(); miss=""
		first=$(head -1 "$DIR/README.md" | tr -d '\r')
		# the README may be written in the campus language (allowed by the subject):
		# " et " and "Ressources" are the French spellings
		if ! grep -qE '^[*_]This project has been created as part of the 42 curriculum by .+[*_][[:space:]]*$' <<< "$first"; then
			m+=("first line must be in italics: *This project has been created as part of the 42 curriculum by <login1>, <login2>.*")
		elif ! grep -qE 'by [^,]+(,| and | et ).+' <<< "$first"; then
			m+=("2-person project: the first line must name both logins (by <login1>, <login2>)")
		fi
		for s in Description Instructions 'Resources|Ressources'; do
			grep -qiE "^#+.*($s)" "$DIR/README.md" || miss+="${s%%|*} "
		done
		[ -n "$miss" ] && m+=("missing section(s): $miss")
		if [ ${#m[@]} -eq 0 ]; then line_ok "README.md"
		else line_ko "README.md"; for s in "${m[@]}"; do msg "$s"; done; fi
	else
		line_ko "README.md"; msg "README.md missing (mandatory)"
	fi
	if [ $PLAIN_OK -eq 1 ]; then
		bins=("$TMP/ps_plain")
		[ -x "$TMP/ck_plain" ] && bins+=("$TMP/ck_plain")
		bad=$(nm -u "${bins[@]}" 2>/dev/null | awk '$1 == "U" {print $2}' | sed 's/@.*//' | sort -u \
			| grep -vxE 'read|write|malloc|free|exit|__libc_start_main|__stack_chk_fail|__cxa_finalize' | tr '\n' ' ')
		if [ -z "$bad" ]; then line_ok "allowed functions" "(read write malloc free exit)"
		else line_ko "allowed functions"; msg "forbidden external function(s): $bad"; fi
		glob=$(awk '$2 ~ /^[BCDGS]$/ {print $3}' "$TMP/objs.nm" | sort -u | tr '\n' ' ')
		if [ -z "$glob" ]; then line_ok "global variables"
		else line_ko "global variables"; msg "forbidden global variables: $glob"; fi
	else
		line_skip "allowed functions" "make failed"
	fi
	if command -v norminette > /dev/null 2>&1; then
		nerr=$(cd "$DIR" && norminette 2>&1 | grep -E ': Error!' | sed -E 's/: Error!//' | tr '\n' ' ')
		if [ -z "$nerr" ]; then line_ok "norminette"
		else line_ko "norminette"; msg "errors in: $nerr"; fi
	else
		line_skip "norminette" "not installed"
	fi
fi

# ------------------------ Build for the tests (ASan) ------------------------ #
PS=""
if wanted errors || wanted sort || wanted perf || wanted bench; then
	if build_bin "$TMP/asan" "" push_swap; then
		PS=$BIN; BUILD="$TMP/asan"
		if [ $BIN_SAN -eq 0 ] && [ -n "$SAN" ]; then
			printf "\n${Y}AddressSanitizer not applied (your Makefile does not use \$(CC) everywhere): leaks will not be detected.${N}\n"
		fi
	else
		section "Tests"
		line_ko "push_swap"; msg "push_swap does not compile: $(first_error "$TMP/asan.log")"
	fi
fi

# ------------------------------ Error handling ------------------------------ #
if [ -n "$PS" ] && wanted errors; then
	section "Error handling"
	t_begin
	run /dev/null "$PS"
	T_N=1
	t_mem "./push_swap"
	if ! crashed "./push_swap" && { [ -s "$TMP/out" ] || [ -s "$TMP/err" ]; }; then
		t_fail "./push_swap (no argument) → stdout $(show_file "$TMP/out"), stderr $(show_file "$TMP/err"); expected: nothing"
	fi
	t_end "no argument"

	t_begin
	for c in '1 a 3' '1 2a 3' 'abc' '-' '+' '1 - 3' '--5' '1 +-2' '1.5 2' '0x1 2' '"" 1' '1 ""' \
		'"1 2" a' '--adaptive 0 one 2 3' '--simple 4 2 x' '1-2 3' '5+ 1' '++5 1' '-+5 1' '1e3 2' \
		'2147483647a 1' '1 2 3 4 5 6 7 8 9 x' 'x 1 2 3 4 5 6 7 8 9'; do
		eval "set -- $c"
		expect_error "$@"
	done
	# the error is only at the very end of a big input
	set -- $("$PSCHECK" rand 41 500 random)
	expect_error "$@" 12abc
	t_end "not integers"

	t_begin
	for c in '2147483648' '-2147483649' '1 2147483648 3' '4294967296' '-4294967296 1' \
		'99999999999999999999' '1 -99999999999999999999' '9223372036854775808' '+2147483648 1' \
		'4294967297 2' '18446744073709551617 2' '-9223372036854775809 1' '12345678901 1' \
		'00000000002147483648 1' '-2147483648 2147483647 2147483648'; do
		eval "set -- $c"
		expect_error "$@"
	done
	set -- $("$PSCHECK" rand 42 500 random)
	expect_error "$@" 2147483648
	t_end "int overflow"

	t_begin
	for c in '1 2 1' '3 2 3' '--simple 3 2 3' '5 5' '-1 0 -1' '1 +1' '42 042' '2147483647 1 2147483647' \
		'0 -0' '-0 +0' '0 00' '-01 -1' '-2147483648 5 -2147483648' '1 2 3 4 5 6 7 8 9 1'; do
		eval "set -- $c"
		expect_error "$@"
	done
	# the duplicate is the last number of a big input
	set -- $("$PSCHECK" rand 43 500 random)
	expect_error "$@" "$1"
	set -- $("$PSCHECK" rand 44 500 extreme)
	expect_error "$@" -2147483648
	t_end "duplicates"

	t_begin
	sort_check "" 2147483647 -2147483648 0
	sort_check "" -2147483648 2147483647
	sort_check "" -1 -5 -3
	sort_check "" 0 -1
	sort_check "" 2147483647 -2147483648 2147483646 -2147483647 0
	sort_check "" -2147483648 2147483647 -1 1 0 2147483646
	for s in 1 2 3; do
		sort_check "" $("$PSCHECK" rand $((50 + s)) $((s * 7)) extreme)
	done
	t_end "int limits"
fi

# ----------------------------------- Sort ----------------------------------- #
STRAT_FLAGS=("" --simple --medium --complex --adaptive)
STRAT_LABEL=("no option" --simple --medium --complex --adaptive)

if [ -n "$PS" ] && wanted sort; then
	section "Sorting (checked by the tester's own checker)"
	for i in "${!STRAT_FLAGS[@]}"; do
		f=${STRAT_FLAGS[$i]}
		t_begin
		o100=""; o500=""
		sort_check "$f" 42
		[ $i -eq 0 ] && t_ok && [ "$NOPS" != 0 ] && t_fail "./push_swap 42: a single number, must not print anything"
		sort_check "$f" 1 2
		sort_check "$f" 2 1
		for n in 3 4 5; do
			while read -r l; do sort_check "$f" $l; done < "$TMP/perms$n"
		done
		sort_check "$f" -2147483648 0 2147483647
		sort_check "$f" -1 -2 -3 -4 -5
		[ $i -eq 0 ] && while read -r l; do sort_check "$f" $l; done < "$TMP/perms6"
		for spec in "1 6 random" "2 10 random" "3 20 random" "4 50 random" "5 100 random" "6 500 random" \
			"7 100 sorted" "8 500 sorted" "9 100 reverse" "10 500 reverse" "11 100 nearly" \
			"12 500 nearly" "13 100 medium" "14 500 medium" \
			"61 7 random" "62 8 random" "63 11 random" "64 16 random" "65 33 random" "66 64 random" \
			"67 99 random" "68 101 random" "69 128 random" "70 255 random" "71 256 random" \
			"72 499 random" "73 501 random" "74 1000 random" "75 5 extreme" "76 100 extreme" \
			"77 500 extreme" "78 6 rotated" "79 100 rotated" "80 500 rotated" "81 100 swapends" \
			"82 500 swapends" "83 100 pairs" "84 500 pairs" "85 7 reverse" "86 6 sorted"; do
			set -- $spec
			# (an O(n²) strategy may be too slow on 1000 numbers under ASan)
			[ "$f" = --simple ] && [ "$2" -gt 501 ] && continue
			if sort_check "$f" $("$PSCHECK" rand "$1" "$2" "$3"); then
				[ "$3" = random ] && [ "$2" = 100 ] && { o100=$NOPS; cp "$TMP/out" "$TMP/o_${i}_100"; }
				[ "$3" = random ] && [ "$2" = 500 ] && o500=$NOPS
				if [ "$3" = sorted ] && [ "$NOPS" != 0 ] && { [ $i -eq 0 ] || [ $i -eq 4 ]; }; then
					t_fail "${f:-no option}, $2 numbers already sorted: must not print anything (prints $NOPS operations)"
				fi
			fi
		done
		for l in "1 2" "1 2 3" "1 2 3 4 5" "-2147483648 2147483647" "-3 -2 -1 0 1 2"; do
			if [ $i -eq 0 ] || [ $i -eq 4 ]; then
				sort_check "$f" $l && [ "$NOPS" != 0 ] \
					&& t_fail "./push_swap ${f:+$f }$l: already sorted, must not print anything (prints $NOPS operations)"
			fi
		done
		T_INFO="($T_N tests)${o100:+ 100 numbers → $o100 ops}${o500:+, 500 → $o500 ops}"
		t_end "${STRAT_LABEL[$i]}"
	done
	# no option = --adaptive; are the 4 strategies really different?
	if [ -f "$TMP/o_0_100" ] && [ -f "$TMP/o_4_100" ] && ! cmp -s "$TMP/o_0_100" "$TMP/o_4_100"; then
		line_warn "default = --adaptive" "with no option, the output differs from --adaptive (subject: --adaptive by default)"
	fi
	if [ -f "$TMP/o_1_100" ] && [ -f "$TMP/o_2_100" ] && [ -f "$TMP/o_3_100" ] && [ -f "$TMP/o_4_100" ] \
		&& cmp -s "$TMP/o_1_100" "$TMP/o_2_100" && cmp -s "$TMP/o_2_100" "$TMP/o_3_100"; then
		line_warn "4 strategies" "--simple, --medium and --complex give exactly the same operations"
	fi
fi

# ------------------------------- Performance -------------------------------- #
if [ -n "$PS" ] && wanted perf; then
	section "Number of operations (no option)"
	for n in 3 5; do
		t_begin; max=0
		while read -r l; do
			sort_check "" $l && [ "$NOPS" -gt $max ] && max=$NOPS
		done < "$TMP/perms$n"
		lim=3; [ $n -eq 5 ] && lim=12
		if ! t_ok; then t_end "$n numbers"
		elif [ $max -le $lim ]; then line_ok "$n numbers" "(max $max operations, all permutations)"
		else line_warn "$n numbers" "max $max operations (an optimized solution needs at most $lim)"; fi
	done
	for n in 100 500; do
		if [ $n -eq 100 ]; then t1=700; t2=1500; t3=2000; else t1=5500; t2=8000; t3=12000; fi
		t_begin; max=0; sum=0; cnt=0
		for s in 1 2 3 4 5 6 7 8 9 10; do
			if sort_check "" $("$PSCHECK" rand $((n + s)) $n random); then
				sum=$((sum + NOPS)); cnt=$((cnt + 1))
				[ "$NOPS" -gt $max ] && max=$NOPS
			fi
		done
		if ! t_ok; then t_end "$n numbers"; continue; fi
		avg=$((sum / cnt))
		if [ $max -lt $t1 ]; then line_ok "$n numbers" "avg $avg, max $max over 10 runs: excellent (< $t1)"
		elif [ $max -lt $t2 ]; then line_ok "$n numbers" "avg $avg, max $max over 10 runs: good (< $t2)"
		elif [ $max -lt $t3 ]; then line_ok "$n numbers" "avg $avg, max $max over 10 runs: enough (< $t3)"
		else line_ko "$n numbers"; msg "avg $avg, max $max over 10 runs: you need fewer than $t3 operations to pass"; fi
	done
fi

# ------------------------------- --bench mode ------------------------------- #
# bench_run <strategy option or ""> <numbers...>: tries --bench before, then
# after the strategy option → 0 if the sort is correct
bench_run() {
	local f=$1
	shift
	if [ -n "$f" ]; then
		sort_check_quiet --bench "$f" "$@" || sort_check_quiet "$f" --bench "$@"
	else
		sort_check_quiet --bench "$@"
	fi
}
sort_check_quiet() {
	local pre=()
	while [[ $1 == --* ]]; do pre+=("$1"); shift; done
	run /dev/null "$PS" "${pre[@]}" "$@"
	BCMD="./push_swap ${pre[*]} $(qargs "$@")"
	t_mem "$BCMD"
	[ $RC -lt 128 ] || return 1
	RES=$("$PSCHECK" check "$@" < "$TMP/out")
	read -r _ NOPS CNTS <<< "$RES"
	[[ $RES == OK* ]] && [ -s "$TMP/err" ]
}

if [ -n "$PS" ] && wanted bench; then
	section "--bench mode"
	t_begin
	OPS=(sa sb ss pa pb ra rb rr rra rrb rrr)
	ARGS=$("$PSCHECK" rand 77 100 random)
	read -r DIS_R DIS_T <<< "$("$PSCHECK" disorder $ARGS)"
	# ("racine" = French for "root": your --bench output may be in French)
	declare -A CLASS_RE=([--simple]='n²|n\^ ?2|n2|n ?\* ?n|quadrat' \
		[--medium]='√|sqrt|racine|n\^ ?1\.5|n1\.5|3/2' [--complex]='log')
	t1=(); t2=(); t3=(); t4=(); w1=(); w2=()
	for f in "" --simple --medium --complex --adaptive; do
		name=${f:-no option}
		if ! bench_run "$f" $ARGS; then
			if [ $RC -ge 128 ] || grep -q "memory error" <<< "$MEM"; then t1+=("$BCMD: crash ${MEM:+($MEM)}")
			elif printf 'Error\n' | cmp -s - "$TMP/err"; then t1+=("$BCMD: prints Error (--bench option not handled?)")
			elif [[ $RES == OK* ]]; then t1+=("--bench ${f:+$f }: nothing is written on stderr")
			elif [[ $RES == KO* ]]; then t1+=("$BCMD: the stack is not sorted after the $NOPS operations")
			else t1+=("$BCMD: invalid output, line ${RES#ERR }"); fi
			continue
		fi
		cp "$TMP/err" "$TMP/bench_$name"
		err=$(cat "$TMP/err")
		# disorder in %, with 2 decimals
		re_r="${DIS_R%.*}[.,]${DIS_R#*.}"; re_t="${DIS_T%.*}[.,]${DIS_T#*.}"
		grep -qE "(^|[^0-9])($re_r|$re_t)[[:space:]]*%" <<< "$err" \
			|| t2+=("--bench ${f:+$f }: expected disorder $DIS_R% (2 decimals + %), not found on stderr")
		# total number of operations + each type of operation
		grep -qE "(^|[^0-9])$NOPS([^0-9]|$)" <<< "$err" \
			|| t3+=("--bench ${f:+$f }: total number of operations ($NOPS) not found on stderr")
		miss=""; bad=""
		read -r -a C <<< "$CNTS"
		for k in "${!OPS[@]}"; do
			op=${OPS[$k]}
			if ! grep -qE "(^|[^a-z])$op([^a-z]|$)" <<< "$err"; then miss+="$op "
			elif ! grep -qE "(^|[^a-z])$op[^a-z0-9]{0,12}${C[$k]}([^0-9]|$)" <<< "$err"; then bad+="$op=${C[$k]} "; fi
		done
		[ -n "$miss" ] && t3+=("--bench ${f:+$f }: operation(s) missing from the breakdown: $miss")
		[ -n "$bad" ] && w1+=("${f:-no option}: expected count $bad")
		# strategy + complexity class
		if ! grep -q "O(" <<< "$err"; then
			t4+=("--bench ${f:+$f }: the complexity class (e.g. O(n log n)) is not found on stderr")
		elif [ -n "$f" ] && [ -n "${CLASS_RE[$f]}" ] && ! grep -qiE "O\(.*(${CLASS_RE[$f]})" <<< "$err"; then
			w2+=("$f: the printed complexity does not look like the expected one")
		fi
	done
	# --bench on an already sorted input
	sort_check_quiet --bench 1 2 3 4 5
	if [ -s "$TMP/err" ] && ! grep -qE '0[.,]00[[:space:]]*%' "$TMP/err"; then
		t2+=("./push_swap --bench 1 2 3 4 5: expected disorder 0.00%")
	fi
	# without --bench: nothing on stderr (already checked in the Sorting part)
	[ -n "$T_MEM" ] && t1+=("$T_MEM")
	for t in 1 2 3 4; do
		case $t in
			1) lab="sort + stderr"; arr=("${t1[@]}") ;;
			2) lab="disorder (%)"; arr=("${t2[@]}") ;;
			3) lab="operations"; arr=("${t3[@]}") ;;
			4) lab="strategy"; arr=("${t4[@]}") ;;
		esac
		if [ ${#arr[@]} -eq 0 ]; then line_ok "$lab"
		else line_ko "$lab"; for m in "${arr[@]}"; do msg "$m"; done; fi
	done
	if [ ${#w1[@]} -gt 0 ]; then
		line_warn "count per operation" "numbers not found next to the names (free format?)"
		for m in "${w1[@]:0:3}"; do note "$m"; done
	fi
	if [ ${#w2[@]} -gt 0 ]; then
		line_warn "classes" "check them by hand"
		for m in "${w2[@]}"; do note "$m"; done
	fi
	if [ -f "$TMP/bench_no option" ]; then
		printf "      ${D}example (./push_swap --bench <100 numbers>, actual disorder %s%%):${N}\n" "$DIS_R"
		head -8 "$TMP/bench_no option" | cut -c1-100 | while IFS= read -r l; do printf "        ${D}%s${N}\n" "$l"; done
	fi
fi

# ------------------------------ Bonus: checker ------------------------------ #
# ck_expect <expected OK|KO|Error|nothing> <stdin description> <stdin file> <args...>
ck_expect() {
	local exp=$1 lab=$2 in=$3 cmd want_out="" want_err=""
	shift 3
	cmd="./checker $(qargs "$@") with $lab"
	run "$in" "$CK" "$@"
	T_N=$((T_N + 1))
	t_mem "$cmd"
	crashed "$cmd" && return
	case $exp in
		OK|KO) want_out="$exp\n"; exp="\"$exp\\n\" on stdout" ;;
		Error) want_err='Error\n'; exp='"Error\n" on stderr' ;;
	esac
	if ! printf "$want_out" | cmp -s - "$TMP/out" || ! printf "$want_err" | cmp -s - "$TMP/err"; then
		t_fail "$cmd → stdout $(show_file "$TMP/out"), stderr $(show_file "$TMP/err"); expected: $exp"
	fi
}

if wanted bonus; then
	section "Bonus: checker"
	if ! has_rule bonus; then
		line_skip "checker" "no bonus rule in the Makefile"
	elif ! build_bin "$TMP/bonus" bonus checker; then
		line_ko "make bonus"
		if [ -x "$TMP/bonus/checker" ] || grep -qE 'error|\*\*\*' "$TMP/bonus.log"; then msg "$(first_error "$TMP/bonus.log")"
		else msg "make bonus must create the checker program at the root"; fi
	else
		CK=$BIN; BUILD="$TMP/bonus"
		[ -z "$PS" ] && [ -x "$TMP/bonus/push_swap" ] && PS="$TMP/bonus/push_swap"
		ops() { printf "$1" > "$TMP/in"; }

		t_begin
		ops 'rra\npb\nsa\nrra\npa\n'; ck_expect OK '"rra pb sa rra pa"' "$TMP/in" 3 2 1 0
		ops 'sa\nrra\npb\n'; ck_expect KO '"sa rra pb"' "$TMP/in" 3 2 1 0
		ck_expect OK "no operation" /dev/null 1 2 3
		ck_expect KO "no operation" /dev/null 2 1 3
		ck_expect OK "no operation" /dev/null 42
		ops 'pb\n'; ck_expect KO '"pb" (b not empty)' "$TMP/in" 1 2 3
		ops 'pb\npa\n'; ck_expect OK '"pb pa"' "$TMP/in" 1 2 3
		ops 'sa\n'; ck_expect OK '"sa"' "$TMP/in" 2 1 3
		ops 'ra\n'; ck_expect OK '"ra"' "$TMP/in" 3 1 2
		ops 'rra\n'; ck_expect OK '"rra"' "$TMP/in" 2 3 1
		ops 'pb\npb\nss\npa\npa\n'; ck_expect OK '"pb pb ss pa pa"' "$TMP/in" 2 1 4 3
		ops 'pb\npb\npb\nrr\npa\npa\npa\n'; ck_expect OK '"pb pb pb rr pa pa pa"' "$TMP/in" 2 3 1 6 4 5
		ops 'pb\npb\npb\nrrr\npa\npa\npa\n'; ck_expect OK '"pb pb pb rrr pa pa pa"' "$TMP/in" 3 1 2 5 6 4
		ops 'pb\npb\npb\nrr\npa\npa\npa\n'; ck_expect KO '"pb pb pb rr pa pa pa"' "$TMP/in" 3 1 2 5 6 4
		ops 'sa\npa\n'; ck_expect KO '"sa pa"' "$TMP/in" 1 2 3
		ck_expect OK "no operation" /dev/null -2147483648 0 2147483647
		ck_expect KO "no operation" /dev/null 2147483647 -2147483648
		t_end "OK / KO"

		# operations on an empty or one-element stack do nothing (no crash)
		t_begin
		ops 'pa\nsb\nrb\nrrb\n'; ck_expect OK '"pa sb rb rrb" (b is empty)' "$TMP/in" 1 2 3
		ops 'sa\nra\nrra\nss\nrr\nrrr\n'; ck_expect OK '"sa ra rra ss rr rrr" (a has 1 element, b is empty)' "$TMP/in" 42
		ops 'pb\nsa\nra\nrra\npb\npa\n'; ck_expect OK '"pb sa ra rra pb pa" (a becomes empty)' "$TMP/in" 7
		ops 'pb\nsb\nrb\nrrb\npa\n'; ck_expect OK '"pb sb rb rrb pa" (b has 1 element)' "$TMP/in" 1 2
		ops 'pb\npb\npb\npa\npa\npa\npa\npa\n'; ck_expect OK '"pb pb pb pa pa pa pa pa"' "$TMP/in" 1 2 3
		ops 'pb\npb\n'; ck_expect KO '"pb pb" (a becomes empty, b is not)' "$TMP/in" 2 1
		t_end "empty stacks"

		# many operations: 200000 lines on stdin
		t_begin
		{ echo sa; yes ra | head -n 199998; } > "$TMP/in"
		ck_expect OK '"sa" then "ra" 199998 times' "$TMP/in" 2 1 3
		{ yes pb | head -n 50000; yes pa | head -n 50000; } > "$TMP/in"
		ck_expect OK '"pb" 50000 times then "pa" 50000 times' "$TMP/in" $("$PSCHECK" rand 45 500 sorted)
		{ yes rra | head -n 99999; echo sa; } > "$TMP/in"
		ck_expect KO '"rra" 99999 times then "sa"' "$TMP/in" 1 2 3
		t_end "many operations"

		t_begin
		run /dev/null "$CK"
		T_N=1; t_mem "./checker"
		if ! crashed "./checker" && { [ -s "$TMP/out" ] || [ -s "$TMP/err" ]; }; then
			t_fail "./checker (no argument) → stdout $(show_file "$TMP/out"), stderr $(show_file "$TMP/err"); expected: nothing"
		fi
		t_end "no argument"

		t_begin
		ck_expect Error "no operation" /dev/null 3 2 one 0
		ck_expect Error "no operation" /dev/null "" 1
		ck_expect Error "no operation" /dev/null 1 2 1
		ck_expect Error "no operation" /dev/null 1 2147483648
		ck_expect Error "no operation" /dev/null -2147483649 1
		for o in 'xx' 'sa ' ' sa' 'SA' 'sa\tsb' 'pa pb' 'rrrr' '' 'ra\r' 's' 'r' 'p' 'Ra' 'rr ' 'sasa' 'rrrb'; do
			ops "sa\n$o\n"; ck_expect Error "\"sa\" then \"$o\"" "$TMP/in" 2 1 3
		done
		ck_expect Error "no operation" /dev/null 0 -0
		ck_expect Error "no operation" /dev/null 1 2 3 4 5 6 7 8 9 x
		{ yes ra | head -n 1000; echo rx; } > "$TMP/in"
		ck_expect Error '"ra" 1000 times, then "rx"' "$TMP/in" 3 2 1
		t_end "errors"

		t_begin
		if [ -n "$PS" ]; then
			for spec in "21 3" "22 5" "23 100" "24 500"; do
				set -- $spec
				ARGS=$("$PSCHECK" rand "$1" "$2" random)
				run /dev/null "$PS" $ARGS
				cp "$TMP/out" "$TMP/ps_ops"
				exp=$("$PSCHECK" check $ARGS < "$TMP/ps_ops" | cut -c1-2)
				[ "$exp" = OK ] && ck_expect OK "the output of your push_swap ($2 numbers)" "$TMP/ps_ops" $ARGS
				if [ -s "$TMP/ps_ops" ]; then
					sed '$d' "$TMP/ps_ops" > "$TMP/ps_cut"
					exp=$("$PSCHECK" check $ARGS < "$TMP/ps_cut" | cut -c1-2)
					[ "$exp" = OK ] || [ "$exp" = KO ] && ck_expect "$exp" "the output of your push_swap without its last line" "$TMP/ps_cut" $ARGS
				fi
			done
			t_end "with your push_swap"
		else
			line_skip "with your push_swap" "push_swap not compiled"
		fi

		t_begin
		for s in $(seq 1 30); do
			mapfile -t L < <("$PSCHECK" gen "$s" $((s % 8 + 1)) $((s * 3 % 40)))
			printf '%s\n' "${L[@]:1}" > "$TMP/gen_ops"
			ck_expect OK "$(( ${#L[@]} - 1 )) random operations, then sorted (seed $s)" "$TMP/gen_ops" ${L[0]}
			printf 'sa\nrra\npb\n' >> "$TMP/gen_ops"
			exp=$("$PSCHECK" check ${L[0]} < "$TMP/gen_ops" | cut -c1-2)
			ck_expect "$exp" "the same + \"sa rra pb\"" "$TMP/gen_ops" ${L[0]}
		done
		t_end "the 11 operations"
	fi
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
