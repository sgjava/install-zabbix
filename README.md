![Title](images/title.png)

Install Zabbix is a set of scripts to install/upgrade Zabbix 6.2.x from source on Ubuntu
22.05 and probably other Debian derived distributions. You can of course use
various methods to install Zabbix Server, but this method gives you the ultimate
flexibility. In addition, there are no deb packages for ARM32 based platforms hence
building from source is the only method. The scripts allow:
* Install and secure MySQL server
* Import Zabbix data into MySQL
* Install Java 17 JDK for the Java gateway and enable in build
* Patch source to fix "plugins/proc/procfs_linux.go:248:6: constant 1099511627776 overflows int" on 32 bit systems
* Install Zabbix Server
* Create zbx_monitor user for local MySQL monitoring (just configure and add 'Template DB MySQL by Zabbix agent 2' template to 'Zabbix server')
* Install Zabbix Agent 2
* Create systemd services for both Zabbix Server and Agent 2
* Move MySQL data directory (optional)
* Install Zabbix Agent 2 on clients (optional)

**Important note:** Before upgrading Zabbix see [Upgrade from sources](https://www.zabbix.com/documentation/current/en/manual/installation/upgrade/sources). 
To be on the safe side I would [export](https://www.zabbix.com/documentation/current/en/manual/xml_export_import) Zabbix
server configuration, shut down Zabbix server service and [backup](https://linuxconfig.org/linux-commands-to-backup-and-restore-mysql-database)
MySQL database. If you are using a VM just make a snapshot before upgrading and rollback 
if you have problems. As always, you should test upgrade on a VM first if possible.

**Upgrading error** If you get ```The Zabbix database version does not match current requirements. Your database version: 6010048. Required version: 6020000. Please contact your system administrator.```
in UI and ```[Z3005] query failed: [1419] You do not have the SUPER privilege and binary logging is enabled (you *might* want to use the less safe log_bin_trust_function_creators variable) [create trigger hosts_insert after insert on hosts``` 
in log.
* `sudo service zabbix-server stop`
* `sudo mysql -u root`
* `SET GLOBAL log_bin_trust_function_creators = 1;`
* `commit;`
* `quit`
* `sudo service zabbix-server start`
* Check /tmp/zabbix_server.log

More [configuration](https://techexpert.tips/category/zabbix) options!

## Download project
* `cd ~/`
* `git clone --depth 1 https://github.com/sgjava/install-zabbix.git`

## Install script
This assumes a fresh OS install. You should try the scripts out on a VM to play
with configuration prior to doing final install. Upgrade is performed if existing
install detected and configuration is saved to `/usr/local/etc/zabbix_server.conf.bak`
and `/usr/local/etc/zabbix_agent2.conf.bak`
* `cd ~/install-zabbix/scripts`
* Change configuration values as needed
* `./install.sh`
* Check log file for errors
* Navigate to http://hostname/zabbix
* Get DB password from script and finalize front end configuration
* Login using Admin/zabbix

To stop and start Zabbix server
* `sudo service zabbix-server stop`
* `sudo service zabbix-server start`

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

To stop and start MySQL server
* `sudo service mysql stop`
* `sudo service mysql start`

These changes can be removed during `apt upgrade`, so if you see mysql fail to start after reboot add service changes back in. 

## Install Agent 2 script
Install Zabbix Agent 2 script on client. Make sure to change configuration to point to
your Zabbix server before running. You can always configure manually should you forget.
Upgrade is performed if existing install detected and configuration is saved to `/usr/local/etc/zabbix_agent2.conf.bak`
* `cd ~/install-zabbix/scripts`
* Change configuration values as needed
* `./install-agent2.sh`
* Check log file for errors

To stop and start Zabbix Agent 2
* `sudo service zabbix-agent2 stop`
* `sudo service zabbix-agent2 start`
