# Manual install of a Ceph Cluster on 3 nodes.

### Fetching software.

First of we want to check that we have all the latest packages in debian systemes.
```
apt update
apt upgrade
```

Next we fetch the keys and ceph packages, in this case we download the pacific packages for bullseye.
```
wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
echo deb https://download.ceph.com/debian-pacific/ bullseye main | sudo tee /etc/apt/sources.list.d/ceph.list
apt update
apt install ceph ceph-common
```

A reboot when we have installed packages is always a good thing and if we need to do some extra hardware changes this is a good place to do so.
```
shutdown -r now
```

### Configure node 1 which is server1

First we will create a ceph configuration file.
```
sudo vi /etc/ceph/ceph.conf
```

The most important things to specify is the id and ips of our cluster monitors. A unique cluster id that we will reuse for all your nodes. And lastly a public network range that we want our monitors to be available over. The cluster network is a good addition if you have the resources to route the recovery traffic on a backbone network.
```
[global]
fsid = {cluster uuid}
mon initial members = server1, server2, server3
mon host = 192.168.10.10,192.168.10.20,192.168.10.30
public network = 192.168.10.0/24
cluster network = 10.0.0.0/24
auth cluster required = cephx
auth service required = cephx
auth client required = cephx
```

Next we create keys for admin, monitors and boostrapping our drives. These keys will then be merged with the monitor key so the initial setup will have the keys used for other operations.
```
sudo ceph-authtool --create-keyring /tmp/monkey --gen-key -n mon. --cap mon 'allow *'
sudo ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
sudo ceph-authtool --create-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring --gen-key -n client.bootstrap-osd --cap mon 'profile bootstrap-osd'
sudo ceph-authtool /tmp/monkey --import-keyring /etc/ceph/ceph.client.admin.keyring
sudo ceph-authtool /tmp/monkey --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
```

Make the monitor key available to the ceph user so we don't get an permission error when we start our services.
```
sudo chown ceph:ceph /tmp/monkey
```

Next up we create a monitor map so the monitors will know of each other. The monitors keeps track on other resources but for high availability the monitors needs to know who is in charge.
```
monmaptool --create --add server1 192.168.10.10 --fsid {cluster uuid} /tmp/monmap
monmaptool --add server2 192.168.10.20 --fsid {cluster uuid} /tmp/monmap
monmaptool --add server3 192.168.10.30 --fsid {cluster uuid} /tmp/monmap
```

Starting a new monitor , creating the filesystem for and starting the service.
```
sudo -u ceph mkdir /var/lib/ceph/mon/ceph-server1
sudo -u ceph ceph-mon --mkfs -i server1 --monmap /tmp/monmap --keyring /tmp/monkey
sudo systemctl start ceph-mon@server1
```

Next up we need a manager so we could configure and monitor our cluster through a visual dashboard. First we create a new key, put that key in a newly created directory and start the service. Enabling a dashboard is as easy as running the command for enabling, creating / assigning a certificate and creating a new admin user.
```
sudo ceph auth get-or-create mgr.server1 mon 'allow profile mgr' osd 'allow *' mds 'allow *'
sudo -u ceph mkdir /var/lib/ceph/mgr/ceph-server1
sudo -u ceph vi /var/lib/ceph/mgr/ceph-server1/keyring
sudo systemctl start ceph-mgr@server1
sudo ceph mgr module enable dashboard
sudo ceph dashboard create-self-signed-cert
sudo ceph dashboard ac-user-create admin -i passwd administrator
```

### Setting up more nodes.

First of we need to copy over the configuration, monitor map and all the keys over to our new 2 hosts.
```
sudo scp {user}@{server}:/etc/ceph/ceph.conf /etc/ceph/ceph.conf
sudo scp {user}@{server}:/etc/ceph/ceph.client.admin.keyring /etc/ceph/ceph.client.admin.keyring
sudo scp {user}@{server}:/var/lib/ceph/bootstrap-osd/ceph.keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
sudo scp {user}@{server}:/tmp/monmap /tmp/monmap
sudo scp {user}@{server}:/tmp/monkey /tmp/monkey
```

Next up we setup the monitor on node 2 exactly as we did with the first node.
```
sudo -u ceph mkdir /var/lib/ceph/mon/ceph-server2
sudo -u ceph ceph-mon --mkfs -i server2 --monmap /tmp/monmap --keyring /tmp/monkey
sudo systemctl start ceph-mon@server2
sudo ceph -s
sudo ceph mon enable-msgr2
```

Next up we setup the monitor on node 3 exactly as we did with the seconde node.
```
sudo -u ceph mkdir /var/lib/ceph/mon/ceph-server3
sudo -u ceph ceph-mon --mkfs -i server3 --monmap /tmp/monmap --keyring /tmp/monkey
sudo systemctl start ceph-mon@server3
sudo ceph -s
sudo ceph mon enable-msgr2
```

Then we setup the manager on node3 exactly as we did with the first node.
```
sudo ceph auth get-or-create mgr.server3 mon 'allow profile mgr' osd 'allow *' mds 'allow *'
sudo -u ceph mkdir /var/lib/ceph/mgr/ceph-server3
sudo -u ceph vi /var/lib/ceph/mgr/ceph-server3/keyring
sudo systemctl start ceph-mgr@server3
```

### Adding storage

When the cluster is up and running and all monitors are in qourum we could add storage services. This is easily done via the volume command. First we prepare a disk so it will be known by the cluster and have the keys and configuration copied to the management directory. Next up we activate the service so our storage nodes will be ready to use. This will be done for all the harddrives we want to add to our network.
```
sudo ceph-volume lvm prepare --data /dev/sd* 
sudo ceph-volume lvm activate {osd-number} {osd-uuid}
```

### Post configuration

Last but not least we want to ensure that all the services starts after a reboot. In debian we do that by enabling the services.
```
sudo systemctl enable ceph-mon@{node-id}
sudo systemctl enable ceph-mgr@{node-id}
sudo systemctl enable ceph-osd@{osd-number}
```

