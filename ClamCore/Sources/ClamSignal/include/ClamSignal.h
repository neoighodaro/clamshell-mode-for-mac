#ifndef CLAM_SIGNAL_H
#define CLAM_SIGNAL_H

#include <stdint.h>

/// Publish the IOPMrootDomain user-client connection (a Mach port name) to the
/// signal handlers. Pass 0 to withdraw it.
void clam_signal_set_connection(uint32_t connection);

/// Best-effort: ask the kernel to restore lid-close sleep. Safe to call with no connection.
void clam_signal_emergency_clear(void);

/// Install the crash, termination and alarm handlers. Call once, on the main thread.
/// Returns 0 on success.
int clam_signal_install(void);

/// Read end of the termination pipe. One byte (the signal number) arrives per
/// termination signal. Valid after clam_signal_install().
int clam_signal_termination_fd(void);

/// Cancel the 5 second alarm armed by a termination signal.
void clam_signal_termination_done(void);

#endif
