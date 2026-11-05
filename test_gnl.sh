#!/usr/bin/env bash
# **************************************************************************** #
#  test_gnl.sh - single-file get_next_line tester                              #
#                                                                              #
#  Usage (from your get_next_line folder):                                     #
#      bash ../test_gnl.sh              -> test everything                     #
#      bash ../test_gnl.sh 1 42         -> only these BUFFER_SIZEs             #
#                                                                              #
#  - On Windows (Git Bash), the script relaunches itself in WSL.               #
#  - Your files are compiled with several BUFFER_SIZEs (from 1 to 10000000),   #
#    each size in a separate program: a crash does not block the others.       #
#  - Files, stdin, pipes, invalid fds, read() and malloc() errors, short      #
#    reads, BUFFER_SIZE <= 0 and fd 1023 are tested; the bonus is tested with  #
#    up to 200 fds read in turn and a read() error on a single fd.             #
#  - Every read() call must ask for exactly BUFFER_SIZE bytes.                 #
#  - A Makefile in the folder is a KO (the subject says "Makefile: No").       #
#  - AddressSanitizer detects crashes, memory overflows and leaks.             #
#  - Do NOT put this file in your repository.                                  #
# **************************************************************************** #

# ----------- Relaunch in WSL if there is no compiler (Git Bash on Windows) -- #
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
banner "get_next_line tester" "$DIR"
if [ ! -f "$DIR/get_next_line.c" ] && [ ! -f "$DIR/get_next_line.h" ]; then
	echo "Error: get_next_line.c not found. Run this script from your get_next_line folder." >&2
	exit 1
fi

