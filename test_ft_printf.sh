#!/usr/bin/env bash
# **************************************************************************** #
#  test_ft_printf.sh - single-file ft_printf tester                            #
#                                                                              #
#  Usage (from your ft_printf folder):                                         #
#      bash ../test_ft_printf.sh             -> test everything                #
#      bash ../test_ft_printf.sh d x p       -> test only these conversions    #
#      bash ../test_ft_printf.sh bonus       -> test only the bonus            #
#      (groups: c s p d i u x X % mix fuzz robust                              #
#               | width - 0 . # + space combo bfuzz)                           #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Your libftprintf.a is built with YOUR Makefile (make / make bonus),       #
#    then each conversion is compared to the real printf (output AND return    #
#    value) in a separate program: a crash does not block the rest.            #
#  - Thousands of random formats are compared to the real printf, and the     #
#    tester tries to break ft_printf: malloc() and write() failures, formats   #
#    ending with '%', huge widths, NULL format, ...                            #
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
banner "ft_printf tester" "$DIR"
if [ ! -f "$DIR/Makefile" ] && [ -z "$(find "$DIR" -maxdepth 2 -name ft_printf.h 2>/dev/null)" ]; then
	echo "Error: no Makefile and no ft_printf.h here. Run this script from your ft_printf folder." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_ft_printf.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 20 ? 20 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }
# ("erreur": compiler messages in a French locale)
first_error() { grep -m1 -E "error|erreur|undefined|No rule|\*\*\*" "$1" | sed -E 's|^.*/||; s/^[[:space:]]+//' | cut -c1-150; }

# ------------------------------- Test groups -------------------------------- #
MAND=(c s p d i u x X pct mix fuzz robust)
BONUS=(width minus zero prec hash plus space combo bfuzz)
declare -A LABEL=(
	[c]='%c' [s]='%s' [p]='%p' [d]='%d' [i]='%i' [u]='%u' [x]='%x' [X]='%X'
	[pct]='%%' [mix]='mixed' [fuzz]='random formats' [robust]='robustness'
	[width]='width (e.g. %5d)' [minus]="flag '-'" [zero]="flag '0'" [prec]="precision '.'"
	[hash]="flag '#'" [plus]="flag '+'" [space]="flag ' '" [combo]='combinations'
	[bfuzz]='random flags'
)

# Optional filter passed as arguments
declare -A WANTED=()
for a in "$@"; do
	case $a in
		%|%%|pct) WANTED[pct]=1 ;;
		bonus) for g in "${BONUS[@]}"; do WANTED[$g]=1; done ;;
		mandatory) for g in "${MAND[@]}"; do WANTED[$g]=1; done ;;
		-|minus) WANTED[minus]=1 ;;
		0|zero) WANTED[zero]=1 ;;
		.|prec|precision) WANTED[prec]=1 ;;
		'#'|hash) WANTED[hash]=1 ;;
		+|plus) WANTED[plus]=1 ;;
		' '|space) WANTED[space]=1 ;;
		width) WANTED[width]=1 ;;
		*)
			a=${a#%}
			if [ -n "${LABEL[$a]}" ]; then WANTED[$a]=1
			else
				echo "Unknown group: '$a'. Groups: c s p d i u x X % mix fuzz robust | bonus width - 0 . # + space combo bfuzz" >&2
				exit 1
			fi ;;
	esac
done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# ---------------------- C prelude shared by the tests ----------------------- #
prelude() { cat <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#ifdef __SANITIZE_ADDRESS__
# include <sanitizer/asan_interface.h>
# include <sanitizer/lsan_interface.h>
#endif

int	ft_printf(const char *, ...);

static int			g_ok = 0;
static int			g_ko = 0;
static const char	*g_case = "start of the test";
static int			g_saved = -1;
static FILE			*g_capf = NULL;
static char			g_got[1 << 17];
static char			g_exp[1 << 17];
static char			g_long[1001];
static char			g_big[50001];
static int			g_warn = 0;
static int			g_mfail = 0;
static int			g_mcount = 0;
static const char	*g_fmt = "";

/* rigged malloc: the g_mfail-th call returns NULL (linked with --wrap=malloc) */
void	*__real_malloc(size_t size);
void	*__wrap_malloc(size_t size)
{
	g_mcount++;
	if (g_mfail > 0 && --g_mfail == 0)
		return (NULL);
	return (__real_malloc(size));
}

/* puts stdout back in place (after a capture) */
static void	tst_restore(void)
{
	if (g_saved >= 0)
	{
		dup2(g_saved, 1);
		close(g_saved);
		g_saved = -1;
	}
}

static void	tst_fail(const char *fmt, ...)
{
	va_list	ap;

	g_ko++;
	if (g_ko > 8)
	{
		if (g_ko == 9)
			printf("@@MSG …\n");
		return ;
	}
	printf("@@MSG ");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("\n");
}

/* something to check by hand (not counted as KO) */
static void	tst_warn(const char *fmt, ...)
{
	va_list	ap;

	if (++g_warn > 4)
		return ;
	printf("@@WARN ");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("\n");
}

/* readable display of an n-byte buffer (\0 and special characters) */
static const char	*tst_qn(const char *s, int n)
{
	static char	bufs[4][256];
	static int	k = 0;
	char		*b;
	int			j = 0;

	if (!s)
		return ("NULL");
	b = bufs[k++ % 4];
	b[j++] = '"';
	for (int i = 0; i < n; i++)
	{
		unsigned char c = s[i];
		if (j > 150)
		{
			snprintf(b + j, 256 - j, "…\" (%d chars)", n);
			return (b);
		}
		if (c == '\n')
			j += sprintf(b + j, "\\n");
		else if (c == '\t')
			j += sprintf(b + j, "\\t");
		else if (c == '\0')
			j += sprintf(b + j, "\\0");
		else if (c < 32 || c > 126)
			j += sprintf(b + j, "\\x%02x", c);
		else
			b[j++] = c;
	}
	b[j++] = '"';
	b[j] = 0;
	return (b);
}

/* captures everything written to fd 1 */
static void	tst_begin(void)
{
	fflush(stdout);
	if (!g_capf && !(g_capf = tmpfile()))
	{
		perror("tmpfile");
		exit(1);
	}
	if (ftruncate(fileno(g_capf), 0) != 0)
		perror("ftruncate");
	lseek(fileno(g_capf), 0, SEEK_SET);
	g_saved = dup(1);
	dup2(fileno(g_capf), 1);
}

static int	tst_end(void)
{
	off_t	n;
	ssize_t	r;

	tst_restore();
	n = lseek(fileno(g_capf), 0, SEEK_CUR);
	if (n > (off_t)sizeof(g_got) - 1)
		n = sizeof(g_got) - 1;
	lseek(fileno(g_capf), 0, SEEK_SET);
	r = read(fileno(g_capf), g_got, n);
	return (r < 0 ? 0 : (int)r);
}

static void	tst_cmp(int r1, int n, int r2)
{
	if (r2 > (int)sizeof(g_exp) - 1)
		r2 = sizeof(g_exp) - 1;
	if (n == r2 && !memcmp(g_got, g_exp, n))
	{
		if (r1 == r2)
			g_ok++;
		else
			tst_fail("%s: correct output but returns %d, expected %d", g_case, r1, r2);
	}
	else
	{
		int	k = 0;
		int	st;

		while (k < n && k < r2 && g_got[k] == g_exp[k])
			k++;
		if (k < 60)
		{
			tst_fail("%s → %s (returns %d), expected %s (returns %d)",
				g_case, tst_qn(g_got, n), r1, tst_qn(g_exp, r2), r2);
			return ;
		}
		/* long output: show where it differs */
		st = k - 20;
		tst_fail("%s → %d chars (returns %d), expected %d chars (returns %d); "
			"first difference at char %d: …%s instead of …%s",
			g_case, n, r1, r2, r2, k, tst_qn(g_got + st, n - st < 50 ? n - st : 50),
			tst_qn(g_exp + st, r2 - st < 50 ? r2 - st : 50));
	}
}

#define CASE(d) (g_case = (d))
/* compares ft_printf(...) to the real printf (via snprintf) */
#define TD(desc, ...) do { int tst_r1; int tst_n; CASE(desc); tst_begin(); \
	tst_r1 = ft_printf(__VA_ARGS__); tst_n = tst_end(); \
	tst_cmp(tst_r1, tst_n, snprintf(g_exp, sizeof g_exp, __VA_ARGS__)); } while (0)
#define T(...) TD("ft_printf(" #__VA_ARGS__ ")", __VA_ARGS__)

/* makes each malloc of ft_printf(...) fail in turn: no crash, no leak,
   and (like printf) the return value should be -1 */
static char	g_mdesc[400];
static int	g_mret_warned = 0;
#define TM(desc, ...) do { int tst_cnt; int tst_r; int tst_pre; CASE(desc); \
	tst_begin(); g_mcount = 0; ft_printf(__VA_ARGS__); tst_cnt = g_mcount; tst_end(); \
	tst_pre = tst_has_leak(); \
	for (int tst_k = 1; tst_k <= tst_cnt && tst_k <= 40; tst_k++) { \
		snprintf(g_mdesc, sizeof g_mdesc, "malloc #%d fails in %s", tst_k, desc); \
		CASE(g_mdesc); tst_begin(); g_mfail = tst_k; tst_r = ft_printf(__VA_ARGS__); \
		g_mfail = 0; tst_end(); g_ok++; \
		if (tst_r != -1 && !g_mret_warned++) \
			tst_warn("%s → returns %d (printf returns -1 when malloc fails)", g_mdesc, tst_r); } \
	if (tst_cnt && !tst_pre && tst_has_leak()) \
		tst_fail("memory leak when a malloc fails in %s (details below)", desc); \
	} while (0)
