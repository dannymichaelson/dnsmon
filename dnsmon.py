from flask import Flask, flash, render_template, redirect, request, url_for
import re
import subprocess

app = Flask(__name__)
app.secret_key = '\r\xa5\x89\xcfw\x1c+\xb4 \xdf\x92KS_\xd7X\xb0\x19+\x99\xfa\x97\xad\x03'

all_log = []
hostname_count = {}
blocked_queries = []
blocked_hosts = []
last_size = 0


def restart_dnsmasq():
    subprocess.call(['service', 'dnsmasq', 'restart'])


def get_queries():
    with open('/var/log/dnsmon.log', 'r') as f:
        # Keep track of what we've read and continue from where we left off
        global last_size
        position = last_size
        f.seek(last_size)
        for line in f:
            if line.find('query') != -1 or line.find('config') != -1 or line.find('reply') != -1 or line.find('forwarded') != -1 or line.find('chached') != -1:
                all_log.append(line)
                # Query reqeusts
                if line.find('query') != -1:
                    tokens = line.strip().split(" ")
                    if len(tokens) == 9:
                        tokens.pop(1)
                    hostname = tokens[5]
                    requester = tokens[-1]
                    date = (" ").join(tokens[0:3])
                    hostname_count[hostname] = hostname_count.get(hostname, 0) + 1
                # Replies
                elif line.find('config') != -1:
                    # Did we return localhost? ie block
                    if line.find('127.0.0.1') != -1:
                        tokens = line.strip().split(" ")
                        if len(tokens) == 9:
                            tokens.pop(1)
                        hostname = tokens[5]
                        requester = tokens[-1]
                        date = (" ").join(tokens[0:3])
                        blocked_queries.append({'hostname': hostname, 'requester': requester, 'date': date})
            position += 1
    # Keep track of how many lines we've seen
    last_size = position


def get_query_stats():
    sorted_stats = sorted(hostname_count, key=hostname_count.get)
    return sorted_stats


def get_blocked_hosts():
    try:
        with open('/etc/dnsmasq.d/dnsmon.conf', 'r') as f:
            blocked_hosts.clear()
            for line in f:
                if line.find('address') != -1:
                    blocked_hosts.append(line[9:-11])
    except IOError:
        return


def add_blocked_host(hostname):
    if hostname in blocked_hosts:
        flash("Hostname already being blocked.")
        return

    with open('/etc/dnsmasq.d/dnsmon.conf', 'a+') as f:
        f.write('address=/{!s}/127.0.0.1\n'.format(hostname))
    blocked_hosts.append(hostname)
    restart_dnsmasq()


def del_blocked_host(hostname):
    if hostname not in blocked_hosts:
        flash("Hostname not being blocked.")
        return

    with open('/etc/dnsmasq.d/dnsmon.conf', 'r+') as f:
        lines = f.readlines()
        f.seek(0)
        for line in lines:
            if line.find('{!s}'.format(hostname)) == -1:
                f.write(line)
        f.truncate()
    blocked_hosts.remove(hostname)
    restart_dnsmasq()


@app.route("/")
def index():
    get_queries()
    stats = get_query_stats()
    if len(stats) < 10:
        min_stats = stats
        max_stats = stats
    else:
        min_stats = stats[:10]
        max_stats = stats[-10:]
    return render_template('queries.html', logs=reversed(all_log), blocked_queries=reversed(blocked_queries),
                           blocked_hosts=blocked_hosts, min_hosts=min_stats, max_hosts=reversed(max_stats))


@app.route("/", methods=['POST'])
def update_hosts():
    host = request.form['hostname']
    regex = re.compile(r'(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)')
    if not re.match(regex, host):
        flash("Please enter a valid hostname")

    elif request.form['change-host'] == 'add':
        add_blocked_host(host)
        flash('Added {!s} to blocked hosts.'.format(host))

    elif request.form['change-host'] == 'del':
        del_blocked_host(host)
        flash('Removed {!s} from blocked hosts.'.format(host))

    return redirect(url_for('index'))


if __name__ == "__main__":
    get_queries()
    get_blocked_hosts()
    app.run(host='0.0.0.0')
