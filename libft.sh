#!/usr/bin/env bash
# **************************************************************************** #
#  test_libft.sh - testeur libft en un seul fichier                            #
#                                                                              #
#  Usage (depuis ton dossier Libft) :                                          #
#      bash ../test_libft.sh               -> teste tout                       #
#      bash ../test_libft.sh split itoa    -> teste seulement ces fonctions    #
# **************************************************************************** #

# ---------- Relance dans WSL si aucun compilateur (Git Bash sous Windows) ---- #
if ! command -v cc >/dev/null 2>&1; then
	if command -v wsl.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		MSYS_NO_PATHCONV=1 exec wsl.exe --cd "$(pwd -W)" -e bash -c \
			'exec bash "$(wslpath "$0")" "$@"' "$(cygpath -m "$0")" "$@"
	fi
	echo "Erreur : 'cc' introuvable. Lance ce script sous Linux / WSL." >&2
	exit 1
fi

DIR=$(pwd)
if [ ! -f "$DIR/libft.h" ]; then
	echo "Erreur : libft.h introuvable. Lance ce script depuis ton dossier Libft." >&2
	exit 1
fi

if [ -t 1 ]; then
	R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; D=$'\e[2m'; N=$'\e[0m'
else
	R=''; G=''; Y=''; B=''; D=''; N=''
fi

TMP=$(mktemp -d /tmp/test_libft.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/strict" "$TMP/obj" "$TMP/mk"

N_OK=0; N_KO=0; N_SKIP=0

section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %-18s ${G}OK${N}%s\n" "$1" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %-18s ${R}KO${N}\n" "$1"; N_KO=$((N_KO + 1)); }
line_skip() { printf "  %-18s ${D}-- %s${N}\n" "$1" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
first_error() { grep -m1 -E "error|erreur|undefined" "$1" | sed -E 's|^.*/||; s/^[[:space:]]+//' | cut -c1-150; }

# ---------------------------- Liste des fonctions --------------------------- #
PART1=(ft_isalpha ft_isdigit ft_isalnum ft_isascii ft_isprint ft_strlen ft_memset
	ft_bzero ft_memcpy ft_memmove ft_strlcpy ft_strlcat ft_toupper ft_tolower
	ft_strchr ft_strrchr ft_strncmp ft_memchr ft_memcmp ft_strnstr ft_atoi
	ft_calloc ft_strdup)
PART2=(ft_substr ft_strjoin ft_strtrim ft_split ft_itoa ft_strmapi ft_striteri
	ft_putchar_fd ft_putstr_fd ft_putendl_fd ft_putnbr_fd)
PART3=(ft_lstnew ft_lstadd_front ft_lstsize ft_lstlast ft_lstadd_back
	ft_lstdelone ft_lstclear ft_lstiter ft_lstmap)

declare -A PROTO=(
	[ft_isalpha]='int ft_isalpha(int c);'
	[ft_isdigit]='int ft_isdigit(int c);'
	[ft_isalnum]='int ft_isalnum(int c);'
	[ft_isascii]='int ft_isascii(int c);'
	[ft_isprint]='int ft_isprint(int c);'
	[ft_strlen]='size_t ft_strlen(const char *s);'
	[ft_memset]='void *ft_memset(void *s, int c, size_t n);'
	[ft_bzero]='void ft_bzero(void *s, size_t n);'
	[ft_memcpy]='void *ft_memcpy(void *dest, const void *src, size_t n);'
	[ft_memmove]='void *ft_memmove(void *dest, const void *src, size_t n);'
	[ft_strlcpy]='size_t ft_strlcpy(char *dst, const char *src, size_t size);'
	[ft_strlcat]='size_t ft_strlcat(char *dst, const char *src, size_t size);'
	[ft_toupper]='int ft_toupper(int c);'
	[ft_tolower]='int ft_tolower(int c);'
	[ft_strchr]='char *ft_strchr(const char *s, int c);'
	[ft_strrchr]='char *ft_strrchr(const char *s, int c);'
	[ft_strncmp]='int ft_strncmp(const char *s1, const char *s2, size_t n);'
	[ft_memchr]='void *ft_memchr(const void *s, int c, size_t n);'
	[ft_memcmp]='int ft_memcmp(const void *s1, const void *s2, size_t n);'
	[ft_strnstr]='char *ft_strnstr(const char *big, const char *little, size_t len);'
	[ft_atoi]='int ft_atoi(const char *nptr);'
	[ft_calloc]='void *ft_calloc(size_t nmemb, size_t size);'
	[ft_strdup]='char *ft_strdup(const char *s);'
	[ft_substr]='char *ft_substr(char const *s, unsigned int start, size_t len);'
	[ft_strjoin]='char *ft_strjoin(char const *s1, char const *s2);'
	[ft_strtrim]='char *ft_strtrim(char const *s1, char const *set);'
	[ft_split]='char **ft_split(char const *s, char c);'
	[ft_itoa]='char *ft_itoa(int n);'
	[ft_strmapi]='char *ft_strmapi(char const *s, char (*f)(unsigned int, char));'
	[ft_striteri]='void ft_striteri(char *s, void (*f)(unsigned int, char *));'
	[ft_putchar_fd]='void ft_putchar_fd(char c, int fd);'
	[ft_putstr_fd]='void ft_putstr_fd(char *s, int fd);'
	[ft_putendl_fd]='void ft_putendl_fd(char *s, int fd);'
	[ft_putnbr_fd]='void ft_putnbr_fd(int n, int fd);'
	[ft_lstnew]='t_list *ft_lstnew(void *content);'
	[ft_lstadd_front]='void ft_lstadd_front(t_list **lst, t_list *new);'
	[ft_lstsize]='unsigned int ft_lstsize(t_list *lst);'
	[ft_lstlast]='t_list *ft_lstlast(t_list *lst);'
	[ft_lstadd_back]='void ft_lstadd_back(t_list **lst, t_list *new);'
	[ft_lstdelone]='void ft_lstdelone(t_list *lst, void (*del)(void *));'
	[ft_lstclear]='void ft_lstclear(t_list **lst, void (*del)(void *));'
	[ft_lstiter]='void ft_lstiter(t_list *lst, void (*f)(void *));'
	[ft_lstmap]='t_list *ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));'
)

# Filtre éventuel passé en argument (ex: "split" ou "ft_split")
declare -A WANTED=()
for a in "$@"; do WANTED["ft_${a#ft_}"]=1; done
wanted() { [ ${#WANTED[@]} -eq 0 ] || [ -n "${WANTED[$1]}" ]; }

# ------------------------- Préambule C commun aux tests --------------------- #
prelude() { cat <<'EOF'
#include "libft.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <signal.h>
#ifdef __SANITIZE_ADDRESS__
# include <sanitizer/asan_interface.h>
# include <sanitizer/lsan_interface.h>
/* vérifie les fuites tout de suite (utile avant un test qui peut crasher) */
# define LEAK_CHECK() __lsan_do_recoverable_leak_check()
#else
# define LEAK_CHECK() ((void)0)
#endif

static int			g_ok = 0;
static int			g_ko = 0;
static const char	*g_case = "début du test";
static int			g_malloc_fail = 0;

/* malloc truqué : le g_malloc_fail-ième appel renvoie NULL */
void	*__real_malloc(size_t size);
void	*__wrap_malloc(size_t size)
{
	if (g_malloc_fail > 0 && --g_malloc_fail == 0)
		return (NULL);
	return (__real_malloc(size));
}
#define FAIL_MALLOC(n) (g_malloc_fail = (n))
#define MALLOC_TRIGGERED() (g_malloc_fail == 0)

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

static const char	*tst_q(const char *s)
{
	static char	bufs[6][160];
	static int	k = 0;
	char		*b;
	int			j = 0;

	if (!s)
		return ("NULL");
	b = bufs[k++ % 6];
	b[j++] = '"';
	for (int i = 0; s[i] && j < 140; i++)
	{
		unsigned char c = s[i];
		if (c == '\n')
			j += sprintf(b + j, "\\n");
		else if (c == '\t')
			j += sprintf(b + j, "\\t");
		else if (c < 32 || c > 126)
			j += sprintf(b + j, "\\x%02x", c);
		else
			b[j++] = c;
	}
	b[j++] = '"';
	b[j] = 0;
	return (b);
}

static const char	*tst_off(const void *p, const void *base)
{
	static char	bufs[4][32];
	static int	k = 0;
	char		*b;

	if (!p)
		return ("NULL");
	b = bufs[k++ % 4];
	snprintf(b, 32, "s + %td", (const char *)p - (const char *)base);
	return (b);
}

static void	tst_str(const char *d, const char *got, const char *exp)
{
	if ((!got && !exp) || (got && exp && strcmp(got, exp) == 0))
		g_ok++;
	else
		tst_fail("%s → %s, attendu %s", d, tst_q(got), tst_q(exp));
}

#define CASE(d) (g_case = (d))
#define CHECK(d, cond) do { CASE(d); if (cond) g_ok++; \
	else tst_fail("%s", d); } while (0)
#define CHECK_STR(d, expr, exp) do { CASE(d); \
	const char *tst_r = (const char *)(expr); tst_str(d, tst_r, exp); } while (0)
#define CHECK_STRF(d, expr, exp) do { CASE(d); \
	char *tst_r = (char *)(expr); tst_str(d, tst_r, exp); free(tst_r); } while (0)
#define CHECK_INT(d, expr, exp) do { CASE(d); long long tst_g = (long long)(expr); \
	long long tst_e = (long long)(exp); if (tst_g == tst_e) g_ok++; \
	else tst_fail("%s → %lld, attendu %lld", d, tst_g, tst_e); } while (0)
#define SIGN(x) (((x) > 0) - ((x) < 0))
#define CHECK_SIGN(d, expr, exp) do { CASE(d); int tst_g = (expr); int tst_e = (exp); \
	if (SIGN(tst_g) == SIGN(tst_e)) g_ok++; \
	else tst_fail("%s → %d, attendu une valeur %s", d, tst_g, \
		tst_e > 0 ? "> 0" : tst_e < 0 ? "< 0" : "= 0"); } while (0)