#define TMM(...) TM("ft_printf(" #__VA_ARGS__ ")", __VA_ARGS__)

/* 1 once a leak exists (checked until the first one; the leaks are all
   reported again at exit) */
static int	tst_has_leak(void)
{
	static int	leak = 0;

#ifdef __SANITIZE_ADDRESS__
	if (!leak && __lsan_do_recoverable_leak_check())
		leak = 1;
#endif
	return (leak);
}

/* runs fn() in a child process, stdout on /dev/null (stderr too if quiet):
   returns 0 (finished, *ret = what fn returned), 1 (crash), 2 (infinite loop) */
static int	g_loops = 0;
static int	g_loop_skipped = 0;

static int	tst_child(int (*fn)(void), int quiet, int *ret)
{
	int		p[2];
	int		st;
	int		v = 0;
	pid_t	pid;

	/* after 2 infinite loops, the next cases are skipped (1 s each) */
	if (g_loops >= 2)
	{
		g_loop_skipped++;
		return (3);
	}
	if (pipe(p) != 0 || (pid = fork()) < 0)
	{
		perror("fork");
		exit(1);
	}
	if (pid == 0)
	{
		int	dn = open("/dev/null", O_WRONLY);

		close(p[0]);
		dup2(dn, 1);
		if (quiet)
			dup2(dn, 2);
		alarm(1);
		v = fn();
		if (write(p[1], &v, sizeof v) < 0)
			_exit(1);
		_exit(0);
	}
	close(p[1]);
	waitpid(pid, &st, 0);
	if (read(p[0], &v, sizeof v) != sizeof v)
		v = 0;
	close(p[0]);
	if (WIFSIGNALED(st) && WTERMSIG(st) == SIGALRM)
	{
		g_loops++;
		return (2);
	}
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		return (1);
	*ret = v;
	return (0);
}

static void	tst_on_death(void)
{
	tst_restore();
	if (g_case)
		printf("\n@@CRASH %s\n", g_case);
}

static void	tst_on_signal(int sig)
{
	tst_restore();
	printf("\n@@CRASH %s\n@@SIGNAL %d\n", g_case, sig);
	_exit(128 + sig);
}

static void	tst_run(void);

int	main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	for (int i = 0; i < 1000; i++)
		g_long[i] = 'a' + i % 26;
	for (int i = 0; i < 50000; i++)
		g_big[i] = 'A' + i % 26;
#ifdef __SANITIZE_ADDRESS__
	__asan_set_death_callback(tst_on_death);
#else
	signal(SIGSEGV, tst_on_signal);
	signal(SIGBUS, tst_on_signal);
	signal(SIGABRT, tst_on_signal);
	signal(SIGFPE, tst_on_signal);
#endif
	signal(SIGTERM, tst_on_signal);
	tst_run();
	printf("@@RESULT %d %d\n", g_ok, g_ko);
	g_case = NULL;
	return (0);
}
EOF
}

# ------------------------------- Test bodies -------------------------------- #
body() {
case "$1" in

c) cat <<'EOF'
static void	tst_g_c(void)
{
	char	d[64];

	for (int ch = 32; ch < 127; ch++)
	{
		snprintf(d, sizeof d, "ft_printf(\"%%c\", '%c')", ch);
		TD(d, "%c", ch);
	}
	T("%c", '\n');
	T("%c", '\t');
	T("%c", '\0');
	T("%c", 127);
	T("%c", (char)200);
	T("%c", 'A' + 256);
	T("%c%c%c", 'a', 'b', 'c');
	T(" %c %c %c ", '1', '2', '3');
	T("[%c]", 'x');
	T("%c%c", '\0', 'a');
	T("abc%cdef", '-');
}
EOF
	;;

s) cat <<'EOF'
static void	tst_g_s(void)
{
	T("%s", "hello");
	T("%s", "");
	T("%s", "a");
	T("%s", (char *)NULL);
	T("[%s]", " ");
	T("%s%s", "ab", "cd");
	T("%s %s %s", "one", "two", "three");
	T("%s", "tab\tnewline\n");
	T("%s", "100%");
	T("%s", "%d %s %%");
	T("-%s-%s-", "", (char *)NULL);
	T("%s", "caf\xc3\xa9 \xff");
	TD("ft_printf(\"%s\", <1000-char string>)", "%s", g_long);
	TD("ft_printf(\"%s\", <50000-char string>)", "%s", g_big);
}
EOF
	;;

p) cat <<'EOF'
static void	tst_g_p(void)
{
	int		x = 0;
	char	*m = malloc(1);

	T("%p", (void *)0);
	T("%p", NULL);
	T("%p", &x);
	T("%p", m);
	T("%p", (void *)1);
	T("%p", (void *)15);
	T("%p", (void *)16);
	T("%p", (void *)0xdeadbeef);
	T("%p", (void *)LONG_MAX);
	T("%p", (void *)LONG_MIN);
	T("%p", (void *)ULONG_MAX);
	T("%p", (void *)-1);
	T("%p %p", (void *)0, (void *)0);
	T("%p%p", (void *)42, &x);
	T("[%p]", (void *)0x1234abcd);
	free(m);
}
EOF
	;;

