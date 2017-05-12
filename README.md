dnsmon
========

## Note: There is currently no uninstaller.

#### Install on a raspberrypi. Set the pi as the dns server for any devices you want to monitor. Will automatically work for requests made on the pi. Might support any debian system.

Download
```shell
cd dnsmon/install
chmod +x install.sh
sudo ./install.sh
```
REBOOT then start web interface
```shell
sudo reboot now
cd dnsmon
sudo python3 dnsmon.py
```

visit the web interface at http://127.0.0.1:5000 on the pi or http://<pi-local-ip>:5000 on your LAN.

##### To remove (possibly incomplete)
Uninstall dnsmasq, or at least replace /etc/dnsmasq.conf with /etc/dnsmasq.conf.orig
Delete dnsmon user
Delete /etc/dnsmasq.d/dnsmon.conf

![screenshot](https://github.com/danielmichaelson/dnsmon/blob/master/webinterface.png?raw=true)