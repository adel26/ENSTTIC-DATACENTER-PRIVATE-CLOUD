# ENSTTIC-DATACENTER-PRIVATE-CLOUD
### Introduction 
The study previously carried out on the third chapter allow us to properly deploy the
infrastructure. A preparation of the system is necessary before the installation of the
ceph and OpenStack solution which will be followed by a test of the various expected
functionalities of the infrastructure namely the creation and the management of the
projects, the instances, the network...

### Ceph installation 
Based on the architecture we decided to manually install Ceph on the three nodes that will be running Openstack services later, we will be making all three nodes Ceph monitors, each of them contain 3 OSDs each , 'server1' and 'server3' will run manager service as active-standby mechanism.
![alt text](https://github.com/adel26/ENSTTIC-DATACENTER-PRIVATE-CLOUD
/blob/main/cephdesign.png?raw=true)
### Choice of the Ceph version
For the version of Ceph to be deployed, we opted for an older and more stable version which is the Pacific version (16.2) released in 2021.
### Choice of the Linux distribution
The choice of deployment is focused on the Debian 11 (Bullseye) version, it is a stable version which does not pose any problem of compatibility .
### Network configuration of the hosts
After installing the operating system on each node of our architecture,  the ("server1", "Server2" and "server3") nodes we will proceed to the configuration of the network interfaces of the latter. All the nodes require access to the Internet for administrative purposes such as installing packages, security updates, DNS and NTP. The architecture we have adopted uses a private address space for the network that provides the connection between the services (the network management) and leaves the role of providing access to the Internet via the the other network interface.