d|i) sed "s/CONV/$1/g" <<'EOF'
static void	tst_g_CONV(void)
{
	int		t[] = {0, 1, -1, 7, -7, 9, -9, 10, -10, 42, -42, 99, 100, -100,
		12345, -12345, 1000000, INT_MAX, INT_MIN, INT_MAX - 1, INT_MIN + 1};
	char	d[96];

	for (size_t k = 0; k < sizeof t / sizeof *t; k++)
	{
		snprintf(d, sizeof d, "ft_printf(\"%%CONV\", %d)", t[k]);
		TD(d, "%CONV", t[k]);
	}
	T("%CONV%CONV", 1, -2);
	T("%CONV %CONV %CONV", INT_MIN, 0, INT_MAX);
	T("[%CONV]", 42);
	T("%CONV%%", 50);
	T("a%CONVb%CONVc", 1, 23);
	T("%CONV", (char)-1);
	T("%CONV", (short)-32768);
}
EOF
	;;

u) cat <<'EOF'
static void	tst_g_u(void)
{
	unsigned int	t[] = {0, 1, 9, 10, 42, 100, 12345, 1000000, INT_MAX,
		2147483648u, UINT_MAX - 1, UINT_MAX};
	char			d[96];

	for (size_t k = 0; k < sizeof t / sizeof *t; k++)
	{
		snprintf(d, sizeof d, "ft_printf(\"%%u\", %u)", t[k]);
		TD(d, "%u", t[k]);
	}
	T("%u", -1);
	T("%u", -42);
	T("%u", INT_MIN);
	T("%u%u", 1u, 2u);
	T("%u %u %u", 0u, UINT_MAX, 42u);
	T("[%u]", 7u);
}
EOF
	;;

x|X) sed "s/CONV/$1/g" <<'EOF'
static void	tst_g_CONV(void)
{
	unsigned int	t[] = {0, 1, 9, 10, 15, 16, 17, 42, 255, 256, 4095, 4096,
		0xabcdef, 0xdeadbeef, INT_MAX, 2147483648u, UINT_MAX};
	char			d[96];

	for (size_t k = 0; k < sizeof t / sizeof *t; k++)
	{
		snprintf(d, sizeof d, "ft_printf(\"%%CONV\", %#x)", t[k]);
		TD(d, "%CONV", t[k]);
	}
	T("%CONV", -1);
	T("%CONV", -42);
	T("%CONV", INT_MIN);
	T("%CONV%CONV%CONV", 1u, 10u, 100u);
	T("[%CONV]", 0xbeefu);
}
EOF
	;;

pct) cat <<'EOF'
static void	tst_g_pct(void)
{
	T("%%");
	T("%%%%");
	T("100%%");
	T("%%d");
	T("%%%d", 42);
	T("a%%b%%c");
	T("%%%s%%", "x");
	T("%%c%c", 'z');
	T("%% %% %%");
}
EOF
	;;

mix) cat <<'EOF'
static void	tst_g_mix(void)
{
	int	x = 0;
	int	r1;
	int	r2;
	int	n;

	/* nothing may stay in a buffer once ft_printf has returned */
	CASE("ft_printf(\"abc\"), write(1, \"|\", 1), ft_printf(\"%d\", 42), write(1, \"|\", 1)");
	tst_begin();
	r1 = ft_printf("abc");
	if (write(1, "|", 1) != 1)
		perror("write");
	r2 = ft_printf("%d", 42);
	if (write(1, "|", 1) != 1)
		perror("write");
	n = tst_end();
	if (n != 7 || memcmp(g_got, "abc|42|", 7) || r1 != 3 || r2 != 2)
		tst_fail("%s → %s (returns %d and %d), expected \"abc|42|\" (returns 3 and 2): "
			"ft_printf must write everything before returning (no buffer kept between calls)",
			g_case, tst_qn(g_got, n), r1, r2);
	else
		g_ok++;

	T("");
	T("hello world");
	T("\n");
	T("line 1\nline 2\n");
	T("%c%s%p%d%i%u%x%X%%", 'a', "bc", (void *)0xff, -1, 2, 3u, 255u, 255u);
	T("char %c, str %s, ptr %p, int %d %i, uint %u, hex %x %X, pct %%\n",
		'Z', "txt", (void *)&x, INT_MIN, INT_MAX, UINT_MAX, 0xbeefu, 0xbeefu);
	T("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20);
	T("%s%s%s%s%s", "a", "", "b", (char *)NULL, "c");
	T("%x%X%x", 0xabu, 0xabu, 0u);
	T("%p%s%c%d", (void *)0, (char *)NULL, 'n', 0);
	T("%s|%c|%d|%u", "fin", '!', 0, 0u);
	TD("ft_printf(<1000-char text without %>)", g_long);
	T("%d%s%c%x%X%u%i%p%%|%d%s%c%x%X%u%i%p%%|%d%s%c%x%X%u%i%p%%",
		1, "a", 'b', 10u, 11u, 12u, -13, (void *)14,
		INT_MIN, "", '\0', 0u, UINT_MAX, 0u, INT_MAX, (void *)0,
		-1, (char *)NULL, 'z', 0xffu, 0xabcu, 42u, 0, (void *)&x);
	{
		char	*lf = malloc(20010);
		char	bytes[256];
		int		j = 0;

		/* 20000-char format, with conversions in the middle and at the end */
		memset(lf, 'f', 20000);
		memcpy(lf + 9998, "%d", 2);
		strcpy(lf + 20000, "%s");
		TD("ft_printf(<20000-char format with a %d in the middle and a %s at the end>)", lf, 42, "end");
		free(lf);
		/* every byte from 1 to 255 (except '%') as plain text */
		for (int c = 1; c < 256; c++)
			if (c != '%')
				bytes[j++] = (char)c;
		bytes[j] = 0;
		TD("ft_printf(<every byte from 1 to 255 except %>)", bytes);
	}
}
EOF
	;;

robust) cat <<'EOF'
static int	tst_fn_int(void)
{
	return (ft_printf(g_fmt, 42, 42, 42));
}

static int	tst_fn_str(void)
{
	return (ft_printf(g_fmt, "abc", "abc"));
}

static int	tst_fn_null(void)
{
	return (ft_printf(NULL));
}

static int	(*g_fn)(void) = tst_fn_int;

static int	tst_fn_closed(void)
{
	close(1);
	return (g_fn());
}

static int	tst_fn_full(void)
{
	int	fd = open("/dev/full", O_WRONLY);

	dup2(fd, 1);
	return (g_fn());
}

/* undefined behaviour: the output does not matter, but ft_printf must not
   crash, loop or read past the end of the format (allocated at its exact size) */
static void	tst_ub(const char *f)
{
	char	d[200];
	char	*h = malloc(strlen(f) + 1);
	int		r;
	int		res;

	strcpy(h, f);
	g_fmt = h;
	snprintf(d, sizeof d, "ft_printf(%s)", tst_qn(f, strlen(f)));
	CASE(d);
	res = tst_child(tst_fn_int, 0, &r);
	if (res == 1)
		tst_fail("%s: crash or memory error (undefined behaviour, but the real printf "
			"neither crashes nor reads past the end of the format)", d);
	else if (res == 2)
		tst_fail("%s: infinite loop (undefined behaviour, but the real printf returns)", d);
	else if (res == 0)
		g_ok++;
	free(h);
}

