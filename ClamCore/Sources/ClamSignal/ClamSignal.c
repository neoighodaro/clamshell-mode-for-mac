#include "ClamSignal.h"

#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

// kPMSetClamshellSleepState in XNU's RootDomainUserClient.
#define CLAM_SET_CLAMSHELL_SLEEP_STATE 12

static volatile io_connect_t g_connection = 0;
static int g_pipe[2] = {-1, -1};
static char g_alt_stack[64 * 1024];

void clam_signal_set_connection(uint32_t connection) {
    g_connection = (io_connect_t)connection;
}

void clam_signal_emergency_clear(void) {
    io_connect_t connection = g_connection;
    if (connection == 0) {
        return;
    }
    uint64_t value = 0;
    IOConnectCallScalarMethod(connection, CLAM_SET_CLAMSHELL_SLEEP_STATE, &value, 1, NULL, NULL);
}

static void crash_handler(int sig) {
    // The clear is a Mach call with no timeout. Arm SIGALRM first so a hang cannot leave a zombie.
    alarm(5);
    clam_signal_emergency_clear();
    signal(sig, SIG_DFL);
    raise(sig);
}

static volatile sig_atomic_t g_termination_armed = 0;

static void termination_handler(int sig) {
    int saved = errno;
    // Arm the deadline once, so repeated signals cannot push it out.
    if (!g_termination_armed) {
        g_termination_armed = 1;
        alarm(5);
    }
    clam_signal_emergency_clear();
    unsigned char byte = (unsigned char)sig;
    ssize_t written = write(g_pipe[1], &byte, 1);
    (void)written;
    errno = saved;
}

static void alarm_handler(int sig) {
    (void)sig;
    _exit(1);
}

int clam_signal_install(void) {
    if (g_pipe[0] == -1) {
        if (pipe(g_pipe) != 0) {
            return -1;
        }
        for (int i = 0; i < 2; i++) {
            fcntl(g_pipe[i], F_SETFL, O_NONBLOCK);
            fcntl(g_pipe[i], F_SETFD, FD_CLOEXEC);
        }
    }

    // Crash handlers run on an alternate stack so a stack overflow can still be handled.
    // sigaltstack is per-thread; this covers the calling (main) thread.
    stack_t stack;
    stack.ss_sp = g_alt_stack;
    stack.ss_size = sizeof g_alt_stack;
    stack.ss_flags = 0;
    sigaltstack(&stack, NULL);

    struct sigaction action;
    memset(&action, 0, sizeof action);
    sigemptyset(&action.sa_mask);

    action.sa_handler = crash_handler;
    action.sa_flags = SA_ONSTACK;
    const int crash[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGSYS};
    for (unsigned i = 0; i < sizeof crash / sizeof crash[0]; i++) {
        if (sigaction(crash[i], &action, NULL) != 0) {
            return -1;
        }
    }

    action.sa_handler = termination_handler;
    action.sa_flags = SA_RESTART;
    const int termination[] = {SIGTERM, SIGINT, SIGHUP, SIGQUIT};
    for (unsigned i = 0; i < sizeof termination / sizeof termination[0]; i++) {
        if (sigaction(termination[i], &action, NULL) != 0) {
            return -1;
        }
    }

    action.sa_handler = alarm_handler;
    action.sa_flags = 0;
    if (sigaction(SIGALRM, &action, NULL) != 0) {
        return -1;
    }

    signal(SIGPIPE, SIG_IGN);
    return 0;
}

int clam_signal_termination_fd(void) {
    return g_pipe[0];
}

void clam_signal_termination_done(void) {
    alarm(0);
}