#define CHECK_PTR(d, expr, exp, base) do { CASE(d); const void *tst_g = (expr); \
	const void *tst_e = (exp); if (tst_g == tst_e) g_ok++; \
	else tst_fail("%s → %s, attendu %s", d, tst_off(tst_g, base), \
		tst_off(tst_e, base)); } while (0)

/* capture de ce qui est écrit sur un fd */
static int	tst_fds[2];
static int	tst_cap(void)
{
	if (pipe(tst_fds) != 0)
	{
		perror("pipe");
		exit(1);
	}
	return (tst_fds[1]);
}
static const char	*tst_captured(void)
{
	static char	buf[512];
	size_t		t = 0;
	ssize_t		n;

	close(tst_fds[1]);
	while (t < sizeof(buf) - 1
		&& (n = read(tst_fds[0], buf + t, sizeof(buf) - 1 - t)) > 0)
		t += n;
	buf[t] = 0;
	close(tst_fds[0]);
	return (buf);
}

static void	tst_on_death(void)
{
	if (g_case)
		printf("\n@@CRASH %s\n", g_case);
}

static void	tst_on_signal(int sig)
{
	printf("\n@@CRASH %s\n@@SIGNAL %d\n", g_case, sig);
	_exit(128 + sig);
}

static void	tst_run(void);

int	main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
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

# Fonctions utilitaires pour les tests de listes
list_helpers() { cat <<'EOF'
static t_list	*tst_node(void *content)
{
	t_list	*n = malloc(sizeof(t_list));

	n->content = content;
	n->next = NULL;
	return (n);
}
static int	g_del = 0;
static void	tst_del(void *p)
{
	g_del++;
	free(p);
}
EOF
}

# ------------------------------- Corps des tests ---------------------------- #
body() {
case "$1" in

ft_isalpha|ft_isdigit|ft_isalnum|ft_isascii|ft_isprint)
	sed "s/FN/${1#ft_}/g" <<'EOF'
static void	tst_run(void)
{
	char	d[64];

	for (int c = -1; c <= 255; c++)
	{
		int want = FN(c) ? 1 : 0;
		snprintf(d, sizeof d, "ft_FN(%d)", c);
		CHECK_INT(d, ft_FN(c), want);
	}
	CHECK_INT("ft_FN(256)", ft_FN(256), 0);
	CHECK_INT("ft_FN(INT_MIN)", ft_FN(INT_MIN), 0);
}
EOF
	;;

ft_toupper|ft_tolower)
	sed "s/FN/${1#ft_}/g" <<'EOF'
static void	tst_run(void)
{
	char	d[64];

	for (int c = -1; c <= 255; c++)
	{
		snprintf(d, sizeof d, "ft_FN(%d)", c);
		CHECK_INT(d, ft_FN(c), FN(c));
	}
	CHECK_INT("ft_FN(1000)", ft_FN(1000), 1000);
}
EOF
	;;

ft_strlen) cat <<'EOF'
static void	tst_run(void)
{
	char	*big = malloc(1001);

	memset(big, 'a', 1000);
	big[1000] = 0;
	CHECK_INT("ft_strlen(\"\")", ft_strlen(""), 0);
	CHECK_INT("ft_strlen(\"a\")", ft_strlen("a"), 1);
	CHECK_INT("ft_strlen(\"hello world\")", ft_strlen("hello world"), 11);
	CHECK_INT("ft_strlen(\"ab\\0cd\")", ft_strlen("ab\0cd"), 2);
	CHECK_INT("ft_strlen(1000 x 'a')", ft_strlen(big), 1000);
	free(big);
}
EOF
	;;

ft_memset) cat <<'EOF'
static void	tst_run(void)
{
	unsigned char	a[32];
	unsigned char	b[32];
	void			*r;

	memset(a, '.', 32);
	memset(b, '.', 32);
	CASE("ft_memset(buf, 'x', 10)");
	r = ft_memset(a, 'x', 10);
	memset(b, 'x', 10);
	CHECK("ft_memset(buf, 'x', 10) : contenu du buffer", !memcmp(a, b, 32));
	CHECK("ft_memset(buf, 'x', 10) : doit renvoyer buf", r == a);
	CASE("ft_memset(buf + 5, 'y', 0)");
	ft_memset(a + 5, 'y', 0);
	CHECK("ft_memset(buf + 5, 'y', 0) : ne doit rien modifier", !memcmp(a, b, 32));
	CASE("ft_memset(buf + 3, 'A' + 256, 5)");
	ft_memset(a + 3, 'A' + 256, 5);
	memset(b + 3, 'A' + 256, 5);
	CHECK("ft_memset(buf + 3, 'A' + 256, 5) : c doit être converti en unsigned char", !memcmp(a, b, 32));
	CASE("ft_memset(buf, -1, 4)");
	ft_memset(a, -1, 4);
	memset(b, -1, 4);
	CHECK("ft_memset(buf, -1, 4) : doit écrire 0xff", !memcmp(a, b, 32));
	CASE("ft_memset(buf, 0, 32)");
	ft_memset(a, 0, 32);
	memset(b, 0, 32);
	CHECK("ft_memset(buf, 0, 32)", !memcmp(a, b, 32));
}
EOF
	;;

ft_bzero) cat <<'EOF'
static void	tst_run(void)
{
	unsigned char	a[32];
	unsigned char	b[32];

	memset(a, 'x', 32);
	memset(b, 'x', 32);
	CASE("ft_bzero(buf + 2, 5)");
	ft_bzero(a + 2, 5);
	memset(b + 2, 0, 5);
	CHECK("ft_bzero(buf + 2, 5) : contenu du buffer", !memcmp(a, b, 32));
	CASE("ft_bzero(buf, 0)");
	ft_bzero(a, 0);
	CHECK("ft_bzero(buf, 0) : ne doit rien modifier", !memcmp(a, b, 32));
	CASE("ft_bzero(buf, 32)");
	ft_bzero(a, 32);
	memset(b, 0, 32);
	CHECK("ft_bzero(buf, 32)", !memcmp(a, b, 32));
}
EOF
	;;

