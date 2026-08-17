#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <unistd.h>

enum { STAT_CAP = 4096 };

static int process_starttime(pid_t pid, unsigned long long *starttime) {
  char path[64];
  char record[STAT_CAP + 1];
  char *closing = NULL;
  char *cursor;
  char *saveptr = NULL;
  char *token;
  int fd;
  int field = 0;
  ssize_t size;

  if (snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid) >= (int)sizeof(path)) {
    return -1;
  }
  fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return -1;
  }
  size = read(fd, record, STAT_CAP);
  if (size <= 0 || size == STAT_CAP || close(fd) != 0) {
    return -1;
  }
  record[size] = '\0';
  for (cursor = record; (cursor = strstr(cursor, ") ")) != NULL; cursor += 2) {
    closing = cursor;
  }
  if (closing == NULL) {
    return -1;
  }
  cursor = closing + 2;
  for (token = strtok_r(cursor, " ", &saveptr); token != NULL;
       token = strtok_r(NULL, " ", &saveptr), ++field) {
    if (field == 19) {
      char *end = NULL;
      errno = 0;
      *starttime = strtoull(token, &end, 10);
      return errno == 0 && end != token && (*end == '\0' || *end == '\n') ? 0 : -1;
    }
  }
  return -1;
}

static int identity_matches(const char *pid_text, const char *starttime_text) {
  char *pid_end = NULL;
  char *starttime_end = NULL;
  unsigned long parsed_pid;
  unsigned long long expected_starttime;
  unsigned long long actual_starttime;

  errno = 0;
  parsed_pid = strtoul(pid_text, &pid_end, 10);
  if (errno != 0 || pid_end == pid_text || *pid_end != '\0' || parsed_pid == 0) {
    return 1;
  }
  errno = 0;
  expected_starttime = strtoull(starttime_text, &starttime_end, 10);
  if (errno != 0 || starttime_end == starttime_text || *starttime_end != '\0') {
    return 1;
  }
  return process_starttime((pid_t)parsed_pid, &actual_starttime) == 0 &&
                 actual_starttime == expected_starttime
             ? 0
             : 1;
}

int main(int argc, char **argv) {
  unsigned long long starttime;
  FILE *identity;

  if (argc == 4 && strcmp(argv[1], "--identity") == 0) {
    return identity_matches(argv[2], argv[3]);
  }
  if (argc != 2) {
    return 64;
  }
  if (prctl(PR_SET_NAME, "ssh bad\n)x", 0, 0, 0) != 0 ||
      signal(SIGTERM, SIG_IGN) == SIG_ERR ||
      process_starttime(getpid(), &starttime) != 0) {
    return 1;
  }
  identity = fopen(argv[1], "wx");
  if (identity == NULL) {
    return 1;
  }
  if (fprintf(identity, "%ld %llu\n", (long)getpid(), starttime) < 0 ||
      fclose(identity) != 0) {
    return 1;
  }
  close(STDIN_FILENO);
  close(STDOUT_FILENO);
  close(STDERR_FILENO);
  for (;;) {
    pause();
  }
}
