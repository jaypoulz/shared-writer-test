#!/usr/bin/env python3
import os
import sys
import time
from datetime import datetime
import socket

# Ensure output is unbuffered
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buffering=1)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buffering=1)

def writer_mode():
    """Writer mode - writes to the shared file"""
    hostname = socket.gethostname()
    node_name = os.environ.get('NODE_NAME', 'unknown-node')
    shared_file = '/mnt/shared/output.txt'

    # Ensure the shared directory exists
    os.makedirs('/mnt/shared', exist_ok=True)

    # Run for 10 minutes (600 seconds), writing every 15 seconds
    # That's 40 iterations
    iterations = 40
    interval = 15

    print(f"Starting WRITER on pod: {hostname}, node: {node_name}", flush=True)
    print(f"Will write to {shared_file} every {interval} seconds for {iterations} iterations", flush=True)
    sys.stdout.flush()

    for i in range(iterations):
        timestamp = datetime.now().isoformat()
        message = f"Pod: {hostname} | Node: {node_name} | Timestamp: {timestamp} | Iteration: {i+1}/{iterations}\n"

        # Write to shared file with append mode
        try:
            with open(shared_file, 'a') as f:
                f.write(message)
            print(f"Written: {message.strip()}", flush=True)
        except Exception as e:
            print(f"Error writing to file: {e}", flush=True)

        # Wait for next iteration (skip on last iteration)
        if i < iterations - 1:
            time.sleep(interval)

    print(f"Completed all {iterations} iterations. Writer finished.", flush=True)
    print("Keeping container alive for log inspection...", flush=True)

    # Keep container running for a bit after completion
    time.sleep(300)  # 5 minutes

def reader_mode():
    """Reader mode - reads and displays the shared file"""
    hostname = socket.gethostname()
    node_name = os.environ.get('NODE_NAME', 'unknown-node')
    shared_file = '/mnt/shared/output.txt'

    iterations = 40
    interval = 15

    print(f"Starting READER on pod: {hostname}, node: {node_name}", flush=True)
    print(f"Will read from {shared_file} every {interval} seconds for {iterations} iterations", flush=True)
    sys.stdout.flush()

    # Track the last position we read to
    last_position = 0

    for i in range(iterations):
        try:
            # Check if file exists
            if os.path.exists(shared_file):
                # Get file size
                file_size = os.path.getsize(shared_file)

                # Read new content if file has grown
                if file_size > last_position:
                    with open(shared_file, 'r') as f:
                        f.seek(last_position)
                        new_content = f.read()
                        last_position = f.tell()

                    if new_content:
                        print(f"[Iteration {i+1}/{iterations}] New content read:")
                        print(new_content.rstrip())
                    else:
                        print(f"[Iteration {i+1}/{iterations}] No new content (position: {last_position})")
                else:
                    print(f"[Iteration {i+1}/{iterations}] No changes (size: {file_size} bytes)")
            else:
                print(f"[Iteration {i+1}/{iterations}] File does not exist yet, waiting...")
        except Exception as e:
            print(f"[Iteration {i+1}/{iterations}] Error reading file: {e}")

        # Wait for next iteration (skip on last iteration)
        if i < iterations - 1:
            time.sleep(interval)

    print(f"Completed all {iterations} iterations. Reader finished.", flush=True)
    print("Keeping container alive for log inspection...", flush=True)

    # Keep container running for a bit after completion
    time.sleep(300)  # 5 minutes

def main():
    # Get the role from environment variable (default to writer for backward compatibility)
    role = os.environ.get('ROLE', 'writer').lower()

    # Immediate startup message
    print(f"========================================", flush=True)
    print(f"Storage Demo Application Starting", flush=True)
    print(f"Role: {role}", flush=True)
    print(f"Hostname: {socket.gethostname()}", flush=True)
    print(f"Node: {os.environ.get('NODE_NAME', 'unknown')}", flush=True)
    print(f"Pod: {os.environ.get('POD_NAME', 'unknown')}", flush=True)
    print(f"========================================", flush=True)
    sys.stdout.flush()

    if role == 'reader':
        reader_mode()
    else:
        writer_mode()

if __name__ == '__main__':
    main()