ft_memcpy) cat <<'EOF'
static void	tst_run(void)
{
	const char	src[] = "abc\0def\0ghi";
	char		a[16];
	char		b[16];
	void		*r;

	memset(a, '.', 16);
	memset(b, '.', 16);
	CASE("ft_memcpy(dst, \"abc\\0def\\0ghi\", 12)");
	r = ft_memcpy(a, src, 12);
	memcpy(b, src, 12);
	CHECK("ft_memcpy(dst, \"abc\\0def\\0ghi\", 12) : doit copier au-delà des \\0", !memcmp(a, b, 16));
	CHECK("ft_memcpy(dst, src, 12) : doit renvoyer dst", r == a);
	CASE("ft_memcpy(dst, \"zzz\", 0)");
	ft_memcpy(a, "zzz", 0);
	CHECK("ft_memcpy(dst, \"zzz\", 0) : ne doit rien modifier", !memcmp(a, b, 16));
	CASE("ft_memcpy(dst + 4, \"XY\", 2)");
	ft_memcpy(a + 4, "XY", 2);
	memcpy(b + 4, "XY", 2);
	CHECK("ft_memcpy(dst + 4, \"XY\", 2)", !memcmp(a, b, 16));
}
EOF
	;;

ft_memmove) cat <<'EOF'
static void	tst_run(void)
{
	char	a[32];
	char	b[32];
	void	*r;

	memset(a, 0, 32); strcpy(a, "0123456789abcdef"); memcpy(b, a, 32);
	CASE("ft_memmove(s + 2, s, 10)");
	r = ft_memmove(a + 2, a, 10);
	memmove(b + 2, b, 10);
	CHECK("ft_memmove(s + 2, s, 10) : chevauchement avec dst > src", !memcmp(a, b, 32));
	CHECK("ft_memmove(s + 2, s, 10) : doit renvoyer dst", r == a + 2);
	memset(a, 0, 32); strcpy(a, "0123456789abcdef"); memcpy(b, a, 32);
	CASE("ft_memmove(s, s + 2, 10)");
	ft_memmove(a, a + 2, 10);
	memmove(b, b + 2, 10);
	CHECK("ft_memmove(s, s + 2, 10) : chevauchement avec dst < src", !memcmp(a, b, 32));
	CASE("ft_memmove(s, s, 10)");
	ft_memmove(a, a, 10);
	CHECK("ft_memmove(s, s, 10) : ne doit rien changer", !memcmp(a, b, 32));
	CASE("ft_memmove(s + 20, s, 5)");
	ft_memmove(a + 20, a, 5);
	memmove(b + 20, b, 5);
	CHECK("ft_memmove(s + 20, s, 5) : sans chevauchement", !memcmp(a, b, 32));
	CASE("ft_memmove(s, s + 1, 0)");
	ft_memmove(a, a + 1, 0);
	CHECK("ft_memmove(s, s + 1, 0) : ne doit rien modifier", !memcmp(a, b, 32));
}
EOF
	;;

ft_strlcpy|ft_strlcat) sed "s/FN/${1#ft_}/g" <<'EOF'
static size_t	tst_ref_strlcpy(char *d, const char *s, size_t n)
{
	size_t	l = strlen(s);
	size_t	c;

	if (n)
	{
		c = (l >= n) ? n - 1 : l;
		memcpy(d, s, c);
		d[c] = 0;
	}
	return (l);
}

static size_t	tst_ref_strlcat(char *d, const char *s, size_t n)
{
	size_t	dl = 0;
	size_t	sl = strlen(s);
	size_t	i = 0;

	while (dl < n && d[dl])
		dl++;
	if (dl == n)
		return (n + sl);
	while (s[i] && dl + i + 1 < n)
	{
		d[dl + i] = s[i];
		i++;
	}
	d[dl + i] = 0;
	return (dl + sl);
}

static void	tst_run(void)
{
	const char	*dsts[] = {"abc", "", "abcdefgh"};
	const char	*srcs[] = {"hello", "", "a longer source"};
	size_t		sizes[] = {0, 1, 2, 3, 4, 6, 8, 9, 10, 12, 20, 32};
	char		a[33];
	char		b[33];
	char		d[160];
	size_t		ra;
	size_t		rb;

	for (int x = 0; x < 3; x++)
		for (int y = 0; y < 3; y++)
			for (int z = 0; z < 12; z++)
			{
				memset(a, 'Z', 32); a[32] = 0; strcpy(a, dsts[x]);
				memcpy(b, a, 33);
				snprintf(d, sizeof d, "ft_FN(dst = %s, %s, %zu)",
					tst_q(dsts[x]), tst_q(srcs[y]), sizes[z]);
				CASE(d);
				ra = ft_FN(a, srcs[y], sizes[z]);
				rb = tst_ref_FN(b, srcs[y], sizes[z]);
				if (ra == rb && !memcmp(a, b, 33))
					g_ok++;
				else
					tst_fail("%s → retour %zu, dst %s ; attendu retour %zu, dst %s",
						d, ra, tst_q(a), rb, tst_q(b));
			}
}
EOF
	;;

ft_strchr|ft_strrchr) sed "s/FN/${1#ft_}/g" <<'EOF'
static void	tst_run(void)
{
	struct { const char *s; int c; const char *desc; } t[] = {
		{"hello world", 'h', "ft_FN(\"hello world\", 'h')"},
		{"hello world", 'o', "ft_FN(\"hello world\", 'o')"},
		{"hello world", 'l', "ft_FN(\"hello world\", 'l')"},
		{"hello world", 'd', "ft_FN(\"hello world\", 'd')"},
		{"hello world", 'z', "ft_FN(\"hello world\", 'z')"},
		{"hello world", '\0', "ft_FN(\"hello world\", '\\0')"},
		{"hello world", 'o' + 256, "ft_FN(\"hello world\", 'o' + 256)"},
		{"", 'a', "ft_FN(\"\", 'a')"},
		{"", '\0', "ft_FN(\"\", '\\0')"},
		{"caf\xe9!", 0xe9, "ft_FN(\"caf\\xe9!\", 0xe9)"},
		{"caf\xe9!", (char)0xe9, "ft_FN(\"caf\\xe9!\", (char)0xe9)"},
	};

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		char *s = strdup(t[i].s);
		CHECK_PTR(t[i].desc, ft_FN(s, t[i].c), FN(s, t[i].c), s);
		free(s);
	}
}
EOF
	;;

ft_strncmp) cat <<'EOF'
static void	tst_run(void)
{
	struct { const char *a; const char *b; size_t n; } t[] = {
		{"abc", "abc", 3}, {"abc", "abd", 3}, {"abd", "abc", 3},
		{"abc", "abd", 2}, {"abc", "ab", 3}, {"ab", "abc", 3},
		{"ab", "abc", 2}, {"", "", 1}, {"", "a", 1}, {"abc", "xyz", 0},
		{"\x80", "", 1}, {"test\xc8", "test", 6}, {"abc", "abc", 100},
		{"abc", "abcd", SIZE_MAX},
	};
	char	d[160];

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		char *a = strdup(t[i].a);
		char *b = strdup(t[i].b);
		snprintf(d, sizeof d, "ft_strncmp(%s, %s, %zu)", tst_q(a), tst_q(b), t[i].n);
		CHECK_SIGN(d, ft_strncmp(a, b, t[i].n), strncmp(a, b, t[i].n));
		free(a);
		free(b);
	}
}
EOF
	;;

