import atexit
import os
import shlex
import signal
import sys


def start_child(shell_command):
    pid = os.fork()
    if pid:
        return pid
    else:
        os.setsid()
        args = shlex.split(shell_command)
        os.execvp(args[0], args)


def cleanup():
    for child_pid in children:
        try:
            os.killpg(os.getpgid(child_pid), signal.SIGTERM)
        except OSError:
            # Probably already dead.
            pass


def hup(*args):
    # Just exit and let our atexit handler clean things up.
    sys.exit()


def register_cleanup():
    atexit.register(cleanup)
    # atexit won't run on HUP unless we've set up a handler for the signal.
    # From https://docs.python.org/3/library/atexit.html:
    #
    #  > Note: The functions registered via this module are not called when the
    #  > program is killed by a signal not handled by Python, when a Python
    #  > fatal internal error is detected, or when os._exit() is called.
    #
    # (HUP is what the shell sends us when it exits, so it's important to
    # handle that and cleanup.)
    signal.signal(signal.SIGHUP, hup)


children = []


def main():
    register_cleanup()

    shell_commands = sys.argv[1:]
    for command in shell_commands:
        children.append(start_child(command))

    # When any child dies, exit (thereby killing all the other children).
    try:
        os.wait()
    except (KeyboardInterrupt, OSError):
        pass


if __name__ == '__main__':
    main()
