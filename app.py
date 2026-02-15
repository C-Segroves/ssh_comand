# app.py  (updated - non-interactive version)
from flask import Flask, request, render_template, jsonify
from flask_socketio import SocketIO, emit
import paramiko
import threading
import os
from paramiko import RSAKey, SSHClient, AutoAddPolicy

app = Flask(__name__)
socketio = SocketIO(app)

# In-memory storage for registered hosts
hosts = {}

# ────────────────────────────────────────────────
# SSH key loading — now non-interactive
# ────────────────────────────────────────────────
PRIVATE_KEY = None
KEY_PASSPHRASE = os.getenv("SSH_KEY_PASSPHRASE")   # optional env var

key_path = os.getenv("SSH_PRIVATE_KEY_PATH", "/root/.ssh/id_rsa")

if os.path.isfile(key_path):
    try:
        PRIVATE_KEY = RSAKey.from_private_key_file(
            key_path,
            password=KEY_PASSPHRASE if KEY_PASSPHRASE else None
        )
        print(f"Loaded SSH private key from {key_path}")
    except paramiko.PasswordRequiredException:
        print("Error: Private key requires passphrase, but SSH_KEY_PASSPHRASE env var is empty or missing.")
        PRIVATE_KEY = None
    except Exception as e:
        print(f"Failed to load private key: {e}")
        PRIVATE_KEY = None
else:
    print(f"No private key found at {key_path} — will require password on registration")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    name = data.get('name')
    ip = data.get('ip')
    username = data.get('username')
    password = data.get('password')   # fallback only if no key

    if not name or not ip or not username:
        return jsonify({'error': 'Missing required fields'}), 400

    if name in hosts:
        return jsonify({'error': 'Host name already registered'}), 400

    client = SSHClient()
    client.set_missing_host_key_policy(AutoAddPolicy())

    connect_args = {
        'hostname': ip,
        'username': username,
        'timeout': 10,
    }

    auth_used = "key" if PRIVATE_KEY else "password"

    try:
        if PRIVATE_KEY:
            connect_args['pkey'] = PRIVATE_KEY
        elif password:
            connect_args['password'] = password
        else:
            return jsonify({'error': 'No auth method: load key or provide password'}), 400

        client.connect(**connect_args)
        hosts[name] = {
            'ip': ip,
            'username': username,
            'client': client,
        }
        return jsonify({'message': f"Registered '{name}' using {auth_used} auth"})
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/hosts', methods=['GET'])
def get_hosts():
    return jsonify(list(hosts.keys()))

@socketio.on('execute_command')
def execute_command(data):
    command = data.get('command')
    target  = data.get('target', 'all')     # 'all', 'selected', or hostname
    selected_hosts = data.get('hosts', [])  # list when target=='selected'

    if not command:
        emit('command_results', {'error': 'No command provided'})
        return

    results = {}

    def run_on_host(hostname, host_data):
        try:
            stdin, stdout, stderr = host_data['client'].exec_command(command)
            output = stdout.read().decode('utf-8').strip()
            error  = stderr.read().decode('utf-8').strip()
            results[hostname] = {
                'ip': host_data['ip'],
                'output': output,
                'error': error if error else None
            }
        except Exception as e:
            results[hostname] = {
                'ip': host_data['ip'],
                'error': str(e)
            }

    if target == 'selected':
        if not selected_hosts:
            results['_meta'] = {'target': 'selected'}
            emit('command_results', results, broadcast=True)
            return
        threads = []
        for hostname in selected_hosts:
            if hostname in hosts:
                t = threading.Thread(target=run_on_host, args=(hostname, hosts[hostname]))
                t.start()
                threads.append(t)
        for t in threads:
            t.join()
        results['_meta'] = {'target': 'selected'}

    elif target == 'all':
        threads = []
        for hostname, host_data in hosts.items():
            t = threading.Thread(target=run_on_host, args=(hostname, host_data))
            t.start()
            threads.append(t)
        for t in threads:
            t.join()
        results['_meta'] = {'target': 'all'}

    else:  # single host
        if target in hosts:
            run_on_host(target, hosts[target])
            results['_meta'] = {'target': 'single'}
        else:
            results[target] = {'error': 'Host not found'}

    emit('command_results', results, broadcast=True)

if __name__ == '__main__':
    print("\nStarting LAN Command Server...")
    print("Open http://localhost:5000 (or your-server-ip:5000) in browser")
    socketio.run(app, host='0.0.0.0', port=5000, allow_unsafe_werkzeug=True)