ft_memchr) cat <<'EOF'
static void	tst_run(void)
{
	char	s[] = "ab\0cd\xff";
	struct { int c; size_t n; const char *desc; } t[] = {
		{'a', 6, "ft_memchr(\"ab\\0cd\\xff\", 'a', 6)"},
		{'c', 6, "ft_memchr(\"ab\\0cd\\xff\", 'c', 6) (après le \\0)"},
		{'c', 3, "ft_memchr(\"ab\\0cd\\xff\", 'c', 3)"},
		{'\0', 6, "ft_memchr(\"ab\\0cd\\xff\", '\\0', 6)"},
		{'z', 6, "ft_memchr(\"ab\\0cd\\xff\", 'z', 6)"},
		{'c' + 256, 6, "ft_memchr(\"ab\\0cd\\xff\", 'c' + 256, 6)"},
		{0xff, 6, "ft_memchr(\"ab\\0cd\\xff\", 0xff, 6)"},
		{-1, 6, "ft_memchr(\"ab\\0cd\\xff\", -1, 6)"},
		{'a', 0, "ft_memchr(\"ab\\0cd\\xff\", 'a', 0)"},
	};

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
		CHECK_PTR(t[i].desc, ft_memchr(s, t[i].c, t[i].n), memchr(s, t[i].c, t[i].n), s);
}
EOF
	;;

ft_memcmp) cat <<'EOF'
static void	tst_run(void)
{
	struct { const char *a; const char *b; size_t n; const char *desc; } t[] = {
		{"abc", "abc", 3, "ft_memcmp(\"abc\", \"abc\", 3)"},
		{"abc", "abd", 3, "ft_memcmp(\"abc\", \"abd\", 3)"},
		{"abd", "abc", 3, "ft_memcmp(\"abd\", \"abc\", 3)"},
		{"abc", "abd", 2, "ft_memcmp(\"abc\", \"abd\", 2)"},
		{"ab\0c", "ab\0d", 4, "ft_memcmp(\"ab\\0c\", \"ab\\0d\", 4) (après le \\0)"},
		{"\xff", "\x01", 1, "ft_memcmp(\"\\xff\", \"\\x01\", 1) (unsigned char)"},
		{"\x01", "\xff", 1, "ft_memcmp(\"\\x01\", \"\\xff\", 1) (unsigned char)"},
		{"abc", "xyz", 0, "ft_memcmp(\"abc\", \"xyz\", 0)"},
	};

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
		CHECK_SIGN(t[i].desc, ft_memcmp(t[i].a, t[i].b, t[i].n), memcmp(t[i].a, t[i].b, t[i].n));
}
EOF
	;;

ft_strnstr) cat <<'EOF'
static char	*tst_ref_strnstr(const char *b, const char *l, size_t len)
{
	size_t	ll = strlen(l);

	if (!ll)
		return ((char *)b);
	for (size_t i = 0; i < len && b[i]; i++)
		if (ll <= len - i && !strncmp(b + i, l, ll))
			return ((char *)b + i);
	return (NULL);
}

static void	tst_run(void)
{
	struct { const char *b; const char *l; size_t n; } t[] = {
		{"hello world", "world", 11}, {"hello world", "world", 10},
		{"hello world", "hello", 5}, {"hello world", "hello", 4},
		{"hello world", "", 0}, {"hello world", "", 5},
		{"hello world", "o", 5}, {"abcdef", "cd", 3}, {"abcdef", "cd", 4},
		{"aaab", "aab", 4}, {"abc", "abcd", 10}, {"", "", 0}, {"", "a", 5},
		{"lorem ipsum", "ipsum", 30}, {"abc", "c", SIZE_MAX}, {"abc", "x", 100},
	};
	char	d[160];

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		char *b = strdup(t[i].b);
		snprintf(d, sizeof d, "ft_strnstr(%s, %s, %zu)", tst_q(b), tst_q(t[i].l), t[i].n);
		CHECK_PTR(d, ft_strnstr(b, t[i].l, t[i].n), tst_ref_strnstr(b, t[i].l, t[i].n), b);
		free(b);
	}
}
EOF
	;;

ft_atoi) cat <<'EOF'
static void	tst_run(void)
{
	const char	*t[] = {"42", "-42", "+42", "0", "-0", "   42", "\t\n\v\f\r 42",
		"   -42abc", "42 43", "+-42", "-+42", "--42", "++42", " + 42", "abc", "",
		"00042", "2147483647", "-2147483648", "\x80 42", "-", "+"};
	char		d[160];

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		char *s = strdup(t[i]);
		snprintf(d, sizeof d, "ft_atoi(%s)", tst_q(s));
		CHECK_INT(d, ft_atoi(s), atoi(s));
		free(s);
	}
}
EOF
	;;

ft_calloc) cat <<'EOF'
static void	tst_run(void)
{
	unsigned char	*p;
	int				zero;

	CASE("ft_calloc(5, 4)");
	p = ft_calloc(5, 4);
	CHECK("ft_calloc(5, 4) : ne doit pas renvoyer NULL", p != NULL);
	if (p)
	{
		zero = 1;
		for (int i = 0; i < 20; i++)
			if (p[i])
				zero = 0;
		CHECK("ft_calloc(5, 4) : les 20 octets doivent valoir 0", zero);
		free(p);
	}
	CASE("ft_calloc(0, 0)");
	p = ft_calloc(0, 0);
	CHECK("ft_calloc(0, 0) : doit renvoyer un pointeur unique libérable (pas NULL)", p != NULL);
	free(p);
	CASE("ft_calloc(0, 5)");
	p = ft_calloc(0, 5);
	CHECK("ft_calloc(0, 5) : doit renvoyer un pointeur unique libérable (pas NULL)", p != NULL);
	free(p);
	CASE("ft_calloc(SIZE_MAX / 2 + 1, 2)");
	p = ft_calloc(SIZE_MAX / 2 + 1, 2);
	CHECK("ft_calloc(SIZE_MAX / 2 + 1, 2) : nmemb * size dépasse SIZE_MAX, doit renvoyer NULL", p == NULL);
	free(p);
	CASE("ft_calloc(4, 4) avec malloc qui échoue");
	FAIL_MALLOC(1);
	p = ft_calloc(4, 4);
	FAIL_MALLOC(0);
	CHECK("ft_calloc(4, 4) : doit renvoyer NULL si malloc échoue", p == NULL);
	free(p);
}
EOF
	;;

ft_strdup) cat <<'EOF'
static void	tst_run(void)
{
	const char	*s = "abc";
	char		*r;

	CHECK_STRF("ft_strdup(\"hello\")", ft_strdup("hello"), "hello");
	CHECK_STRF("ft_strdup(\"\")", ft_strdup(""), "");
	CHECK_STRF("ft_strdup(\"a b\\tc\")", ft_strdup("a b\tc"), "a b\tc");
	CASE("ft_strdup(s)");
	r = ft_strdup(s);
	CHECK("ft_strdup(s) : doit renvoyer une nouvelle zone mémoire", r != s);
	free(r);
	FAIL_MALLOC(1);
	CHECK_STRF("ft_strdup(\"abc\") avec malloc qui échoue", ft_strdup("abc"), NULL);
	FAIL_MALLOC(0);
}
EOF
	;;