/* write() fails: printf returns -1 (C standard: "a negative value if an
   output error occurred") */
static void	tst_write_fail(int (*mode)(void), const char *how)
{
	const char	*f[] = {"hello", "%d", "%c", "%x", "%u", "%%", "abc%ixyz", "%s", "%p"};
	char		d[200];
	char		bad[300] = "";
	int			r;
	int			res;

	for (int k = 0; k < 9; k++)
	{
		g_fmt = f[k];
		g_fn = k < 7 ? tst_fn_int : tst_fn_str;
		snprintf(d, sizeof d, "ft_printf(%s) when write() fails (%s)", tst_qn(f[k], strlen(f[k])), how);
		CASE(d);
		res = tst_child(mode, 0, &r);
		if (res == 1)
			tst_fail("%s: crash", d);
		else if (res == 2)
			tst_fail("%s: infinite loop", d);
		else if (res == 0)
		{
			g_ok++;
			if (r != -1 && strlen(bad) < 200)
				snprintf(bad + strlen(bad), sizeof bad - strlen(bad), "%s%s → %d",
					*bad ? ", " : "", tst_qn(f[k], strlen(f[k])), r);
		}
	}
	if (*bad)
		tst_warn("when write() fails (%s), printf returns -1; your ft_printf returns: %s", how, bad);
}

static void	tst_g_robust(void)
{
	const char	*ub[] = {"%", "abc%", "%%%", "abc%%%", "%k", "abc%kdef", "%5", "% ",
		"%-", "%.", "%#", "%+", "%0", "%-5", "%.3", "%05.3", "%#0-+ 5.3", "%-%", "%l", "%ld", "%lld",
		"%hhd", "%zu", "%5%", "%-5%", "%\n"};
	int			x = 0;
	int			r;
	int			res;

	for (size_t k = 0; k < sizeof ub / sizeof *ub; k++)
		tst_ub(ub[k]);
	CASE("ft_printf(NULL)");
	res = tst_child(tst_fn_null, 1, &r);
	if (res == 2)
		tst_fail("ft_printf(NULL): infinite loop");
	else if (res == 3)
		;
	else if (res == 1)
		tst_warn("ft_printf(NULL) crashes (undefined behaviour; glibc's printf returns -1)");
	else
		g_ok++;
	tst_write_fail(tst_fn_closed, "stdout closed");
	if (access("/dev/full", W_OK) == 0)
		tst_write_fail(tst_fn_full, "stdout = /dev/full");
	if (g_loop_skipped)
		tst_fail("%d other tests skipped after 2 infinite loops", g_loop_skipped);
	/* each malloc fails in turn: no crash, no leak */
	TMM("hello");
	TMM("%c", 'a');
	TMM("%s", "hello");
	TMM("%s", (char *)NULL);
	TMM("%p", (void *)&x);
	TMM("%p", (void *)0);
	TMM("%d", INT_MIN);
	TMM("%i", 42);
	TMM("%u", UINT_MAX);
	TMM("%x", 0xabcdefu);
	TMM("%X", 0xabcdefu);
	TMM("%%");
	TMM("%c%s%p%d%i%u%x%X%%", 'a', "bc", (void *)0xff, -1, 2, 3u, 255u, 255u);
	TMM("%s %s %s %d %d %d", "a", "b", "c", 1, 2, 3);
}
EOF
	;;

fuzz|bfuzz) fuzz_src "$1" ;;

width) cat <<'EOF'
static void	tst_g_width(void)
{
	int	x = 0;

	T("[%5c]", 'a');
	T("[%1c]", 'a');
	T("[%3c]", '\0');
	T("[%10s]", "abc");
	T("[%3s]", "hello");
	T("[%10s]", "");
	T("[%10s]", (char *)NULL);
	T("[%20p]", (void *)&x);
	T("[%20p]", (void *)0);
	T("[%5p]", (void *)1);
	T("[%5d]", 42);
	T("[%5d]", -42);
	T("[%1d]", 12345);
	T("[%12i]", INT_MIN);
	T("[%5u]", 42u);
	T("[%12u]", UINT_MAX);
	T("[%8x]", 0xabcu);
	T("[%8X]", 0xabcu);
	T("[%2x]", 0xabcdefu);
	T("[%5d][%3d]", 0, 7);
	/* big widths: no fixed-size buffer */
	T("[%300d]", 42);
	T("[%300d]", INT_MIN);
	T("[%300u]", UINT_MAX);
	T("[%300x]", 0xabcu);
	T("[%300X]", 0xabcu);
	T("[%300c]", 'z');
	T("[%300s]", "abc");
	T("[%300p]", (void *)&x);
	T("[%300p]", (void *)0);
	T("[%1500s]", g_long);
	T("[%5000i]", -7);
	T("[%50000c]", '!');
}
EOF
	;;

minus) cat <<'EOF'
static void	tst_g_minus(void)
{
	int	x = 0;

	T("[%-5c]", 'a');
	T("[%-1c]", 'b');
	T("[%-3c]", '\0');
	T("[%-10s]", "abc");
	T("[%-10s]", "");
	T("[%-10s]", (char *)NULL);
	T("[%-2s]", "hello");
	T("[%-20p]", (void *)&x);
	T("[%-20p]", (void *)0);
	T("[%-5d]", 42);
	T("[%-5d]", -42);
	T("[%-12d]", INT_MIN);
	T("[%-1d]", 0);
	T("[%-5i]", 7);
	T("[%-5u]", 42u);
	T("[%-12u]", UINT_MAX);
	T("[%-8x]", 0xabcu);
	T("[%-8X]", 0xabcu);
	T("[%-5d][%5d]", 1, 2);
	T("[%-300d]", -42);
	T("[%-300s]", (char *)NULL);
	T("[%-300c]", '\0');
	T("[%-300p]", (void *)&x);
	T("[%-5000x]", UINT_MAX);
	T("[%-1500s]", g_long);
}
EOF
	;;

zero) cat <<'EOF'
static void	tst_g_zero(void)
{
	T("[%05d]", 42);
	T("[%05d]", -42);
	T("[%05d]", 0);
	T("[%01d]", 7);
	T("[%03d]", 12345);
	T("[%012d]", INT_MIN);
	T("[%05i]", 42);
	T("[%05i]", -7);
	T("[%05u]", 42u);
	T("[%012u]", UINT_MAX);
	T("[%08x]", 0xabcu);
	T("[%08X]", 0xabcu);
	T("[%02x]", 0u);
	T("[%-05d]", 42);
	T("[%05.3d]", 42);
	T("[%05.0d]", 0);
	T("[%08.5x]", 0xabu);
	T("[%0300d]", -42);
	T("[%0300i]", INT_MIN);
	T("[%0300u]", 42u);
	T("[%0300X]", 0xabcu);
	T("[%05d|%5d|%-5d|%05d]", -1, -1, -1, -1);
}
EOF
	;;

