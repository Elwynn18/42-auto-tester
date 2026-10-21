#!/usr/bin/env bash
# **************************************************************************** #
#  test_ft_printf.sh - single-file ft_printf tester                            #
#                                                                              #
#  Usage (from your ft_printf folder):                                         #
#      bash ../test_ft_printf.sh             -> test everything                #
#      bash ../test_ft_printf.sh d x p       -> test only these conversions    #
#      bash ../test_ft_printf.sh bonus       -> test only the bonus            #
#      (groups: c s p d i u x X % mix | width - 0 . # + space combo)           #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Your libftprintf.a is built with YOUR Makefile (make / make bonus),       #
#    then each conversion is compared to the real printf (output AND return    #
#    value) in a separate program: a crash does not block the rest.            #
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

N_OK=0; N_KO=0; N_SKIP=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 20 ? 20 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }
# ("erreur": compiler messages in a French locale)
first_error() { grep -m1 -E "error|erreur|undefined|No rule|\*\*\*" "$1" | sed -E 's|^.*/||; s/^[[:space:]]+//' | cut -c1-150; }

# ------------------------------- Test groups -------------------------------- #
MAND=(c s p d i u x X pct mix)
BONUS=(width minus zero prec hash plus space combo)
declare -A LABEL=(
	[c]='%c' [s]='%s' [p]='%p' [d]='%d' [i]='%i' [u]='%u' [x]='%x' [X]='%X'
	[pct]='%%' [mix]='mixed'
	[width]='width (e.g. %5d)' [minus]="flag '-'" [zero]="flag '0'" [prec]="precision '.'"
	[hash]="flag '#'" [plus]="flag '+'" [space]="flag ' '" [combo]='combinations'
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
				echo "Unknown group: '$a'. Groups: c s p d i u x X % mix | bonus width - 0 . # + space combo" >&2
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
#ifdef __SANITIZE_ADDRESS__
# include <sanitizer/asan_interface.h>
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
		tst_fail("%s → %s (returns %d), expected %s (returns %d)",
			g_case, tst_qn(g_got, n), r1, tst_qn(g_exp, r2), r2);
}

#define CASE(d) (g_case = (d))
/* compares ft_printf(...) to the real printf (via snprintf) */
#define TD(desc, ...) do { int tst_r1; int tst_n; CASE(desc); tst_begin(); \
	tst_r1 = ft_printf(__VA_ARGS__); tst_n = tst_end(); \
	tst_cmp(tst_r1, tst_n, snprintf(g_exp, sizeof g_exp, __VA_ARGS__)); } while (0)
#define T(...) TD("ft_printf(" #__VA_ARGS__ ")", __VA_ARGS__)

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
}
EOF
	;;

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
}
EOF
	;;
esac
}

# C source of a test program for the given groups
gen_src() {
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
	n=$(grep -E "/$(basename "$src"):[0-9]+" | head -1 | sed -E 's/.*\.c:([0-9]+).*/\1/')
	[ -n "$n" ] && sed -n "${n}p" "$src" | sed -E 's/^[[:space:]]+//; s/^T\(/ft_printf(/; s/\);$/)/' | cut -c1-110
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
		msg "memory leak: $(grep -m1 -oE '[0-9]+ byte\(s\) leaked in [0-9]+ allocation\(s\)' "$err")"
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
	local label=$1 name=$2 lib=$3 src="$TMP/t_$2.c" bin="$TMP/t_$2" out rc res ok ko
	shift 3
	gen_src "$@" > "$src"
	if ! cc $SAN -g -w "$src" -o "$bin" -L"$lib" -lftprintf 2> "$TMP/cerr"; then
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
	out=$(cd "$TMP" && ASAN_OPTIONS="detect_leaks=1" timeout 10 "$bin" 2> "$TMP/rerr")
	rc=$?
	res=$(grep -m1 "^@@RESULT" <<< "$out")
	ok=$(awk '{print $2}' <<< "$res"); ko=$(awk '{print $3}' <<< "$res")
	if [ -n "$res" ] && [ "$ko" = 0 ] && ! grep -q "Sanitizer" "$TMP/rerr"; then
		line_ok "$label" "($ok tests)"
		return
	fi
	line_ko "$label"
	grep "^@@MSG " <<< "$out" | sed 's/^@@MSG //' | while IFS= read -r m; do msg "$m"; done
	if [ $rc -eq 124 ]; then
		msg "infinite loop (10 s timeout) during: $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	elif [ -z "$res" ]; then
		msg "crash during: $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	fi
	asan_report "$TMP/rerr" "$src"
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

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