ft_substr) cat <<'EOF'
static void	tst_run(void)
{
	char	*s = strdup("hello world");
	char	*e = strdup("");

	CHECK_STRF("ft_substr(\"hello world\", 6, 5)", ft_substr(s, 6, 5), "world");
	CHECK_STRF("ft_substr(\"hello world\", 0, 5)", ft_substr(s, 0, 5), "hello");
	CHECK_STRF("ft_substr(\"hello world\", 0, 11)", ft_substr(s, 0, 11), "hello world");
	CHECK_STRF("ft_substr(\"hello world\", 3, 0)", ft_substr(s, 3, 0), "");
	CHECK_STRF("ft_substr(\"hello world\", 6, 100)", ft_substr(s, 6, 100), "world");
	CHECK_STRF("ft_substr(\"hello world\", 11, 5)", ft_substr(s, 11, 5), "");
	CHECK_STRF("ft_substr(\"hello world\", 100, 5)", ft_substr(s, 100, 5), "");
	CHECK_STRF("ft_substr(\"\", 0, 1)", ft_substr(e, 0, 1), "");
	CHECK_STRF("ft_substr(\"\", 1, 1)", ft_substr(e, 1, 1), "");
	FAIL_MALLOC(1);
	CHECK_STRF("ft_substr(\"hello world\", 0, 5) avec malloc qui échoue", ft_substr(s, 0, 5), NULL);
	FAIL_MALLOC(0);
	CHECK_STRF("ft_substr(\"hello world\", 3, SIZE_MAX)", ft_substr(s, 3, SIZE_MAX), "lo world");
	free(s);
	free(e);
}
EOF
	;;

ft_strjoin) cat <<'EOF'
static void	tst_run(void)
{
	CHECK_STRF("ft_strjoin(\"abc\", \"def\")", ft_strjoin("abc", "def"), "abcdef");
	CHECK_STRF("ft_strjoin(\"abc\", \"\")", ft_strjoin("abc", ""), "abc");
	CHECK_STRF("ft_strjoin(\"\", \"def\")", ft_strjoin("", "def"), "def");
	CHECK_STRF("ft_strjoin(\"\", \"\")", ft_strjoin("", ""), "");
	FAIL_MALLOC(1);
	CHECK_STRF("ft_strjoin(\"abc\", \"def\") avec malloc qui échoue", ft_strjoin("abc", "def"), NULL);
	FAIL_MALLOC(0);
}
EOF
	;;

ft_strtrim) cat <<'EOF'
static void	tst_run(void)
{
	CHECK_STRF("ft_strtrim(\"  hello  \", \" \")", ft_strtrim("  hello  ", " "), "hello");
	CHECK_STRF("ft_strtrim(\"xxhixx\", \"x\")", ft_strtrim("xxhixx", "x"), "hi");
	CHECK_STRF("ft_strtrim(\"a b c\", \" \")", ft_strtrim("a b c", " "), "a b c");
	CHECK_STRF("ft_strtrim(\"  a b c  \", \" \")", ft_strtrim("  a b c  ", " "), "a b c");
	CHECK_STRF("ft_strtrim(\"-+-hello-+-world-+-\", \"-+\")",
		ft_strtrim("-+-hello-+-world-+-", "-+"), "hello-+-world");
	CHECK_STRF("ft_strtrim(\"abc\", \"\")", ft_strtrim("abc", ""), "abc");
	CHECK_STRF("ft_strtrim(\"   \", \" \")", ft_strtrim("   ", " "), "");
	CHECK_STRF("ft_strtrim(\"\", \" \")", ft_strtrim("", " "), "");
	CHECK_STRF("ft_strtrim(\"abc\", \"cba\")", ft_strtrim("abc", "cba"), "");
	FAIL_MALLOC(1);
	CHECK_STRF("ft_strtrim(\" ab \", \" \") avec malloc qui échoue", ft_strtrim(" ab ", " "), NULL);
	FAIL_MALLOC(0);
}
EOF
	;;

ft_split) cat <<'EOF'
static void	tst_free_tab(char **t)
{
	for (int i = 0; t && t[i]; i++)
		free(t[i]);
	free(t);
}

static void	tst_split_check(const char *d, char **r, const char **exp)
{
	int	i = 0;

	if (!r)
	{
		tst_fail("%s → NULL", d);
		return ;
	}
	while (exp[i] && r[i] && !strcmp(r[i], exp[i]))
		i++;
	if (!exp[i] && !r[i])
		g_ok++;
	else
		tst_fail("%s → case [%d] = %s, attendu %s", d, i, tst_q(r[i]), tst_q(exp[i]));
	tst_free_tab(r);
}

#define CHECK_SPLIT(d, s, c, ...) do { const char *tst_e[] = {__VA_ARGS__, NULL}; \
	char *tst_s = strdup(s); CASE(d); tst_split_check(d, ft_split(tst_s, c), tst_e); \
	free(tst_s); } while (0)

static void	tst_run(void)
{
	char	d[96];
	char	**r;

	CHECK_SPLIT("ft_split(\"hello world foo\", ' ')", "hello world foo", ' ', "hello", "world", "foo");
	CHECK_SPLIT("ft_split(\"   hello   world   \", ' ')", "   hello   world   ", ' ', "hello", "world");
	CHECK_SPLIT("ft_split(\"hello\", ' ')", "hello", ' ', "hello");
	CHECK_SPLIT("ft_split(\"\", ' ')", "", ' ', NULL);
	CHECK_SPLIT("ft_split(\"     \", ' ')", "     ", ' ', NULL);
	CHECK_SPLIT("ft_split(\"a,b,,c,\", ',')", "a,b,,c,", ',', "a", "b", "c");
	CHECK_SPLIT("ft_split(\"xxhelloxxworldxx\", 'x')", "xxhelloxxworldxx", 'x', "hello", "world");
	for (int n = 1; n <= 4; n++)
	{
		snprintf(d, sizeof d, "ft_split(\"aa bb cc\", ' ') avec le malloc n°%d qui échoue", n);
		CASE(d);
		FAIL_MALLOC(n);
		r = ft_split("aa bb cc", ' ');
		if (MALLOC_TRIGGERED())
			CHECK(d, r == NULL);
		FAIL_MALLOC(0);
		tst_free_tab(r);
	}
	LEAK_CHECK();
	CHECK_SPLIT("ft_split(\"hello\", '\\0')", "hello", '\0', "hello");
}
EOF
	;;

ft_itoa) cat <<'EOF'
static void	tst_run(void)
{
	int		t[] = {0, 1, -1, 9, -9, 10, -10, 42, -42, 100, 105, 1000, -1000,
		123456789, INT_MAX, INT_MIN, INT_MIN + 1};
	char	d[64];
	char	e[32];

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		snprintf(d, sizeof d, "ft_itoa(%d)", t[i]);
		snprintf(e, sizeof e, "%d", t[i]);
		CHECK_STRF(d, ft_itoa(t[i]), e);
	}
	FAIL_MALLOC(1);
	CHECK_STRF("ft_itoa(42) avec malloc qui échoue", ft_itoa(42), NULL);
	FAIL_MALLOC(0);
}
EOF
	;;

ft_strmapi) cat <<'EOF'
static char	tst_map(unsigned int i, char c)
{
	return ((i % 2) ? toupper(c) : c);
}

static void	tst_run(void)
{
	char	*s = strdup("hello world");

	CHECK_STRF("ft_strmapi(\"hello world\", f) avec f = majuscule aux index impairs",
		ft_strmapi(s, tst_map), "hElLo wOrLd");
	CHECK("ft_strmapi : ne doit pas modifier la chaîne d'origine", !strcmp(s, "hello world"));
	CHECK_STRF("ft_strmapi(\"\", f)", ft_strmapi("", tst_map), "");
	FAIL_MALLOC(1);
	CHECK_STRF("ft_strmapi(\"abc\", f) avec malloc qui échoue", ft_strmapi("abc", tst_map), NULL);
	FAIL_MALLOC(0);
	free(s);
}
EOF
	;;

ft_striteri) cat <<'EOF'
static char	*g_base;
static int	g_bad = 0;

static void	tst_iter(unsigned int i, char *c)
{
	if (c != g_base + i)
		g_bad = 1;
	if (i % 2)
		*c = toupper(*c);
}

static void	tst_run(void)
{
	char	*s = strdup("hello world");
	char	e[1] = "";

	g_base = s;
	CASE("ft_striteri(\"hello world\", f)");
	ft_striteri(s, tst_iter);
	CHECK_STR("ft_striteri(\"hello world\", f) avec f = majuscule aux index impairs", s, "hElLo wOrLd");
	CHECK("ft_striteri : f doit recevoir l'index i et l'adresse &s[i]", !g_bad);
	g_base = e;
	CASE("ft_striteri(\"\", f)");
	ft_striteri(e, tst_iter);
	CHECK("ft_striteri(\"\", f) : ne doit rien faire", e[0] == 0);
	free(s);
}
EOF
	;;