prec) cat <<'EOF'
static void	tst_g_prec(void)
{
	T("[%.3s]", "hello");
	T("[%.0s]", "hello");
	T("[%.s]", "hello");
	T("[%.10s]", "hello");
	T("[%.5s]", "");
	T("[%.6s]", (char *)NULL);
	T("[%.10s]", (char *)NULL);
	T("[%.5d]", 42);
	T("[%.5d]", -42);
	T("[%.0d]", 0);
	T("[%.d]", 0);
	T("[%.0d]", 5);
	T("[%.1d]", 0);
	T("[%.3d]", 12345);
	T("[%.12d]", INT_MIN);
	T("[%.5i]", 42);
	T("[%.5u]", 42u);
	T("[%.0u]", 0u);
	T("[%.8x]", 0xabcu);
	T("[%.0x]", 0u);
	T("[%.8X]", 0xabcu);
	T("[%.0X]", 0u);
	T("[%8.3d]", 42);
	T("[%-8.3d]", -42);
	T("[%8.3s]", "hello");
	T("[%-8.3s]", "hello");
	T("[%5.0d]", 0);
	T("[%-5.0d]", 0);
	T("[%10.5i]", -42);
	T("[%3.5d]", 42);
	T("[%10.8x]", 0xabcu);
	T("[%.300d]", 42);
	T("[%.300d]", INT_MIN);
	T("[%.300i]", 0);
	T("[%.5000u]", UINT_MAX);
	T("[%.3000x]", 0xabcu);
	T("[%.300X]", 0u);
	T("[%.999s]", g_long);
	T("[%.1000s]", g_long);
	T("[%.2000s]", g_long);
	T("[%400.300d]", -42);
	T("[%-400.300X]", 0xabcu);
	T("[%.6s|%.7s|%.0s]", (char *)NULL, (char *)NULL, "");
	T("[%.0d|%.0i|%.0u|%.0x|%.0X]", 0, 0, 0u, 0u, 0u);
	T("[%3.0d|%-3.0u|%3.0x]", 0, 0u, 0u);
	T("[%.00d|%.001d]", 0, 0);
}
EOF
	;;

hash) cat <<'EOF'
static void	tst_g_hash(void)
{
	T("[%#x]", 0u);
	T("[%#x]", 42u);
	T("[%#X]", 42u);
	T("[%#x]", UINT_MAX);
	T("[%#X]", 0xabcdefu);
	T("[%#10x]", 42u);
	T("[%#-10x]", 42u);
	T("[%#010x]", 42u);
	T("[%#010X]", 42u);
	T("[%#.5x]", 42u);
	T("[%#.0x]", 0u);
	T("[%#5.0x]", 0u);
	T("[%#8.5X]", 0xabu);
	T("[%#x %#X]", 1u, 1u);
	T("[%#300x]", 42u);
	T("[%#-300X]", 42u);
	T("[%#0300x]", 42u);
	T("[%#.300x]", 42u);
	T("[%#x|%x|%#x]", 1u, 1u, 0u);
	T("[%#-10.0x]", 0u);
	T("[%#010.0x]", 0u);
}
EOF
	;;

plus) cat <<'EOF'
static void	tst_g_plus(void)
{
	T("[%+d]", 42);
	T("[%+d]", 0);
	T("[%+d]", -42);
	T("[%+d]", INT_MAX);
	T("[%+d]", INT_MIN);
	T("[%+i]", 7);
	T("[%+5d]", 42);
	T("[%+-5d]", 42);
	T("[%-+5d]", -42);
	T("[%+05d]", 42);
	T("[%+05d]", -42);
	T("[%+.3d]", 7);
	T("[%+.0d]", 0);
	T("[%+5.0d]", 0);
	T("[%+d %+i]", 1, -1);
	T("[%+300d]", 42);
	T("[%+.300d]", -42);
	T("[%+0300i]", 0);
	T("[%+d|%d|%+d]", 1, 1, 0);
}
EOF
	;;

space) cat <<'EOF'
static void	tst_g_space(void)
{
	T("[% d]", 42);
	T("[% d]", 0);
	T("[% d]", -42);
	T("[% d]", INT_MAX);
	T("[% d]", INT_MIN);
	T("[% i]", 7);
	T("[% 5d]", 42);
	T("[% -5d]", 42);
	T("[% 05d]", 42);
	T("[% .3d]", 7);
	T("[% .0d]", 0);
	T("[% +d]", 42);
	T("[%+ d]", 42);
	T("[%  d]", 42);
	T("[% 5.0d]", 0);
	T("[% 300d]", 42);
	T("[% .300d]", -42);
	T("[% 0300i]", 7);
	T("[% d|%d|% d]", 1, 1, 0);
}
EOF
	;;

combo) cat <<'EOF'
static void	tst_g_combo(void)
{
	T("[%-10s|%05d|%#x|%+d|% i|%.2s]", "abc", 42, 255u, 7, 8, "hello");
	T("[%-5c|%5c]", 'a', 'b');
	T("[%10.3s|%-10.3s]", "abcdef", "abcdef");
	T("[%08.3d|%-8.3d|%+8.3d|% 8.3d]", 42, 42, 42, 42);
	T("[%#-12.6x|%#12X]", 0xabcu, 0xabcu);
	T("[%-20p|%20p]", (void *)0xff, (void *)0);
	T("[%%%-5d%%]", 3);
	T("[%05d%-5d%5d]", 1, 2, 3);
	T("[%.0s%.0d%.0x]", "abc", 0, 0u);
	T("[%-+8.4d|%-#8.4x|%- 8.4i]", 5, 5u, 5);
	T("[%010u|%-10u|%.10u]", 42u, 42u, 42u);
	/* flags must not leak to the next conversion */
	T("[%-5d|%d|%05d|%d|%.3d|%d|%+d|%d|% d|%d|%#x|%x]", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11u, 12u);
	T("[%10s|%s|%.2s|%s|%-4c|%c]", "ab", "cd", "efgh", "ij", 'k', 'l');
	/* each malloc fails in turn: no crash, no leak */
	TMM("[%-10s|%05d|%#x|%+d|% i|%.2s|%10p]", "abc", 42, 255u, 7, 8, "hello", (void *)0xff);
	TMM("[%300d]", 42);
	TMM("[%-300s]", "abc");
	TMM("[%.300x]", 42u);
	TMM("[%#020X|%-20u|%020i]", 42u, 42u, -42);
}
EOF
	;;
esac
}

