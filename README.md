![Title](images/title.png)

Install Zabbix is a set of scripts to install Zabbix 6.0.x from source on Ubuntu
22.05 and probably other Debian derived distributions. You can of course use
various methods to install Zabbix Server, but this method gives you the ultimate
flexibility. In addition, there are no deb packages for ARM based platforms hence
building from source is the only method. The scripts allow:
* Install and secure MySQL server
* Import Zabbix data into MySQL
* Install Java 17 JDK for the Java gateway
* Patch source to fix "plugins/proc/procfs_linux.go:248:6: constant 1099511627776 overflows int" on 32 bit systems
* Install Zabbix Server
* Configures macros for local MySQL monitoring (just add 'Template DB MySQL by Zabbix agent 2' template to 'Zabbix server')
* Install Zabbix Agent 2
* Create systemd services for both Zabbix Server and Agent 2
* Move MySQL data directory (optional)
* Install Zabbix Agent 2 on clients (optional)

More [configuration](https://techexpert.tips/category/zabbix) options!

## Download project
* `cd ~/`
* `git clone --depth 1 https://github.com/sgjava/install-zabbix.git`

## Install script
This assumes a fresh OS install. You should try the scripts out on a VM to play
with configuration prior to doing final install.
* `cd ~/install-zabbix/scripts`
* Change configuration values as needed
* `./install.sh`
* Check log file for errors
* Navigate to http://hostname/zabbix
* Get DB password from script and finalize front end configuration
* Login using Admin/zabbix

## Move DB script
This assumes you ran install.sh above. It's handy to move the MySQL data directory
to a NFS share if you are running Zabbix Server off an SD card for instance.
* `cd ~/install-zabbix/scripts`
* Change configuration values as needed
* `./movedb.sh`
* Check log file for errors

If you plan on using a NFS mount for your MySQL data directory you will need to
do the following:
* `sudo nano /etc/systemd/system/multi-user.target.wants/mysql.service`
* Add `remote-fs.target` to `After`
* Add `RequiresMountsFor=/your/mount/dir` to `[Unit]` section
* `sudo systemctl daemon-reload`

These changes can be removed during `apt upgrade`, so if you see mysql fail to start after reboot add service changes back in. 

## Install Agent 2 script
Install Zabbix Agent 2 script on client. Make sure to change configuration to point to
your Zabbix server before running. You can always configure manually should you forget. 
* `cd ~/install-zabbix/scripts`
* Change configuration values as needed
* `./install-agent2.sh`
* Check log file for errors