ft_putchar_fd) cat <<'EOF'
static void	tst_run(void)
{
	CASE("ft_putchar_fd('a', fd)");
	ft_putchar_fd('a', tst_cap());
	CHECK_STR("ft_putchar_fd('a', fd)", tst_captured(), "a");
	CASE("ft_putchar_fd('\\n', fd)");
	ft_putchar_fd('\n', tst_cap());
	CHECK_STR("ft_putchar_fd('\\n', fd)", tst_captured(), "\n");
	CASE("ft_putchar_fd((char)0xe9, fd)");
	ft_putchar_fd((char)0xe9, tst_cap());
	CHECK_STR("ft_putchar_fd((char)0xe9, fd)", tst_captured(), "\xe9");
}
EOF
	;;

ft_putstr_fd|ft_putendl_fd)
	local nl=''
	[ "$1" = ft_putendl_fd ] && nl='\\n'
	sed "s/FN/${1#ft_}/g; s/NL/$nl/g" <<'EOF'
static void	tst_run(void)
{
	char	*s = strdup("hello world");
	char	*e = strdup("");

	CASE("ft_FN(\"hello world\", fd)");
	ft_FN(s, tst_cap());
	CHECK_STR("ft_FN(\"hello world\", fd)", tst_captured(), "hello worldNL");
	CASE("ft_FN(\"\", fd)");
	ft_FN(e, tst_cap());
	CHECK_STR("ft_FN(\"\", fd)", tst_captured(), "NL");
	free(s);
	free(e);
}
EOF
	;;

ft_putnbr_fd) cat <<'EOF'
static void	tst_run(void)
{
	int		t[] = {0, 5, -5, 10, -10, 42, -42, 100, 123456, INT_MAX, INT_MIN};
	char	d[64];
	char	e[32];

	for (size_t i = 0; i < sizeof t / sizeof *t; i++)
	{
		snprintf(d, sizeof d, "ft_putnbr_fd(%d, fd)", t[i]);
		snprintf(e, sizeof e, "%d", t[i]);
		CASE(d);
		ft_putnbr_fd(t[i], tst_cap());
		CHECK_STR(d, tst_captured(), e);
	}
}
EOF
	;;

ft_lstnew) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	int		x = 42;
	t_list	*n;

	CASE("ft_lstnew(&x)");
	n = ft_lstnew(&x);
	CHECK("ft_lstnew(&x) : ne doit pas renvoyer NULL", n != NULL);
	if (n)
	{
		CHECK("ft_lstnew(&x) : content doit valoir &x", n->content == &x);
		CHECK("ft_lstnew(&x) : next doit valoir NULL", n->next == NULL);
		free(n);
	}
	CASE("ft_lstnew(NULL)");
	n = ft_lstnew(NULL);
	CHECK("ft_lstnew(NULL) : nœud avec content NULL", n && !n->content && !n->next);
	free(n);
	CASE("ft_lstnew(&x) avec malloc qui échoue");
	FAIL_MALLOC(1);
	n = ft_lstnew(&x);
	FAIL_MALLOC(0);
	CHECK("ft_lstnew(&x) : doit renvoyer NULL si malloc échoue", n == NULL);
	free(n);
}
EOF
	;;

ft_lstadd_front) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*lst = NULL;
	t_list	*a = tst_node("a");
	t_list	*b = tst_node("b");

	CASE("ft_lstadd_front(&lst, a) avec lst vide");
	ft_lstadd_front(&lst, a);
	CHECK("ft_lstadd_front(&lst, a) avec lst vide : lst doit valoir a", lst == a);
	CHECK("ft_lstadd_front(&lst, a) avec lst vide : a->next doit valoir NULL", a->next == NULL);
	CASE("ft_lstadd_front(&lst, b) avec lst = a");
	ft_lstadd_front(&lst, b);
	CHECK("ft_lstadd_front(&lst, b) : lst doit valoir b", lst == b);
	CHECK("ft_lstadd_front(&lst, b) : b->next doit valoir a", b->next == a);
	free(a);
	free(b);
}
EOF
	;;

ft_lstsize) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*a = tst_node("a");
	t_list	*b = tst_node("b");
	t_list	*c = tst_node("c");

	CHECK_INT("ft_lstsize(NULL)", ft_lstsize(NULL), 0);
	CHECK_INT("ft_lstsize(a)", ft_lstsize(a), 1);
	a->next = b;
	b->next = c;
	CHECK_INT("ft_lstsize(a -> b -> c)", ft_lstsize(a), 3);
	free(a);
	free(b);
	free(c);
}
EOF
	;;

ft_lstlast) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*a = tst_node("a");
	t_list	*b = tst_node("b");
	t_list	*c = tst_node("c");

	CHECK("ft_lstlast(NULL) : doit renvoyer NULL", ft_lstlast(NULL) == NULL);
	CHECK("ft_lstlast(a) : doit renvoyer a", ft_lstlast(a) == a);
	a->next = b;
	b->next = c;
	CHECK("ft_lstlast(a -> b -> c) : doit renvoyer c", ft_lstlast(a) == c);
	free(a);
	free(b);
	free(c);
}
EOF
	;;

ft_lstadd_back) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*lst = NULL;
	t_list	*a = tst_node("a");
	t_list	*b = tst_node("b");
	t_list	*c = tst_node("c");

	CASE("ft_lstadd_back(&lst, a) avec lst vide");
	ft_lstadd_back(&lst, a);
	CHECK("ft_lstadd_back(&lst, a) avec lst vide : lst doit valoir a", lst == a);
	CASE("ft_lstadd_back(&lst, b) avec lst = a");
	ft_lstadd_back(&lst, b);
	CHECK("ft_lstadd_back(&lst, b) : lst doit toujours valoir a", lst == a);
	CHECK("ft_lstadd_back(&lst, b) : a->next doit valoir b", a->next == b);
	CASE("ft_lstadd_back(&lst, c) avec lst = a -> b");
	ft_lstadd_back(&lst, c);
	CHECK("ft_lstadd_back(&lst, c) : b->next doit valoir c", b->next == c);
	CHECK("ft_lstadd_back(&lst, c) : c->next doit valoir NULL", c->next == NULL);
	free(a);
	free(b);
	free(c);
}
EOF
	;;

ft_lstdelone) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*a = tst_node(strdup("a"));
	t_list	*b = tst_node(strdup("b"));

	a->next = b;
	CASE("ft_lstdelone(a, del) avec a -> b");
	ft_lstdelone(a, tst_del);
	CHECK_INT("ft_lstdelone(a, del) : nombre d'appels à del", g_del, 1);
	CASE("accès à b après ft_lstdelone(a, del)");
	CHECK("ft_lstdelone(a, del) : b ne doit pas être touché", !strcmp(b->content, "b"));
	free(b->content);
	free(b);
}
EOF
	;;

ft_lstclear) list_helpers; cat <<'EOF'
static void	tst_run(void)
{
	t_list	*lst = tst_node(strdup("a"));
	t_list	*empty = NULL;

	lst->next = tst_node(strdup("b"));
	lst->next->next = tst_node(strdup("c"));
	CASE("ft_lstclear(&lst, del) avec lst = a -> b -> c");
	ft_lstclear(&lst, tst_del);
	CHECK("ft_lstclear(&lst, del) : lst doit valoir NULL", lst == NULL);
	CHECK_INT("ft_lstclear(&lst, del) : nombre d'appels à del", g_del, 3);
	CASE("ft_lstclear(&lst, del) avec lst vide");
	ft_lstclear(&empty, tst_del);
	CHECK("ft_lstclear(&lst, del) avec lst vide : ne doit rien faire", empty == NULL && g_del == 3);
}
EOF
	;;