# Random formats compared to printf (fuzz: mandatory, bfuzz: with flags)
fuzz_src() {
	local a b c
	if [ -z "$FUZZ_DONE" ]; then
		FUZZ_DONE=1
		cat <<'EOF'
typedef struct s_tv
{
	int			i;
	unsigned	u;
	const char	*s;
	void		*p;
	char		conv;
}	t_tv;

static unsigned	g_fs = 1;
static int		g_fx = 0;
static char		g_fcase[1024];

static unsigned	fz_rnd(void)
{
	g_fs = g_fs * 1103515245u + 12345u;
	return ((g_fs >> 8) & 0xffffff);
}

static unsigned	fz_rnd32(void)
{
	return ((fz_rnd() << 16) ^ fz_rnd());
}

static void	fz_text(char *f)
{
	const char	*set = "abcXYZ 0123456789-+.:|#_\n\t";
	size_t		n = strlen(f);
	int			k = fz_rnd() % 5 == 0 ? fz_rnd() % 7 : 0;

	while (k-- > 0)
		f[n++] = set[fz_rnd() % strlen(set)];
	if (fz_rnd() % 12 == 0)
	{
		f[n++] = '%';
		f[n++] = '%';
	}
	f[n] = 0;
}

static int	fz_int(void)
{
	const int	t[] = {0, 1, -1, 9, -9, 10, -10, 42, -42, 100, 999, -1000,
		12345, INT_MAX, INT_MIN, INT_MAX - 1, INT_MIN + 1};
	int			k = fz_rnd() % 20;

	if (k < 17)
		return (t[k]);
	return (k == 17 ? (int)fz_rnd32() : (int)(fz_rnd() % 2001) - 1000);
}

static unsigned	fz_uint(void)
{
	const unsigned	t[] = {0, 1, 9, 10, 15, 16, 255, 256, 4095, 4096, 0xabcdef,
		0xdeadbeef, INT_MAX, 2147483648u, UINT_MAX};
	int				k = fz_rnd() % 18;

	if (k < 15)
		return (t[k]);
	return (k == 15 ? fz_rnd32() : fz_rnd() % 5000);
}

/* appends a random conversion; returns the type of its argument
   (0 int, 1 unsigned, 2 string, 3 pointer), -1 for %% */
static int	fz_conv(char *f, int bonus, t_tv *v)
{
	const char	*convs = "cspdiuxX%";
	const char	*strs[] = {"", "a", "hello", "Hello, World!", "  sp  ", "%d %s %%",
		"\t\n", "caf\xc3\xa9", g_long, NULL};
	void		*ptrs[] = {NULL, &g_fx, (void *)1, (void *)0xff, (void *)0xdeadbeef,
		(void *)LONG_MAX, (void *)LONG_MIN, (void *)ULONG_MAX, g_big};
	const char	*chars = "aZ0 ~\n\t";
	char		c = convs[fz_rnd() % 9];
	char		*p = f + strlen(f);
	const char	*fl = "";
	int			prec = -1;

	*p++ = '%';
	if (bonus && c != '%')
	{
		char	set[8];
		int		n = 0;

		fl = c == 'd' || c == 'i' ? "-0+ " : c == 'u' ? "-0" : c == 'x' || c == 'X' ? "-0#" : "-";
		for (int k = 0; fl[k]; k++)
			if (fz_rnd() % 3 == 0)
				set[n++] = fl[k];
		for (int k = n - 1; k > 0; k--)
		{
			int		j = fz_rnd() % (k + 1);
			char	t = set[k];

			set[k] = set[j];
			set[j] = t;
		}
		if (n > 0 && fz_rnd() % 15 == 0)
			set[n++] = set[0];
		memcpy(p, set, n);
		p += n;
		if (fz_rnd() % 2)
			p += sprintf(p, "%u", fz_rnd() % 8 ? 1 + fz_rnd() % 20 : 20 + fz_rnd() % 60);
		if (c != 'c' && c != 'p' && fz_rnd() % 5 < 2)
		{
			if (fz_rnd() % 4 == 0)
				prec = 0;
			else
				prec = fz_rnd() % 8 ? fz_rnd() % 15 : fz_rnd() % 60;
			p += prec == 0 && fz_rnd() % 2 ? sprintf(p, ".") : sprintf(p, ".%d", prec);
		}
	}
	*p++ = c;
	*p = 0;
	v->conv = c;
	if (c == '%')
		return (-1);
	if (c == 'c')
		v->i = fz_rnd() % 9 < 7 ? chars[fz_rnd() % 7] : fz_rnd() % 2 ? 0 : 200;
	else if (c == 's')
	{
		v->s = strs[fz_rnd() % 10];
		if (!v->s && prec >= 0 && prec < 6)
			v->s = "null";
		return (2);
	}
	else if (c == 'p')
	{
		v->p = ptrs[fz_rnd() % 9];
		return (3);
	}
	else if (c == 'd' || c == 'i')
		v->i = fz_int();
	else
	{
		v->u = fz_uint();
		return (1);
	}
	return (0);
}

/* "ft_printf("fmt", args)" for the report */
static void	fz_desc(const char *f, const t_tv *v, int n)
{
	int	j = snprintf(g_fcase, sizeof g_fcase, "ft_printf(%s", tst_qn(f, strlen(f)));

	for (int k = 0; k < n && j < 900; k++)
	{
		if (v[k].conv == 's' && v[k].s == g_long)
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", <1000-char string>");
		else if (v[k].conv == 's')
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", %s", tst_qn(v[k].s, v[k].s ? strlen(v[k].s) : 0));
		else if (v[k].conv == 'p' && !v[k].p)
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", NULL");
		else if (v[k].conv == 'p')
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", (void *)%#lx", (unsigned long)v[k].p);
		else if (v[k].conv == 'c' && v[k].i > 32 && v[k].i < 127)
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", '%c'", v[k].i);
		else if (v[k].conv == 'c' || v[k].conv == 'd' || v[k].conv == 'i')
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", %d", v[k].i);
		else
			j += snprintf(g_fcase + j, sizeof g_fcase - j, ", %uu", v[k].u);
	}
	snprintf(g_fcase + j, sizeof g_fcase - j, ")");
}

#define FZ_0(k) v[k].i
#define FZ_1(k) v[k].u
#define FZ_2(k) v[k].s
#define FZ_3(k) v[k].p

static void	fz_call(const char *f, const int *t, const t_tv *v)
{
	switch (t[0] * 16 + t[1] * 4 + t[2])
	{
EOF
		for a in 0 1 2 3; do for b in 0 1 2 3; do for c in 0 1 2 3; do
			printf '\t\tcase %d: TD(g_fcase, f, FZ_%d(0), FZ_%d(1), FZ_%d(2)); break;\n' \
				$((a * 16 + b * 4 + c)) $a $b $c
		done; done; done
		cat <<'EOF'
	}
}

/* count random formats of 1 to 3 conversions, with random text around */
static void	fz_run(unsigned seed, int count, int bonus)
{
	char	f[512];
	t_tv	v[3];
	int		t[3];
	int		n;
	int		nconv;

	g_fs = seed;
	for (int it = 0; it < count; it++)
	{
		memset(v, 0, sizeof v);
		memset(t, 0, sizeof t);
		f[0] = 0;
		n = 0;
		nconv = 1 + fz_rnd() % 3;
		fz_text(f);
		for (int k = 0; k < nconv; k++)
		{
			int	ty = fz_conv(f, bonus, &v[n]);

			if (ty >= 0)
				t[n++] = ty;
			fz_text(f);
		}
		fz_desc(f, v, n);
		fz_call(f, t, v);
	}
}
EOF
	fi
	if [ "$1" = fuzz ]; then
		printf 'static void\ttst_g_fuzz(void)\n{\n\tfz_run(42, 3000, 0);\n}\n'
	else
		printf 'static void\ttst_g_bfuzz(void)\n{\n\tfz_run(4242, 8000, 1);\n}\n'
	fi
}

# C source of a test program for the given groups
gen_src() {
	FUZZ_DONE=""
	prelude
	for g in "$@"; do body "$g"; done
	printf 'static void\ttst_run(void)\n{\n'
	for g in "$@"; do printf '\ttst_g_%s();\n' "$g"; done
	printf '}\n'
}

