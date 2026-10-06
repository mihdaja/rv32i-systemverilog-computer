#!/usr/bin/env python3
import sys
import tty
import termios
import socket
import select
import os

def main():
    host = "127.0.0.1"
    port = 9000

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect((host, port))
    except Exception as e:
        print(f"Error connecting to simulated CPU on {host}:{port}: {e}")
        sys.exit(1)

    # Put terminal in raw mode if running in a TTY
    is_tty = sys.stdin.isatty()
    old_settings = None
    if is_tty:
        # Clear whole screen and scrollback buffer before session begins
        sys.stdout.write("\033[2J\033[3J\033[H")
        sys.stdout.flush()
        old_settings = termios.tcgetattr(sys.stdin)
        tty.setraw(sys.stdin.fileno())

    try:
        while True:
            rlist = [s, sys.stdin]
            
            readable, _, _ = select.select(rlist, [], [])

            if sys.stdin in readable:
                ch = os.read(sys.stdin.fileno(), 1)
                if not ch:
                    break
                s.sendall(ch)
                # Allow Ctrl-C (0x03) to break
                if ch == b'\x03':
                    break

            if s in readable:
                data = s.recv(1024)
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)

    except KeyboardInterrupt:
        pass
    finally:
        if is_tty and old_settings:
            # Restore cursor and terminal attributes
            sys.stdout.write("\033[?25h")
            sys.stdout.flush()
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        s.close()
        print("\n[Terminal session ended]")

if __name__ == "__main__":
    main()