ft_lstiter) list_helpers; cat <<'EOF'
static void	tst_inc(void *p)
{
	(*(int *)p)++;
}

static void	tst_run(void)
{
	int		v[3] = {1, 2, 3};
	t_list	*a = tst_node(&v[0]);
	t_list	*b = tst_node(&v[1]);
	t_list	*c = tst_node(&v[2]);

	a->next = b;
	b->next = c;
	CASE("ft_lstiter(a -> b -> c, f) avec f = +1");
	ft_lstiter(a, tst_inc);
	CHECK("ft_lstiter(1 -> 2 -> 3, f) avec f = +1 : doit donner 2 -> 3 -> 4",
		v[0] == 2 && v[1] == 3 && v[2] == 4);
	CASE("ft_lstiter(NULL, f)");
	ft_lstiter(NULL, tst_inc);
	CHECK("ft_lstiter(NULL, f) : ne doit rien faire", 1);
	free(a);
	free(b);
	free(c);
}
EOF
	;;

ft_lstmap) list_helpers; cat <<'EOF'
static void	*tst_dbl(void *p)
{
	int	*r = __real_malloc(sizeof(int));

	*r = *(int *)p * 2;
	return (r);
}

static void	tst_free_map(t_list *l)
{
	t_list	*nx;

	while (l)
	{
		nx = l->next;
		free(l->content);
		free(l);
		l = nx;
	}
}

static void	tst_run(void)
{
	int		v[3] = {1, 2, 3};
	t_list	*a = tst_node(&v[0]);
	t_list	*r;
	char	d[96];

	a->next = tst_node(&v[1]);
	a->next->next = tst_node(&v[2]);
	CASE("ft_lstmap(1 -> 2 -> 3, f, del) avec f = x2");
	r = ft_lstmap(a, tst_dbl, free);
	CHECK("ft_lstmap(1 -> 2 -> 3, f, del) avec f = x2 : doit donner 2 -> 4 -> 6",
		r && r->next && r->next->next && !r->next->next->next
		&& *(int *)r->content == 2 && *(int *)r->next->content == 4
		&& *(int *)r->next->next->content == 6);
	CHECK("ft_lstmap : la liste d'origine ne doit pas changer",
		v[0] == 1 && v[1] == 2 && v[2] == 3 && a->content == &v[0]);
	CHECK("ft_lstmap : doit créer de nouveaux nœuds", r != a);
	if (r != a)
		tst_free_map(r);
	CHECK("ft_lstmap(NULL, f, del) : doit renvoyer NULL", ft_lstmap(NULL, tst_dbl, free) == NULL);
	for (int n = 1; n <= 3; n++)
	{
		snprintf(d, sizeof d, "ft_lstmap(1 -> 2 -> 3, f, del) avec le malloc n°%d qui échoue", n);
		CASE(d);
		FAIL_MALLOC(n);
		r = ft_lstmap(a, tst_dbl, free);
		if (MALLOC_TRIGGERED())
			CHECK(d, r == NULL);
		FAIL_MALLOC(0);
		if (r != a)
			tst_free_map(r);
	}
	free(a->next->next);
	free(a->next);
	free(a);
}
EOF
	;;
esac
}

# --------------------------- Lecture du rapport ASan ------------------------ #
# Affiche "fichier.c:ligne" de la première frame dans le code de l'élève
user_frame() {
	grep -E "^[[:space:]]+#[0-9]+ .* in [^ ]+ $DIR/" | head -1 \
		| sed -E "s|.* in ([^ ]+) $DIR/([^ ]+).*|\2 (\1)|"
}

# Ligne du test qui a fait l'appel fautif
test_frame_line() {
	local src=$1 n
	n=$(grep -E "in tst_run .*$(basename "$src"):[0-9]+" | head -1 | sed -E 's/.*:([0-9]+).*/\1/')
	[ -n "$n" ] && sed -n "${n}p" "$src" | sed -E 's/^[[:space:]]+//' | cut -c1-110
}

asan_report() {
	local err=$1 src=$2 type loc call
	if grep -q "ERROR: AddressSanitizer" "$err"; then
		type=$(grep -m1 -oE "ERROR: AddressSanitizer: [a-zA-Z_-]+" "$err" | awk '{print $3}')
		loc=$(sed -n '/ERROR: AddressSanitizer/,/^$/p' "$err" | user_frame)
		if [ -n "$loc" ]; then
			msg "erreur mémoire ($type) dans $loc"
		else
			loc=$(sed -n '/allocated by thread/,/^$/p' "$err" | user_frame)
			msg "erreur mémoire ($type) en lisant le résultat de ta fonction${loc:+ (zone allouée dans $loc)}"
		fi
	fi
	if grep -q "ERROR: LeakSanitizer" "$err"; then
		msg "fuite mémoire : $(grep -m1 -oE '[0-9]+ byte\(s\) leaked in [0-9]+ allocation\(s\)' "$err")"
		# un bloc par fuite : où a été fait le malloc, et quel appel du test
		awk '/leak of/{n++} {print > (FILENAME "." n)}' "$err"
		for blk in "$err".[1-9]*; do
			[ -f "$blk" ] || continue
			loc=$(user_frame < "$blk")
			call=$(test_frame_line "$src" < "$blk")
			printf "        ${D}malloc dans %s%s${N}\n" "${loc:-?}" "${call:+ ← appel : $call}"
		done | sort -u | head -4
	fi
}