# ------------------------- Reading the ASan report -------------------------- #
# BUILD = folder where your library was compiled
user_frame() {
	grep -E "^[[:space:]]+#[0-9]+ .* in [^ ]+ $BUILD/" | head -1 \
		| sed -E "s|.* in ([^ ]+) $BUILD/([^ ]+).*|\2 (\1)|"
}

# Line of the test that made the faulty call
test_frame_line() {
	local src=$1 n
	n=$(grep -E "/$(basename "$src"):[0-9]+" | grep -v ' in __wrap_malloc ' | head -1 \
		| sed -E 's/.*\.c:([0-9]+).*/\1/')
	[ -n "$n" ] && sed -n "${n}p" "$src" | sed -E 's/^[[:space:]]+//; s/^TM*\(/ft_printf(/; s/\);$/)/' | cut -c1-110
}

asan_report() {
	local err=$1 src=$2 type loc call
	if grep -q "ERROR: AddressSanitizer" "$err"; then
		type=$(grep -m1 -oE "ERROR: AddressSanitizer: [a-zA-Z_-]+" "$err" | awk '{print $3}')
		loc=$(sed -n '/ERROR: AddressSanitizer/,/^$/p' "$err" | user_frame)
		if [ -n "$loc" ]; then
			msg "memory error ($type) in $loc"
		else
			msg "memory error ($type)"
		fi
	fi
	if grep -q "ERROR: LeakSanitizer" "$err"; then
		msg "memory leak: $(grep -oE '[0-9]+ byte\(s\) leaked in [0-9]+ allocation\(s\)' "$err" | tail -1)"
		awk '/leak of/{n++} {print > (FILENAME "." n)}' "$err"
		for blk in "$err".[1-9]*; do
			[ -f "$blk" ] || continue
			loc=$(user_frame < "$blk")
			call=$(test_frame_line "$src" < "$blk")
			printf "        ${D}malloc in %s%s${N}\n" "${loc:-?}" "${call:+ ← call: $call}"
		done | sort -u | head -4
		rm -f "$err".[1-9]*
	fi
}