TMP=$(mktemp -d /tmp/test_gnl.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/strict" "$TMP/run"

N_OK=0; N_KO=0; N_SKIP=0; N_WARN=0

lbl() { printf "%s%*s" "$1" $(( ${#1} < 30 ? 30 - ${#1} : 0 )) ""; }
section() { printf "\n${B}== %s ==${N}\n" "$1"; }
line_ok() { printf "  %s ${G}OK${N}%s\n" "$(lbl "$1")" "${2:+ ${D}$2${N}}"; N_OK=$((N_OK + 1)); }
line_ko() { printf "  %s ${R}KO${N}\n" "$(lbl "$1")"; N_KO=$((N_KO + 1)); }
line_warn() { printf "  %s ${Y}!!${N} %s\n" "$(lbl "$1")" "$2"; N_WARN=$((N_WARN + 1)); }
line_skip() { printf "  %s ${D}-- %s${N}\n" "$(lbl "$1")" "$2"; N_SKIP=$((N_SKIP + 1)); }
msg() { printf "      ${R}✗${N} %s\n" "$1"; }
note() { printf "      ${D}%s${N}\n" "$1"; }
# "erreur" also matches gcc messages in a French locale
first_error() { grep -m1 -E "error|erreur|undefined" "$1" | sed -E 's|^.*/||; s/^[[:space:]]+//' | cut -c1-150; }

# BUFFER_SIZEs to test (or the ones given as arguments)
SIZES=(1 2 3 5 10 42 100 1000 9999 10000000)
if [ $# -gt 0 ]; then
	for a in "$@"; do
		if ! [[ $a =~ ^[1-9][0-9]*$ ]]; then
			echo "Invalid argument: '$a' (expected: BUFFER_SIZEs, e.g. 1 42 9999)" >&2
			exit 1
		fi
	done
	SIZES=("$@")
fi

MAND_C=(get_next_line.c get_next_line_utils.c)
BONUS_C=(get_next_line_bonus.c get_next_line_utils_bonus.c)
ALLOWED_FILES="get_next_line.c get_next_line_utils.c get_next_line.h get_next_line_bonus.c get_next_line_utils_bonus.c get_next_line_bonus.h"

# ----------------------------- Test program (C) ----------------------------- #
harness() { cat <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/resource.h>
#ifdef __SANITIZE_ADDRESS__
# include <sanitizer/asan_interface.h>
# include <sanitizer/lsan_interface.h>
#endif

char	*get_next_line(int fd);

static int			g_ok = 0;
static int			g_ko = 0;
static const char	*g_case = "start of the test";
static int			g_malloc_fail = 0;
static int			g_malloc_count = 0;
static long			g_live = 0;
static int			g_read_fail = 0;
static int			g_read_fail_fd = -1;
static int			g_read_short = 0;
static unsigned		g_read_seed = 1;
static long			g_read_bytes = 0;
static int			g_leak_seen = 0;
static int			g_warn = 0;
static int			g_greedy = 0;
static volatile int	g_in_read = 0;
static int			g_read_eagain = 0;
static int			g_read_badsize = 0;

/* rigged malloc: the g_malloc_fail-th call returns NULL; g_live counts the
   blocks not freed yet */
void	*__real_malloc(size_t size);
void	*__wrap_malloc(size_t size)
{
	void	*p;

	g_malloc_count++;
	if (g_malloc_fail > 0 && --g_malloc_fail == 0)
		return (NULL);
	p = __real_malloc(size);
	if (p)
		g_live++;
	return (p);
}
#define FAIL_MALLOC(n) (g_malloc_fail = (n))
#define MALLOC_TRIGGERED() (g_malloc_fail == 0)

void	__real_free(void *p);
void	__wrap_free(void *p)
{
	if (p)
		g_live--;
	__real_free(p);
}

static void	tst_fail(const char *fmt, ...);

/* rigged read: returns -1 while g_read_fail is 1 (on every fd, or only on
   g_read_fail_fd); with g_read_short, returns fewer bytes than asked.
   Every call must ask for exactly BUFFER_SIZE bytes (reported once). */
ssize_t	__real_read(int fd, void *buf, size_t n);
ssize_t	__wrap_read(int fd, void *buf, size_t n)
{
	ssize_t	r;

	if (n != (size_t)(BUFFER_SIZE) && !g_read_badsize)
	{
		g_read_badsize = 1;
		tst_fail("read() called with a size of %zu instead of BUFFER_SIZE (%ld) during: %s"
			" -> always read exactly BUFFER_SIZE bytes", n, (long)(BUFFER_SIZE),
			g_case ? g_case : "end of the test");
	}
	if (g_read_fail && (g_read_fail_fd < 0 || fd == g_read_fail_fd))
	{
		errno = EIO;
		return (-1);
	}
	if (g_read_short && n > 1)
	{
		g_read_seed = g_read_seed * 1103515245u + 12345u;
		n = 1 + (g_read_seed >> 8) % (g_read_seed & 1 ? (n < 5 ? n : 5) : n);
	}
	g_in_read = 1;
	r = __real_read(fd, buf, n);
	g_in_read = 0;
	if (r < 0 && errno == EAGAIN)
		g_read_eagain++;
	if (r > 0)
		g_read_bytes += r;
	return (r);
}

#define CASE(d) (g_case = (d))

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

	if (++g_warn > 3)
		return ;
	printf("@@WARN ");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("\n");
}

/* readable display of a line (truncated if too long) */
static const char	*tst_qn(const char *s, size_t n)
{
	static char	bufs[4][256];
	static int	k = 0;
	char		*b;
	int			j = 0;

	if (!s)
		return ("NULL");
	b = bufs[k++ % 4];
	b[j++] = '"';
	for (size_t i = 0; i < n; i++)
	{
		unsigned char c = s[i];
		if (j > 100)
		{
			snprintf(b + j, 256 - j, "…\" (%zu chars)", n);
			return (b);
		}
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
#define Q(s) ((s) ? tst_qn((s), strlen(s)) : "NULL")

/* reports the first memory leak and the scenario it happened in */
static void	tst_leaks(const char *scenario)
{
#ifdef __SANITIZE_ADDRESS__
	if (!g_leak_seen && __lsan_do_recoverable_leak_check())
	{
		g_leak_seen = 1;
		printf("@@LEAK %s\n", scenario);
	}
#else
	(void)scenario;
#endif
}

static int	tst_open(const char *name, const char *content, size_t len)
{
	int	fd = open(name, O_WRONLY | O_CREAT | O_TRUNC, 0644);

	if (fd < 0 || write(fd, content, len) != (ssize_t)len)
	{
		perror(name);
		exit(1);
	}
	close(fd);
	fd = open(name, O_RDONLY);
	if (fd < 0)
	{
		perror(name);
		exit(1);
	}
	return (fd);
}

static void	tst_drain(int fd)
{
	char	*s;
	int		n = 0;

	while (n++ < 100000 && (s = get_next_line(fd)))
		free(s);
}

/* reads fd to the end with get_next_line and compares with the lines of content */
static int	tst_lines(int fd, const char *name, const char *content, size_t len)
{
	static char	d[300];
	size_t		pos = 0;
	size_t		e;
	int			n = 0;
	long		live = g_live;
	char		*got;

	while (pos < len)
	{
		e = pos;
		while (e < len && content[e] != '\n')
			e++;
		if (e < len)
			e++;
		snprintf(d, sizeof d, "%s: line %d", name, ++n);
		CASE(d);
		got = get_next_line(fd);
		if (!got || strlen(got) != e - pos || memcmp(got, content + pos, e - pos))
		{
			tst_fail("%s → %s, expected %s", d, Q(got), tst_qn(content + pos, e - pos));
			free(got);
			tst_drain(fd);
			return (0);
		}
		free(got);
		pos = e;
	}
	for (int k = 1; k <= 2; k++)
	{
		snprintf(d, sizeof d, "%s: %s call%s", name, k == 1 ? "1st" : "2nd",
			len ? " after the last line" : "");
		CASE(d);
		got = get_next_line(fd);
		if (got)
		{
			tst_fail("%s → %s, expected NULL", d, Q(got));
			free(got);
			tst_drain(fd);
			return (0);
		}
	}
	g_ok++;
	if (g_live > live && !g_read_short)
	{
		static int	warned = 0;

		if (!warned++)
			tst_warn("%s: once get_next_line has returned NULL, %ld block(s) it allocated are "
				"still not freed (valgrind: \"still reachable\"); free everything at the end of the file",
				name, g_live - live);
	}
	return (1);
}

static void	tst_file(const char *name, const char *content, size_t len)
{
	int	fd = tst_open("tst_file.txt", content, len);

	tst_lines(fd, name, content, len);
	close(fd);
	tst_leaks(name);
}
#define FILE_STR(name, s) tst_file(name, s, sizeof(s) - 1)

static void	tst_stdin(const char *name, const char *content, size_t len)
{
	int	fd = tst_open("tst_stdin.txt", content, len);
	int	saved = dup(0);

	dup2(fd, 0);
	close(fd);
	tst_lines(0, name, content, len);
	dup2(saved, 0);
	close(saved);
	tst_leaks(name);
}

/* pipe filled by a child process */
static void	tst_pipe(const char *name, const char *content, size_t len)
{
	int		p[2];
	pid_t	pid;

	if (pipe(p) != 0)
	{
		perror("pipe");
		exit(1);
	}
	pid = fork();
	if (pid == 0)
	{
		size_t	off = 0;
		ssize_t	w;

		close(p[0]);
		while (off < len && (w = write(p[1], content + off, len - off)) > 0)
			off += w;
		_exit(0);
	}
	close(p[1]);
	tst_lines(p[0], name, content, len);
	close(p[0]);
	waitpid(pid, NULL, 0);
	tst_leaks(name);
}

static void	tst_expect(int fd, const char *desc, const char *exp)
{
	char	*got;

	CASE(desc);
	got = get_next_line(fd);
	if ((!got && !exp) || (got && exp && !strcmp(got, exp)))
		g_ok++;
	else
		tst_fail("%s → %s, expected %s", desc, Q(got), Q(exp));
	free(got);
}

/* pipe whose writer has not finished yet: get_next_line must return each
   line as soon as it finds it, without waiting for the end of the file */
static void	tst_pipe_open(void)
{
	int	p[2];

	if (pipe(p) != 0)
	{
		perror("pipe");
		exit(1);
	}
	fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) | O_NONBLOCK);
	g_read_eagain = 0;
	alarm(5);
	if (write(p[1], "abc\n", 4) != 4)
		perror("write");
	tst_expect(p[0], "pipe still open containing \"abc\\n\": must return the line without waiting for more", "abc\n");
	if (write(p[1], "def\nghi\n", 8) != 8)
		perror("write");
	tst_expect(p[0], "pipe still open containing \"def\\nghi\\n\": 1st line", "def\n");
	tst_expect(p[0], "pipe still open, \"ghi\\n\" already read: must return the line without calling read again", "ghi\n");
	if (write(p[1], "jkl", 3) != 3)
		perror("write");
	close(p[1]);
	tst_expect(p[0], "pipe closed after \"jkl\"", "jkl");
	tst_expect(p[0], "pipe closed: end", NULL);
	alarm(0);
	if (g_read_eagain)
		tst_fail("pipe still open: get_next_line called read() again although the line was already "
			"complete (or read the whole input at once): on a terminal or an open pipe it would wait forever");
	close(p[0]);
	tst_leaks("pipe still open");
}

static void	tst_bad_fd(void)
{
	int	fd;

	tst_expect(-1, "get_next_line(-1)", NULL);
	tst_expect(4242, "get_next_line(4242) (fd not open)", NULL);
	tst_expect(100000, "get_next_line(100000) (fd not open)", NULL);
	tst_expect(1024, "get_next_line(1024) (fd not open)", NULL);
	fd = tst_open("tst_file.txt", "abc\n", 4);
	close(fd);
	tst_expect(fd, "get_next_line(fd) on a closed fd", NULL);
	fd = open(".", O_RDONLY);
	tst_expect(fd, "get_next_line(fd) on a directory (read fails)", NULL);
	close(fd);
	tst_leaks("invalid fds");
}

static void	tst_read_error(void)
{
	const char	*c = "aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\ndddddddddd";
	const char	*l[] = {"aaaaaaaaaa\n", "bbbbbbbbbb\n", "cccccccccc\n", "dddddddddd\n"};
	int			fd = tst_open("tst_file.txt", c, strlen(c));
	int			k = 1;
	int			bad = 0;
	char		*got;

	tst_expect(fd, "read error: 1st line (read still works)", l[0]);
	g_read_fail = 1;
	CASE("read() returns -1: get_next_line must return NULL");
	while (!bad && k <= 4 && (got = get_next_line(fd)))
	{
		/* complete lines that were already read may still be returned */
		if (k >= 4 || strcmp(got, l[k]))
		{
			tst_fail("read() returns -1 → get_next_line returns %s instead of NULL", Q(got));
			bad = 1;
		}
		k++;
		free(got);
	}
	if (!bad)
		g_ok++;
	g_read_fail = 0;
	if (bad)
		tst_drain(fd);
	close(fd);
	fd = tst_open("tst_file.txt", c, strlen(c));
	tst_lines(fd, "after a read error, reading the file again from the start", c, strlen(c));
	close(fd);
	tst_leaks("read error");
}

static char	*tst_fill(char ch, size_t n, const char *end, size_t *len);
static char	*tst_gen(size_t nlines, size_t maxlen, unsigned seed, size_t *len);
static char	*tst_around(size_t *len);

/* every malloc of the call fails in turn (1st, 2nd, ... allocation) */
static void	tst_malloc_fail(void)
{
	const char	*c = "line 1\nline 02\nlast line";
	const char	*l[] = {"line 1\n", "line 02\n", "last line", NULL};
	const char	*what[] = {"the 1st line", "the 2nd line", "the last line (no \\n)",
		"the call after the last line"};
	char		d[200];
	char		*got;
	int			fd;
	int			cnt;

	for (int step = 0; step < 4; step++)
	{
		fd = tst_open("tst_file.txt", c, strlen(c));
		for (int j = 0; j < step; j++)
			free(get_next_line(fd));
		g_malloc_count = 0;
		free(get_next_line(fd));
		cnt = g_malloc_count;
		tst_drain(fd);
		close(fd);
		for (int n = 1; n <= cnt && n <= 60; n++)
		{
			fd = tst_open("tst_file.txt", c, strlen(c));
			for (int j = 0; j < step; j++)
				free(get_next_line(fd));
			snprintf(d, sizeof d, "malloc #%d (of %d) fails while reading %s", n, cnt, what[step]);
			CASE(d);
			FAIL_MALLOC(n);
			got = get_next_line(fd);
			if (MALLOC_TRIGGERED())
			{
				FAIL_MALLOC(0);
				/* expected: NULL (a correct line is tolerated) */
				if (got && (!l[step] || strcmp(got, l[step])))
					tst_fail("%s → %s, expected NULL", d, Q(got));
				else
					g_ok++;
			}
			FAIL_MALLOC(0);
			free(got);
			snprintf(d, sizeof d, "next calls after malloc #%d (of %d) failed while reading %s", n, cnt, what[step]);
			CASE(d);
			tst_drain(fd);
			close(fd);
			snprintf(d, sizeof d, "malloc #%d (of %d) failed while reading %s "
				"(free the stash before returning NULL)", n, cnt, what[step]);
			tst_leaks(d);
		}
	}
}

/* subject: "try to read as little as possible", "don't read the whole file
   and then return each line" */
static void	tst_read_little(void)
{
	size_t	len;
	char	*s = tst_fill('r', 6300, "", &len);
	char	*got;
	int		fd;

	for (size_t k = 20; k < len; k += 21)
		s[k] = '\n';
	fd = tst_open("tst_file.txt", s, len);
	g_read_bytes = 0;
	for (int k = 1; k <= 3; k++)
	{
		CASE("reads only what is needed");
		got = get_next_line(fd);
		free(got);
		if ((size_t)(21 * k + BUFFER_SIZE) < len && g_read_bytes > 21 * k + BUFFER_SIZE)
		{
			tst_fail("after %d line(s) of 20 chars, read() has already returned %ld bytes "
				"(at most %d expected): the subject says to stop reading as soon as a \\n is found",
				k, g_read_bytes, 21 * k + BUFFER_SIZE);
			g_greedy = 1;
			break ;
		}
		if (k == 3)
			g_ok++;
	}
	tst_drain(fd);
	close(fd);
	free(s);
	tst_leaks("reads only what is needed");
}

/* read() returns fewer bytes than asked (allowed: pipes, terminals, ...) */
static void	tst_short_reads(void)
{
	size_t	len;
	char	*s;

	g_read_short = 1;
	s = tst_gen(300, 120, 7, &len);
	tst_file("short reads (read() returns fewer bytes than asked): big file", s, len);
	free(s);
	if (BUFFER_SIZE <= 100000)
	{
		s = tst_around(&len);
		tst_file("short reads: lines of BUFFER_SIZE-1, BUFFER_SIZE, BUFFER_SIZE+1 chars", s, len);
		free(s);
	}
	FILE_STR("short reads: 3 lines without a final \\n", "line 01\nline 02\nline 03");
	g_read_short = 0;
}

/* a file read through a high (but valid) fd */
static void	tst_high_fd(void)
{
	const char		*c = "first line\nsecond line\nlast";
	struct rlimit	rl;
	int				hi = 1023;
	int				fd;
	char			d[200];
	char			*got;

	if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < 1024)
		hi = (int)rl.rlim_cur - 1;
	fd = tst_open("tst_file.txt", c, strlen(c));
	if (dup2(fd, hi) < 0)
	{
		close(fd);
		return ;
	}
	close(fd);
	snprintf(d, sizeof d, "fd %d (valid: the fd limit is %d here): line 1", hi, hi + 1);
	CASE(d);
	got = get_next_line(hi);
	if (!got)
		tst_warn("%s → NULL: an fd up to %d can be opened, get_next_line should read it", d, hi);
	else if (strcmp(got, "first line\n"))
		tst_fail("%s → %s, expected \"first line\\n\"", d, Q(got));
	else
	{
		snprintf(d, sizeof d, "fd %d", hi);
		tst_lines(hi, d, c + 11, strlen(c + 11));
	}
	free(got);
	tst_drain(hi);
	close(hi);
	tst_leaks("high fd");
}

/* ----- content generators ----- */
static char	*tst_fill(char ch, size_t n, const char *end, size_t *len)
{
	char	*s = malloc(n + strlen(end) + 1);

	memset(s, ch, n);
	strcpy(s + n, end);
	*len = n + strlen(end);
	return (s);
}

/* lines of 0, 1, 2, ... n-1 chars */
static char	*tst_ramp(size_t n, size_t *len)
{
	char	*s = malloc(n * (n + 1) / 2 + n + 1);
	size_t	j = 0;

	for (size_t i = 0; i < n; i++)
	{
		for (size_t k = 0; k < i; k++)
			s[j++] = 'a' + (i + k) % 26;
		s[j++] = '\n';
	}
	s[j] = 0;
	*len = j;
	return (s);
}

/* random (but reproducible) lines of 0 to maxlen chars */
static char	*tst_gen(size_t nlines, size_t maxlen, unsigned seed, size_t *len)
{
	char		*s = malloc(nlines * (maxlen + 1) + 1);
	size_t		j = 0;
	unsigned	r = seed * 2654435761u + 1;

	for (size_t i = 0; i < nlines; i++)
	{
		r = r * 1103515245u + 12345u;
		size_t l = (r >> 8) % (maxlen + 1);
		for (size_t k = 0; k < l; k++)
		{
			r = r * 1103515245u + 12345u;
			s[j++] = 32 + (r >> 8) % 95;
		}
		s[j++] = '\n';
	}
	s[j] = 0;
	*len = j;
	return (s);
}

/* lines of BUFFER_SIZE - 1, BUFFER_SIZE, BUFFER_SIZE + 1 chars */
static char	*tst_around(size_t *len)
{
	size_t	n = BUFFER_SIZE;
	size_t	sz[] = {n - 1, n, n + 1, n > 1 ? n - 2 : 0, n};
	char	*s = malloc(5 * (n + 2) + 1);
	size_t	j = 0;

	for (int i = 0; i < 5; i++)
	{
		memset(s + j, 'a' + i, sz[i]);
		j += sz[i];
		if (i < 4)
			s[j++] = '\n';
	}
	s[j] = 0;
	*len = j;
	return (s);
}

#ifdef TST_BONUS
/* several fds read in turn; steps[i] = number of lines read in a row from fd i */
static void	tst_multi(const char *name, int nf, const char **c, const int *steps, int use_stdin)
{
	int		fd[4];
	size_t	pos[4];
	size_t	len[4];
	int		done[4];
	int		nline[4];
	char	d[300];
	char	fname[32];
	char	*got;
	int		left = nf;
	int		ok = 1;
	int		saved = -1;

	for (int i = 0; i < nf; i++)
	{
		len[i] = strlen(c[i]);
		snprintf(fname, sizeof fname, "tst_multi%d.txt", i);
		fd[i] = tst_open(fname, c[i], len[i]);
		pos[i] = 0;
		done[i] = 0;
		nline[i] = 0;
	}
	if (use_stdin)
	{
		saved = dup(0);
		dup2(fd[0], 0);
		close(fd[0]);
		fd[0] = 0;
	}
	while (left > 0 && ok)
		for (int i = 0; i < nf && ok; i++)
			for (int k = 0; k < steps[i] && !done[i] && ok; k++)
			{
				size_t e = pos[i];
				while (e < len[i] && c[i][e] != '\n')
					e++;
				if (e < len[i])
					e++;
				snprintf(d, sizeof d, "%s: fd %d (file %c), %s %d", name, fd[i], 'A' + i,
					pos[i] == len[i] ? "call after the last line" : "line", ++nline[i]);
				CASE(d);
				got = get_next_line(fd[i]);
				if (pos[i] == len[i])
				{
					if (got)
					{
						tst_fail("%s → %s, expected NULL", d, Q(got));
						ok = 0;
					}
					done[i] = 1;
					left--;
				}
				else if (!got || strlen(got) != e - pos[i] || memcmp(got, c[i] + pos[i], e - pos[i]))
				{
					tst_fail("%s → %s, expected %s", d, Q(got), tst_qn(c[i] + pos[i], e - pos[i]));
					ok = 0;
				}
				free(got);
				pos[i] = e;
			}
	for (int i = 0; i < nf; i++)
	{
		if (!ok)
			tst_drain(fd[i]);
		close(fd[i]);
	}
	if (use_stdin)
	{
		dup2(saved, 0);
		close(saved);
	}
	if (ok)
		g_ok++;
	tst_leaks(name);
}

/* many fds open at the same time, read in turn */
static void	tst_many_fds(void)
{
	struct rlimit	rl;
	int				nf = 200;
	int				fd[200];
	char			c[200][64];
	char			fname[64];
	char			d[200];
	char			*got;
	int				ok = 1;

	if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < 250)
		nf = (int)rl.rlim_cur - 50;
	for (int i = 0; i < nf; i++)
	{
		snprintf(c[i], sizeof c[i], "file %d: line 1\nfile %d: line 2\nfile %d: end", i, i, i);
		snprintf(fname, sizeof fname, "tst_many%d.txt", i);
		fd[i] = tst_open(fname, c[i], strlen(c[i]));
	}
	for (int l = 0; l < 4 && ok; l++)
		for (int i = 0; i < nf && ok; i++)
		{
			char	exp[64];

			if (l < 2)
				snprintf(exp, sizeof exp, "file %d: line %d\n", i, l + 1);
			else
				snprintf(exp, sizeof exp, "file %d: end", i);
			snprintf(d, sizeof d, "%d files open at the same time, read in turn: fd %d, %s",
				nf, fd[i], l < 3 ? (l < 2 ? (l ? "line 2" : "line 1") : "line 3") : "call after the last line");
			CASE(d);
			got = get_next_line(fd[i]);
			if (l < 3 ? !got || strcmp(got, exp) : got != NULL)
			{
				tst_fail("%s → %s, expected %s", d, Q(got), l < 3 ? Q(exp) : "NULL");
				ok = 0;
			}
			free(got);
		}
	for (int i = 0; i < nf; i++)
	{
		if (!ok)
			tst_drain(fd[i]);
		close(fd[i]);
	}
	if (ok)
		g_ok++;
	tst_leaks("many fds");
}

/* a read() error on one fd must not touch the other fds */
static void	tst_bonus_read_error(void)
{
	const char	*a = "a1\na2\na3\na4\na5";
	const char	*la[] = {"a1\n", "a2\n", "a3\n", "a4\n", "a5\n"};
	const char	*b = "b1-xyz\nb2\nb3\nb4\nb5";
	int			fa = tst_open("tst_multi0.txt", a, strlen(a));
	int			fb = tst_open("tst_multi1.txt", b, strlen(b));
	int			k = 1;
	int			bad = 0;
	char		*got;

	tst_expect(fa, "read error on fd A only: fd A, line 1", "a1\n");
	tst_expect(fb, "read error on fd A only: fd B, line 1", "b1-xyz\n");
	g_read_fail = 1;
	g_read_fail_fd = fa;
	CASE("read() returns -1 on fd A only: get_next_line(A) must return NULL");
	while (!bad && k <= 5 && (got = get_next_line(fa)))
	{
		/* complete lines that were already read may still be returned */
		if (k >= 5 || strcmp(got, la[k]))
		{
			tst_fail("read() returns -1 on fd A → get_next_line(A) returns %s instead of NULL", Q(got));
			bad = 1;
		}
		k++;
		free(got);
	}
	if (!bad)
		g_ok++;
	g_read_fail = 0;
	g_read_fail_fd = -1;
	if (bad)
		tst_drain(fa);
	close(fa);
	tst_lines(fb, "read error on fd A, then the rest of fd B", b + 7, strlen(b) - 7);
	close(fb);
	fa = tst_open("tst_multi0.txt", a, strlen(a));
	tst_lines(fa, "after a read error on fd A, reading the file again from the start", a, strlen(a));
	close(fa);
	tst_leaks("read error on one fd");
}

static void	tst_bonus(void)
{
	const char	*a = "a1\na2\na3\na4\n";
	const char	*b = "b1\nb2";
	const char	*c = "c1\nc2\nc3\nc4\nc5\nc6\n";
	size_t		len;
	char		*g1 = tst_gen(300, 80, 1, &len);
	char		*g2 = tst_gen(200, 80, 2, &len);

	tst_multi("3 fds in turn (1 line each)", 3, (const char *[]){a, b, c}, (int []){1, 1, 1}, 0);
	tst_multi("3 fds in turn (2 lines from A, 1 from B, 3 from C)", 3, (const char *[]){a, b, c}, (int []){2, 1, 3}, 0);
	tst_multi("3 big files in turn (one of them empty)", 3, (const char *[]){g1, g2, ""}, (int []){1, 2, 1}, 0);
	tst_multi("stdin and a file in turn", 2, (const char *[]){a, c}, (int []){1, 1}, 1);
	free(g1);
	free(g2);
	tst_many_fds();
	tst_bonus_read_error();
}
#endif

static void	tst_on_death(void)
{
	if (g_case)
		printf("\n@@CRASH %s\n", g_case);
}

static void	tst_on_signal(int sig)
{
	printf("\n@@CRASH %s\n@@SIGNAL %d\n@@INREAD %d\n", g_case, sig, g_in_read);
	_exit(128 + sig);
}

#ifdef TST_BS_BAD
/* BUFFER_SIZE <= 0: nothing can be read, get_next_line must return NULL */
int	main(void)
{
	int	fd;

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
	signal(SIGALRM, tst_on_signal);
	alarm(5);
	fd = tst_open("tst_file.txt", "abc\ndef\n", 8);
	tst_expect(fd, "file \"abc\\ndef\\n\", 1st call", NULL);
	tst_expect(fd, "file \"abc\\ndef\\n\", 2nd call", NULL);
	close(fd);
	tst_expect(-1, "get_next_line(-1)", NULL);
	tst_leaks("BUFFER_SIZE <= 0");
	printf("@@RESULT %d %d\n", g_ok, g_ko);
	g_case = NULL;
	return (0);
}
#else
int	main(void)
{
	size_t	len;
	char	*s;
	int		big = BUFFER_SIZE >= 100000;

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
	signal(SIGALRM, tst_on_signal);
	FILE_STR("empty file", "");
	FILE_STR("file \"\\n\"", "\n");
	FILE_STR("file of 5 empty lines", "\n\n\n\n\n");
	FILE_STR("file \"a\" (no \\n)", "a");
	FILE_STR("file \"a\\n\"", "a\n");
	FILE_STR("1 line with a final \\n", "Hello world\n");
	FILE_STR("1 line without a final \\n", "Hello world");
	FILE_STR("3 lines with a final \\n", "line 01\nline 02\nline 03\n");
	FILE_STR("3 lines without a final \\n", "line 01\nline 02\nline 03");
	FILE_STR("empty lines in the middle", "abc\n\n\ndef\n\nghi");
	FILE_STR("special characters", "\t \r\v\f\n\xc3\xa9t\xc3\xa9 \xe2\x82\xac \xff\x80\n~\x01\n");
	tst_read_little();
	s = tst_fill('x', 10000, "\n", &len);
	tst_file("line of 10000 chars + \\n", s, len);
	free(s);
	s = tst_fill('y', 10000, "", &len);
	tst_file("line of 10000 chars without \\n", s, len);
	free(s);
	s = tst_ramp(big ? 50 : 200, &len);
	tst_file("lines of 0 to N chars", s, len);
	free(s);
	if (BUFFER_SIZE <= 100000)
	{
		s = tst_around(&len);
		tst_file("lines of BUFFER_SIZE-1, BUFFER_SIZE and BUFFER_SIZE+1 chars", s, len);
		free(s);
	}
	s = tst_gen(big ? 100 : 2000, 100, 42, &len);
	if (g_greedy)
		tst_fail("big file tests skipped: reading the whole input first is too slow");
	else
	{
		tst_file("big file (random lines)", s, len);
		tst_stdin("stdin (big file)", s, len);
		tst_pipe("pipe (big file)", s, len);
	}
	free(s);
	tst_stdin("empty stdin", "", 0);
	tst_stdin("stdin (3 lines)", "one\ntwo\nthree\n", 14);
	tst_pipe_open();
	tst_bad_fd();
	FILE_STR("normal read after invalid fds", "ok\nok\n");
	tst_read_error();
	tst_malloc_fail();
	tst_short_reads();
	tst_high_fd();
	s = tst_fill('\n', 1000, "", &len);
	tst_file("file of 1000 empty lines", s, len);
	free(s);
#ifdef TST_BONUS
	tst_bonus();
#endif
	printf("@@RESULT %d %d\n", g_ok, g_ko);
	g_case = NULL;
	return (0);
}
#endif
EOF
}

# ------------------------- Reading the ASan report -------------------------- #
user_frame() {
	grep -E "^[[:space:]]+#[0-9]+ .* in [^ ]+ $DIR/" | head -1 \
		| sed -E "s|.* in ([^ ]+) $DIR/([^ ]+).*|\2 (\1)|"
}

asan_report() {
	local err=$1 type loc
	if grep -q "ERROR: AddressSanitizer" "$err"; then
		type=$(grep -m1 -oE "ERROR: AddressSanitizer: [a-zA-Z_-]+" "$err" | awk '{print $3}')
		loc=$(sed -n '/ERROR: AddressSanitizer/,/^$/p' "$err" | user_frame)
		if [ -n "$loc" ]; then
			msg "memory error ($type) in $loc"
		else
			loc=$(sed -n '/allocated by thread/,/^$/p' "$err" | user_frame)
			msg "memory error ($type) while reading the returned line${loc:+ (allocated in $loc)}: missing final '\\0'?"
		fi
		[ "$type" = "stack-overflow" ] && msg "a BUFFER_SIZE-byte array on the stack does not fit: use malloc"
	fi
	if grep -q "ERROR: LeakSanitizer" "$err"; then
		msg "memory leak: $(grep -m1 -oE '[0-9]+ byte\(s\) leaked in [0-9]+ allocation\(s\)' "$err")"
		awk '/leak of/{n++} {print > (FILENAME "." n)}' "$err"
		for blk in "$err".[1-9]*; do
			[ -f "$blk" ] || continue
			loc=$(user_frame < "$blk")
			printf "        ${D}malloc in %s${N}\n" "${loc:-?}"
		done | sort -u | head -4
		rm -f "$err".[1-9]*
	fi
}

# ----------------------- Testing one BUFFER_SIZE build ---------------------- #
# run_bs <label> <BUFFER_SIZE> <mand|bonus>
run_bs() {
	local label=$1 bs=$2 mode=$3 src="$TMP/t_gnl.c" bin="$TMP/t_$3_$2" out rc res ok ko t warns files=() def=()
	if [ "$mode" = bonus ]; then
		files=("${BONUS_C[@]/#/$DIR/}"); def=(-DTST_BONUS)
	else
		files=("${MAND_C[@]/#/$DIR/}")
	fi
	[ "$bs" -le 0 ] && def+=(-DTST_BS_BAD)
	if ! cc $SAN -g -w -D BUFFER_SIZE="$bs" "${def[@]}" -I"$DIR" "$src" "${files[@]}" \
		-Wl,--wrap=malloc -Wl,--wrap=free -Wl,--wrap=read -o "$bin" 2> "$TMP/cerr"; then
		line_ko "$label"
		if grep -q "undefined reference to .get_next_line'" "$TMP/cerr"; then
			msg "get_next_line is not defined (wrong function name?)"
		else
			msg "does not compile: $(first_error "$TMP/cerr")"
		fi
		[ "$bs" -le 0 ] && msg "with BUFFER_SIZE <= 0, get_next_line must compile and return NULL"
		return
	fi
	t=10; [ "$bs" -ge 1000000 ] && t=30
	out=$(cd "$TMP/run" && ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=1" \
		timeout $t "$bin" 2> "$TMP/rerr")
	rc=$?
	res=$(grep -m1 "^@@RESULT" <<< "$out")
	ok=$(awk '{print $2}' <<< "$res"); ko=$(awk '{print $3}' <<< "$res")
	warns=$(grep "^@@WARN " <<< "$out" | sed 's/^@@WARN //')
	if [ -n "$res" ] && [ "$ko" = 0 ] && ! grep -q "Sanitizer" "$TMP/rerr" && ! grep -q "^@@LEAK" <<< "$out"; then
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
		if grep -q "^@@INREAD 1" <<< "$out"; then
			msg "blocked in read() ($t s timeout) during: $(grep "^@@CRASH" <<< "$out" | tail -1 | sed 's/^@@CRASH //')"
		else
			msg "too slow or infinite loop ($t s timeout) during: $(grep "^@@CRASH" <<< "$out" | tail -1 | sed 's/^@@CRASH //')"
		fi
	elif grep -q "^@@SIGNAL 14" <<< "$out" && grep -q "^@@INREAD 1" <<< "$out" && [ "$bs" -gt 0 ]; then
		msg "stuck on read() during: $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	elif grep -q "^@@SIGNAL 14" <<< "$out"; then
		msg "infinite loop during: $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
		[ "$bs" -le 0 ] && msg "with BUFFER_SIZE <= 0, read() never returns data: return NULL before reading"
	elif [ -z "$res" ]; then
		msg "crash during: $(grep -m1 "^@@CRASH" <<< "$out" | sed 's/^@@CRASH //')"
	fi
	grep -m1 "^@@LEAK" <<< "$out" | sed 's/^@@LEAK /memory leak detected after the test: /' \
		| while IFS= read -r m; do msg "$m"; done
	asan_report "$TMP/rerr"
	[ -n "$warns" ] && while IFS= read -r m; do note "!! $m"; done <<< "$warns"
}

# External functions called by object files
ext_funcs() {
	comm -23 \
		<(nm -u "$@" 2>/dev/null | awk 'NF == 2 && $1 == "U" {print $2}' | sed 's/@.*//' | sort -u) \
		<(nm --defined-only "$@" 2>/dev/null | awk 'NF == 3 {print $3}' | sort -u) \
		| grep -vxE '_GLOBAL_OFFSET_TABLE_|__stack_chk_fail|__stack_chk_guard'
}

# Checks on a set of files (strict compilation, functions, global variables)
# check_files <label suffix> <.c files...>
check_files() {
	local sfx=$1 f objs=() err="" bad glob
	shift
	for f in "$@"; do
		if ! cc -Wall -Wextra -Werror -D BUFFER_SIZE=42 -I"$DIR" -c "$DIR/$f" -o "$TMP/strict/$f.o" 2> "$TMP/err"; then
			err="$f: $(first_error "$TMP/err")"
			break
		fi
		objs+=("$TMP/strict/$f.o")
	done
	if [ -n "$err" ]; then
		line_ko "-Wall -Wextra -Werror$sfx"; msg "$err"
		return
	fi
	line_ok "-Wall -Wextra -Werror$sfx"
	err=""
	for f in "$@"; do
		cc -Wall -Wextra -Werror -I"$DIR" -c "$DIR/$f" -o "$TMP/strict/nobs.o" 2> "$TMP/err" \
			|| { err="$f: $(first_error "$TMP/err")"; break; }
	done
	if [ -z "$err" ]; then line_ok "without -D BUFFER_SIZE$sfx"
	else
		line_ko "without -D BUFFER_SIZE$sfx"; msg "$err"
		msg "the subject requires compiling with AND without -D BUFFER_SIZE (default value in the .h)"
	fi
	bad=$(ext_funcs "${objs[@]}" | grep -vxE 'read|malloc|free' | tr '\n' ' ')
	if [ -z "$bad" ]; then line_ok "allowed functions$sfx" "(read malloc free)"
	else
		line_ko "allowed functions$sfx"; msg "forbidden external function(s): $bad"
		grep -qw lseek <<< "$bad" && msg "lseek is explicitly forbidden by the subject"
	fi
	glob=$(nm "${objs[@]}" 2>/dev/null | awk '$2 ~ /^[BCDGRS]$/ {print $3}' | sort -u | tr '\n' ' ')
	if [ -z "$glob" ]; then line_ok "global variables$sfx"
	else line_ko "global variables$sfx"; msg "forbidden global variable(s): $glob"; fi
}

# =================================== Start ================================== #
SAN="-fsanitize=address"
echo 'int main(void){return 0;}' > "$TMP/probe.c"
if ! cc $SAN "$TMP/probe.c" -o "$TMP/probe" 2>/dev/null || ! "$TMP/probe" 2>/dev/null; then
	SAN=""
	printf "${Y}AddressSanitizer unavailable: leaks and buffer overflows will not be detected.${N}\n"
fi

HAS_BONUS=0
[ -f "$DIR/get_next_line_bonus.c" ] && HAS_BONUS=1
harness > "$TMP/t_gnl.c"

# -------------------------------- Submission -------------------------------- #
if [ $# -eq 0 ]; then
	section "Submission"
	missing=""; extra=""
	for f in get_next_line.c get_next_line_utils.c get_next_line.h; do
		[ -f "$DIR/$f" ] || missing+="$f "
	done
	for f in "$DIR"/*.c "$DIR"/*.h; do
		[ -f "$f" ] || continue
		grep -qw "$(basename "$f")" <<< "$ALLOWED_FILES" || extra+="$(basename "$f") "
	done
	if [ -z "$missing$extra" ]; then line_ok "files"
	else
		line_ko "files"
		[ -n "$missing" ] && msg "missing file(s): $missing"
		[ -n "$extra" ] && msg "extra file(s) (\"Submitting unused files is not allowed\"): $extra"
	fi
	if [ -f "$DIR/README.md" ]; then
		m=(); miss=""
		head -1 "$DIR/README.md" | tr -d '\r' | grep -qE '^[*_]This project has been created as part of the 42 curriculum by .+[*_][[:space:]]*$' \
			|| m+=("first line must be in italics: *This project has been created as part of the 42 curriculum by <login>.*")
		# "Ressources" is accepted too: the README may be in the campus language
		for s in Description Instructions 'Resources|Ressources'; do
			grep -qiE "^#+.*($s)" "$DIR/README.md" || miss+="${s%%|*} "
		done
		[ -n "$miss" ] && m+=("missing section(s): $miss")
		if [ ${#m[@]} -eq 0 ]; then line_ok "README.md"
		else line_ko "README.md"; for s in "${m[@]}"; do msg "$s"; done; fi
	else
		line_ko "README.md"; msg "README.md missing (mandatory)"
	fi
	if [ -f "$DIR/get_next_line.h" ] && grep -qE 'char[[:space:]]*\*[[:space:]]*get_next_line[[:space:]]*\([[:space:]]*int([[:space:]]+[a-zA-Z_]+)?[[:space:]]*\)' "$DIR/get_next_line.h"; then
		line_ok "prototype"
	else
		line_ko "prototype"; msg "get_next_line.h must contain: char *get_next_line(int fd);"
	fi
	if grep -lE '#[[:space:]]*include[[:space:]]+"[^"]*libft' "$DIR"/*.c "$DIR"/*.h > /dev/null 2>&1; then
		line_ko "libft"; msg "libft is forbidden in this project"
	fi
	mk=""
	for f in Makefile makefile GNUmakefile; do [ -f "$DIR/$f" ] && mk+="$f "; done
	if [ -n "$mk" ]; then
		line_ko "no Makefile"; msg "found: $mk(the subject says \"Makefile: No\" for get_next_line, remove it)"
	fi
	if [ -z "$missing" ]; then
		check_files "" "${MAND_C[@]}"
	fi
	if command -v norminette > /dev/null 2>&1; then
		files=()
		for f in $ALLOWED_FILES; do [ -f "$DIR/$f" ] && files+=("$f"); done
		nerr=$(cd "$DIR" && norminette "${files[@]}" 2>&1 | grep -E ': Error!' | sed -E 's/: Error!//' | tr '\n' ' ')
		if [ -z "$nerr" ]; then line_ok "norminette"
		else line_ko "norminette"; msg "errors in: $nerr"; fi
	else
		line_skip "norminette" "not installed"
	fi
fi

# ------------------------------ Mandatory part ------------------------------ #
section "Mandatory part"
if [ ! -f "$DIR/get_next_line.c" ] || [ ! -f "$DIR/get_next_line_utils.c" ]; then
	line_skip "get_next_line" "get_next_line.c / get_next_line_utils.c missing"
else
	for bs in "${SIZES[@]}"; do
		run_bs "BUFFER_SIZE=$bs" "$bs" mand
	done
	if [ $# -eq 0 ]; then
		for bs in 0 -1; do
			run_bs "BUFFER_SIZE=$bs (NULL expected)" "$bs" mand
		done
	fi
fi

# ---------------------------------- Bonus ----------------------------------- #
section "Bonus"
if [ $HAS_BONUS -eq 0 ]; then
	line_skip "bonus" "get_next_line_bonus.c missing"
else
	missing=""
	for f in get_next_line_bonus.c get_next_line_utils_bonus.c get_next_line_bonus.h; do
		[ -f "$DIR/$f" ] || missing+="$f "
	done
	if [ -n "$missing" ]; then
		line_ko "bonus files"; msg "missing file(s): $missing"
	else
		[ $# -eq 0 ] && check_files " (bonus)" "${BONUS_C[@]}"
		# only one static variable allowed
		statics=$(cat "$DIR/get_next_line_bonus.c" "$DIR/get_next_line_utils_bonus.c" \
			| grep -E '^[[:space:]]*static[[:space:]]' | grep -v '(' | sed -E 's/^[[:space:]]+//')
		nst=$(grep -c . <<< "$statics")
		if [ "$nst" -le 1 ]; then line_ok "one static variable"
		else
			line_ko "one static variable"; msg "the bonus must use ONE static variable, found $nst:"
			while IFS= read -r l; do printf "        ${D}%s${N}\n" "$l"; done <<< "$statics"
		fi
		for bs in "${SIZES[@]}"; do
			run_bs "BUFFER_SIZE=$bs" "$bs" bonus
		done
		if [ $# -eq 0 ]; then
			for bs in 0 -1; do
				run_bs "BUFFER_SIZE=$bs (NULL expected)" "$bs" bonus
			done
		fi
	fi
fi

printf "\n${B}Result:${N} ${G}%d OK${N}, ${R}%d KO${N}, ${Y}%d warning(s)${N}, ${D}%d skipped${N}\n" \
	"$N_OK" "$N_KO" "$N_WARN" "$N_SKIP"
disclaimer
[ "$N_KO" -eq 0 ]