# ------------------------------ Test d'une fonction ------------------------- #
run_test() {
	local fn=$1 src="$TMP/t_$fn.c" bin="$TMP/t_$fn" out rc res ok ko msgs=()

	if [ ! -f "$DIR/$fn.c" ]; then
		line_skip "$fn" "non réalisé"
		return
	fi
	[ -n "${STRICT[$fn]}" ] && msgs+=("ne compile pas avec -Wall -Wextra -Werror : ${STRICT[$fn]}")
	grep -Eq "\b$fn[[:space:]]*\(" "$DIR/libft.h" || msgs+=("prototype absent de libft.h")
	[ -n "${STYLE[$fn]}" ] && msgs+=("${STYLE[$fn]}")

	if [ -n "${BROKEN[$fn]}" ]; then
		line_ko "$fn"
		for m in "${msgs[@]}"; do msg "$m"; done
		[ -z "${STRICT[$fn]}" ] && msg "ne compile pas : ${BROKEN[$fn]}"
		return
	fi

	{ prelude; echo "${PROTO[$fn]}"; body "$fn"; } > "$src"
	build() { cc $SAN -g -w -I"$DIR" "$src" -o "$bin" -L"$TMP" -ltest -Wl,--wrap=malloc 2> "$TMP/cerr"; }
	if ! build && grep -q "conflicting types" "$TMP/cerr"; then
		# prototype différent du sujet : on le signale, puis on teste quand même
		msgs+=("prototype dans libft.h différent du sujet. Attendu : ${PROTO[$fn]}")
		{ prelude; body "$fn"; } > "$src"
	fi
	if [ ! -x "$bin" ] && ! build; then
		line_ko "$fn"
		for m in "${msgs[@]}"; do msg "$m"; done
		if grep -q "undefined reference to .$fn'" "$TMP/cerr"; then
			msg "$fn n'est pas défini (mauvais nom de fonction ?)"
		else
			msg "le test ne compile pas : $(first_error "$TMP/cerr")"
		fi
		return
	fi

	out=$(cd "$TMP" && ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=1" \
		timeout 5 "$bin" 2> "$TMP/rerr")
	rc=$?
	res=$(grep -m1 "^@@RESULT" <<< "$out")
	ok=$(awk '{print $2}' <<< "$res"); ko=$(awk '{print $3}' <<< "$res")
	if [ -n "$res" ] && [ "$ko" = 0 ] && [ ${#msgs[@]} -eq 0 ] \
		&& ! grep -q "Sanitizer" "$TMP/rerr"; then
		line_ok "$fn" "($ok tests)"
		return
	fi
	line_ko "$fn"
	for m in "${msgs[@]}"; do msg "$m"; done
	grep "^@@MSG " <<< "$out" | sed 's/^@@MSG //' | while IFS= read -r m; do msg "$m"; done
	if [ $rc -eq 124 ]; then
		msg "boucle infinie (timeout 5 s) pendant : $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	elif [ -z "$res" ]; then
		msg "crash pendant : $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	fi
	asan_report "$TMP/rerr" "$src"
}

# ================================== Début =================================== #
printf "${B}Testeur libft${N} ${D}($DIR)${N}\n"

# AddressSanitizer disponible ?
SAN="-fsanitize=address"
echo 'int main(void){return 0;}' > "$TMP/asan.c"
if ! cc $SAN "$TMP/asan.c" -o "$TMP/asan" 2>/dev/null || ! "$TMP/asan" 2>/dev/null; then
	SAN=""
	printf "${Y}AddressSanitizer indisponible : pas de détection des fuites / débordements.${N}\n"
fi

# ------------------------------- Compilation -------------------------------- #
declare -A STRICT=() BROKEN=() STYLE=()
ALLOWED_EXT="malloc free write"
for f in "$DIR"/*.c; do
	[ -f "$f" ] || continue
	fn=$(basename "$f" .c)
	if ! cc -Wall -Wextra -Werror -c "$f" -I"$DIR" -o "$TMP/strict/$fn.o" 2> "$TMP/err"; then
		STRICT[$fn]=$(first_error "$TMP/err")
	else
		# fonctions externes interdites / variables globales
		bad=$(nm -u "$TMP/strict/$fn.o" | awk '{print $2}' \
			| grep -vE '^(ft_|_GLOBAL_OFFSET_TABLE_|__stack_chk_fail)' \
			| grep -vxF -f <(tr ' ' '\n' <<< "$ALLOWED_EXT") | tr '\n' ' ')
		[ -n "$bad" ] && STYLE[$fn]="fonction(s) externe(s) interdite(s) : $bad"
		glob=$(nm "$TMP/strict/$fn.o" | awk '$2 ~ /^[BCDGRSbdgs]$/ {print $3}' | tr '\n' ' ')
		[ -n "$glob" ] && STYLE[$fn]="${STYLE[$fn]:+${STYLE[$fn]} ; }variable(s) globale(s) : $glob"
	fi
	# fonctions auxiliaires non static
	helpers=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_[:space:]*]*[[:space:]*][a-zA-Z_][a-zA-Z0-9_]*\(' "$f" \
		| grep -vE '^static|;[[:space:]]*$' \
		| sed -E 's/^[^(]*[[:space:]*]([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/' \
		| grep -vx "$fn" | grep -vx main | tr '\n' ' ')
	[ -n "$helpers" ] && STYLE[$fn]="${STYLE[$fn]:+${STYLE[$fn]} ; }fonction(s) auxiliaire(s) non static : $helpers"
	if ! cc $SAN -g -w -c "$f" -I"$DIR" -o "$TMP/obj/$fn.o" 2> "$TMP/err"; then
		BROKEN[$fn]=$(first_error "$TMP/err")
		rm -f "$TMP/obj/$fn.o"
	fi
done
ar rcs "$TMP/libtest.a" "$TMP"/obj/*.o 2>/dev/null

# --------------------------------- Makefile --------------------------------- #
if [ ${#WANTED[@]} -eq 0 ]; then
	section "Makefile"
	cp "$DIR"/*.c "$DIR"/*.h "$DIR"/Makefile "$TMP/mk/" 2>/dev/null
	if [ ! -f "$TMP/mk/Makefile" ]; then
		line_ko "Makefile"; msg "fichier Makefile absent"
	else
		mk() { make -C "$TMP/mk" "$@" 2>&1; }
		out=$(mk)
		if [ $? -eq 0 ] && [ -f "$TMP/mk/libft.a" ]; then
			line_ok "make"
			missing=""
			for f in "$DIR"/ft_*.c; do
				fn=$(basename "$f" .c)
				ar t "$TMP/mk/libft.a" | grep -qx "$fn.o" || missing+="$fn.o "
			done
			if [ -z "$missing" ]; then line_ok "contenu libft.a"
			else line_ko "contenu libft.a"; msg "absents de libft.a : $missing"; fi
			out=$(mk)
			if grep -qE '(^|[[:space:]/])(cc|gcc|clang|ar)[[:space:]]' <<< "$out"; then
				line_ko "relink"; msg "un 2e 'make' recompile alors que rien n'a changé"
			else line_ok "relink"; fi
			mk clean > /dev/null
			if ls "$TMP/mk"/*.o > /dev/null 2>&1 || [ ! -f "$TMP/mk/libft.a" ]; then
				line_ko "make clean"; msg "doit supprimer les .o et garder libft.a"
			else line_ok "make clean"; fi
			mk fclean > /dev/null
			if [ -f "$TMP/mk/libft.a" ]; then line_ko "make fclean"; msg "libft.a n'est pas supprimé"
			else line_ok "make fclean"; fi
			if mk re > /dev/null && [ -f "$TMP/mk/libft.a" ]; then line_ok "make re"
			else line_ko "make re"; fi
		else
			line_ko "make"
			grep -E 'error:|undefined reference|No rule|^make.*\*\*\*' <<< "$out" | head -3 \
				| sed -E 's|^/[^ ]*/||' | cut -c1-150 | while IFS= read -r m; do msg "$m"; done
		fi
		flags=""
		for fl in -Wall -Wextra -Werror; do grep -q -- "$fl" "$DIR/Makefile" || flags+="$fl "; done
		if [ -z "$flags" ]; then line_ok "flags"; else line_ko "flags"; msg "flags manquants : $flags"; fi
	fi

	section "Rendu"
	if [ -f "$DIR/README.md" ]; then
		if head -1 "$DIR/README.md" | grep -qE '^[*_]This project has been created as part of the 42 curriculum by .+[*_][[:space:]]*$'; then
			line_ok "README.md"
		else
			line_ko "README.md"; msg "1re ligne attendue en italique : *This project has been created as part of the 42 curriculum by <login>.*"
		fi
	else
		line_ko "README.md"; msg "README.md absent (obligatoire)"
	fi
	extra=""
	for f in "$DIR"/*.c; do
		fn=$(basename "$f" .c)
		[ -n "${PROTO[$fn]}" ] || extra+="$fn.c "
	done
	if [ -z "$extra" ]; then line_ok "fichiers"
	else
		line_ko "fichiers"; msg "fichiers hors sujet (« Submitting unused files is not allowed ») : $extra"
	fi
	if command -v norminette > /dev/null 2>&1; then
		nerr=$(cd "$DIR" && norminette *.c *.h 2>&1 | grep -E ': Error!' | sed -E 's/: Error!//' | tr '\n' ' ')
		if [ -z "$nerr" ]; then line_ok "norminette"
		else line_ko "norminette"; msg "erreurs dans : $nerr"; fi
	else
		line_skip "norminette" "non installée"
	fi
fi

# --------------------------------- Fonctions -------------------------------- #
for part in 1 2 3; do
	case $part in
		1) LIST=("${PART1[@]}") ;;
		2) LIST=("${PART2[@]}") ;;
		3) LIST=("${PART3[@]}") ;;
	esac
	printed=0
	for fn in "${LIST[@]}"; do
		wanted "$fn" || continue
		[ $printed -eq 0 ] && section "Partie $part" && printed=1
		run_test "$fn"
	done
done

printf "\n${B}Résultat :${N} ${G}%d OK${N}, ${R}%d KO${N}, ${D}%d non réalisé(s)${N}\n" \
	"$N_OK" "$N_KO" "$N_SKIP"
[ "$N_KO" -eq 0 ]