# -------------------------- Running a test program -------------------------- #
# run_group <label> <name> <libftprintf.a folder> <groups...>
run_group() {
	local label=$1 name=$2 lib=$3 src="$TMP/t_$2.c" bin="$TMP/t_$2" out rc res ok ko warns
	shift 3
	gen_src "$@" > "$src"
	if ! cc $SAN -g -w "$src" -o "$bin" -L"$lib" -lftprintf -Wl,--wrap=malloc 2> "$TMP/cerr"; then
		line_ko "$label"
		if grep -q "undefined reference to .ft_printf'" "$TMP/cerr"; then
			msg "ft_printf not found in libftprintf.a"
		elif grep -q "undefined reference" "$TMP/cerr"; then
			msg "incomplete libftprintf.a: $(grep -m1 -oE "undefined reference to .[^']+'" "$TMP/cerr") (libft not included in libftprintf.a?)"
		else
			msg "the test does not compile: $(first_error "$TMP/cerr")"
		fi
		return
	fi
	out=$(cd "$TMP" && ASAN_OPTIONS="detect_leaks=1:allocator_may_return_null=1" timeout 30 "$bin" 2> "$TMP/rerr")
	rc=$?
	res=$(grep -m1 "^@@RESULT" <<< "$out")
	ok=$(awk '{print $2}' <<< "$res"); ko=$(awk '{print $3}' <<< "$res")
	warns=$(grep "^@@WARN " <<< "$out" | sed 's/^@@WARN //')
	if [ -n "$res" ] && [ "$ko" = 0 ] && ! grep -q "Sanitizer" "$TMP/rerr"; then
		if [ -n "$warns" ]; then
			line_warn "$label" "check by hand ($ok tests passed)"
			while IFS= read -r m; do note "$m"; done <<< "$warns"
		else
			line_ok "$label" "($ok tests)"
		fi
		return
	fi
	line_ko "$label"
	grep "^@@MSG " <<< "$out" | sed 's/^@@MSG //' | while IFS= read -r m; do msg "$m"; done
	if [ $rc -eq 124 ]; then
		msg "infinite loop (30 s timeout) during: $(grep "^@@CRASH" <<< "$out" | tail -1 | sed 's/^@@CRASH //')"
	elif [ -z "$res" ]; then
		msg "crash during: $(grep "^@@CRASH" <<< "$out" | tail -1 | sed 's/^@@CRASH //')"
	fi
	asan_report "$TMP/rerr" "$src"
	[ -n "$warns" ] && while IFS= read -r m; do note "!! $m"; done <<< "$warns"
}

# --------------------------- Building the library --------------------------- #
copy_repo() { mkdir -p "$1" && tar -C "$DIR" --exclude=.git -cf - . | tar -C "$1" -xf -; }
has_rule() { grep -qE "^$1[[:space:]]*:" "$DIR/Makefile" 2>/dev/null; }

# build_lib <folder> [bonus]: make (with AddressSanitizer if possible)
build_lib() {
	copy_repo "$1"
	make -C "$1" fclean > /dev/null 2>&1
	if [ -n "$SAN" ] && make -C "$1" $2 CC="cc $SAN -g" > "$1.log" 2>&1 && [ -f "$1/libftprintf.a" ]; then
		return 0
	fi
	make -C "$1" fclean > /dev/null 2>&1
	make -C "$1" $2 > "$1.log" 2>&1 && [ -f "$1/libftprintf.a" ]
}

# Manual build (if your Makefile fails): every .c except *_bonus.c
manual_lib() {
	local f n=0 incs=()
	mkdir -p "$1"
	while IFS= read -r f; do incs+=("-I$f"); done \
		< <(find "$DIR" -name '*.h' -not -path '*/.git/*' -exec dirname {} \; | sort -u)
	MANUAL_ERR=""
	while IFS= read -r f; do
		grep -qE '^[a-z_[:space:]]*[[:space:]]main[[:space:]]*\(' "$f" && continue
		n=$((n + 1))
		if ! cc $SAN -g -w "${incs[@]}" -c "$f" -o "$1/m$n.o" 2> "$1.err"; then
			rm -f "$1/m$n.o"
			[ -z "$MANUAL_ERR" ] && MANUAL_ERR="${f#$DIR/} does not compile: $(first_error "$1.err")"
		fi
	done < <(find "$DIR" -name '*.c' -not -name '*_bonus.c' -not -path '*/.git/*')
	ar rcs "$1/libftprintf.a" "$1"/*.o 2> /dev/null
}

# External functions called by objects / archives
ext_funcs() {
	comm -23 \
		<(nm -u "$@" 2>/dev/null | awk 'NF == 2 && $1 == "U" {print $2}' | sed 's/@.*//' | sort -u) \
		<(nm --defined-only "$@" 2>/dev/null | awk 'NF == 3 {print $3}' | sort -u) \
		| grep -vxE '_GLOBAL_OFFSET_TABLE_|__stack_chk_fail|__stack_chk_guard'
}

# ================================== Start =================================== #
SAN="-fsanitize=address"
echo 'int main(void){return 0;}' > "$TMP/probe.c"
if ! cc $SAN "$TMP/probe.c" -o "$TMP/probe" 2>/dev/null || ! "$TMP/probe" 2>/dev/null; then
	SAN=""
	printf "${Y}AddressSanitizer unavailable: leaks and buffer overflows will not be detected.${N}\n"
fi

# --------------------------------- Makefile --------------------------------- #
LIB_OK=0
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Makefile"
	if [ ! -f "$DIR/Makefile" ]; then
		line_ko "Makefile"; msg "Makefile missing"
	else
		copy_repo "$TMP/mk"
		mk() { make -C "$TMP/mk" "$@" 2>&1; }
		mk fclean > /dev/null
		out=$(mk); rc=$?
		if [ $rc -eq 0 ] && [ -f "$TMP/mk/libftprintf.a" ]; then
			line_ok "make"
			LIB_OK=1
			cp "$TMP/mk/libftprintf.a" "$TMP/plain.a"
			if grep -qE '(^|[[:space:]])(gcc|clang)[[:space:]]' <<< "$out"; then
				CC_BAD=1
			fi
			if nm "$TMP/mk/libftprintf.a" 2>/dev/null | grep -qE ' T ft_printf$'; then
				line_ok "libftprintf.a"
			else
				line_ko "libftprintf.a"; msg "ft_printf is not defined in libftprintf.a"
			fi
			out=$(mk)
			if grep -qE '(^|[[:space:]/])(cc|gcc|clang|ar)[[:space:]]' <<< "$out"; then
				line_ko "relink"; msg "a 2nd 'make' rebuilds although nothing changed"
			else line_ok "relink"; fi
			mk clean > /dev/null
			if [ -n "$(find "$TMP/mk" -name '*.o')" ] || [ ! -f "$TMP/mk/libftprintf.a" ]; then
				line_ko "make clean"; msg "must remove every .o and keep libftprintf.a"
			else line_ok "make clean"; fi
			mk fclean > /dev/null
			if [ -f "$TMP/mk/libftprintf.a" ]; then line_ko "make fclean"; msg "libftprintf.a is not removed"
			else line_ok "make fclean"; fi
			if mk re > /dev/null && [ -f "$TMP/mk/libftprintf.a" ]; then line_ok "make re"
			else line_ko "make re"; fi
			if has_rule bonus; then
				mk fclean > /dev/null
				out=$(mk bonus)
				if [ $? -eq 0 ] && [ -f "$TMP/mk/libftprintf.a" ]; then
					line_ok "make bonus"
					out=$(mk bonus)
					if grep -qE '(^|[[:space:]/])(cc|gcc|clang|ar)[[:space:]]' <<< "$out"; then
						line_ko "relink bonus"; msg "a 2nd 'make bonus' rebuilds although nothing changed"
					else line_ok "relink bonus"; fi
				else
					line_ko "make bonus"; msg "$(grep -m1 -E 'error|\*\*\*' <<< "$out" | sed -E 's|^/[^ ]*/||' | cut -c1-150)"
				fi
			fi
		else
			line_ko "make"
			grep -E 'error:|undefined reference|No rule|^make.*\*\*\*' <<< "$out" | head -3 \
				| sed -E 's|^/[^ ]*/||' | cut -c1-150 | while IFS= read -r m; do msg "$m"; done
			[ $rc -eq 0 ] && msg "libftprintf.a is not created at the root of the repository"
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
		if grep -qw libtool "$DIR/Makefile"; then
			line_ko "ar"; msg "the libtool command is forbidden: use ar"
		fi
	fi

	section "Submission"
	check_readme() {
		local f="$DIR/README.md" first s missing="" m=()
		if [ ! -f "$f" ]; then line_ko "README.md"; msg "README.md missing (mandatory)"; return; fi
		first=$(head -1 "$f" | tr -d '\r')
		grep -qE '^[*_]This project has been created as part of the 42 curriculum by .+[*_][[:space:]]*$' <<< "$first" \
			|| m+=("first line must be in italics: *This project has been created as part of the 42 curriculum by <login>.*")
		# 'Ressources': the README may be written in the campus language
		for s in Description Instructions 'Resources|Ressources'; do
			grep -qiE "^#+.*($s)" "$f" || missing+="${s%%|*} "
		done
		[ -n "$missing" ] && m+=("missing section(s): $missing")
		if [ ${#m[@]} -eq 0 ]; then line_ok "README.md"
		else line_ko "README.md"; for s in "${m[@]}"; do msg "$s"; done; fi
	}
	check_readme
	hdr=$(find "$DIR" -maxdepth 2 -name ft_printf.h -not -path '*/.git/*' | head -1)
	if [ -z "$hdr" ]; then
		line_ko "ft_printf.h"; msg "ft_printf.h missing"
	elif grep -qE 'int[[:space:]]+ft_printf[[:space:]]*\([[:space:]]*const[[:space:]]+char[[:space:]]*\*' "$hdr"; then
		line_ok "ft_printf.h"
	else
		line_ko "ft_printf.h"; msg "prototype missing or different. Expected: int ft_printf(const char *, ...);"
	fi
	if [ $LIB_OK -eq 1 ]; then
		bad=$(ext_funcs "$TMP/plain.a" | grep -vxE 'malloc|free|write' | tr '\n' ' ')
		if [ -z "$bad" ]; then line_ok "allowed functions" "(malloc free write va_*)"
		else line_ko "allowed functions"; msg "forbidden external function(s): $bad"; fi
		glob=$(nm "$TMP/plain.a" 2>/dev/null | awk '$2 ~ /^[BCDGS]$/ {print $3}' | sort -u | tr '\n' ' ')
		if [ -z "$glob" ]; then line_ok "global variables"
		else line_ko "global variables"; msg "global variable(s) forbidden by the Norm: $glob"; fi
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

# ------------------------------ Mandatory part ------------------------------ #
want_any() { for g in "$@"; do wanted "$g" && return 0; done; return 1; }

if want_any "${MAND[@]}"; then
	section "Mandatory part"
	BUILD="$TMP/asan"
	if ! build_lib "$TMP/asan"; then
		BUILD="$DIR"
		manual_lib "$TMP/manual"
		LIBDIR="$TMP/manual"
		printf "  ${Y}make fails: the tester compiles your library itself to test it anyway.${N}\n"
		[ -n "$MANUAL_ERR" ] && printf "  ${Y}%s${N}\n" "$MANUAL_ERR"
	else
		LIBDIR="$TMP/asan"
	fi
	for g in "${MAND[@]}"; do
		wanted "$g" || continue
		run_group "${LABEL[$g]}" "$g" "$LIBDIR" "$g"
	done
fi

# ---------------------------------- Bonus ----------------------------------- #
if want_any "${BONUS[@]}"; then
	section "Bonus"
	if ! has_rule bonus; then
		line_skip "bonus" "no bonus rule in the Makefile"
	elif [ ${#WANTED[@]} -eq 0 ] && [ -z "$(find "$DIR" -name '*_bonus.c' -not -path '*/.git/*' | head -1)" ]; then
		line_skip "bonus" "no *_bonus.c file (to test anyway: bash $(basename "$0") bonus)"
	elif ! build_lib "$TMP/bonus" bonus; then
		line_ko "make bonus"; msg "$(first_error "$TMP/bonus.log")"
	else
		BUILD="$TMP/bonus"
		[ ${#WANTED[@]} -eq 0 ] && run_group "mandatory (bonus)" "mand_bonus" "$TMP/bonus" "${MAND[@]}"
		for g in "${BONUS[@]}"; do
			wanted "$g" || continue
			run_group "${LABEL[$g]}" "$g" "$TMP/bonus" "$g"
		done
	fi
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
