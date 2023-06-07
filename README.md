# ENSTTIC-DATACENTER-PRIVATE-CLOUD
### Introduction 
The study previously carried out on the third chapter allow us to properly deploy the
infrastructure. A preparation of the system is necessary before the installation of the
ceph and OpenStack solution which will be followed by a test of the various expected
functionalities of the infrastructure namely the creation and the management of the
projects, the instances, the network...

## Ceph installation 
Based on the architecture we decided to manually install Ceph on the three nodes that will be running Openstack services later, we will be making all three nodes Ceph monitors, each of them contain 3 OSDs each , 'server1' and 'server3' will run manager service as active-standby mechanism.
![alt text](https://github.com/adel26/ENSTTIC-DATACENTER-PRIVATE-CLOUD/blob/main/cephdesign.png?raw=true)
### Choice of the Ceph version
For the version of Ceph to be deployed, we opted for an older and more stable version which is the Pacific version (16.2) released in 2021.
### Choice of the Linux distribution
The choice of deployment is focused on the Debian 11 (Bullseye) version, it is a stable version which does not pose any problem of compatibility .
### Network configuration of the hosts
After installing the operating system on each node of our architecture,  the ("server1", "Server2" and "server3") nodes we will proceed to the configuration of the network interfaces of the latter. All the nodes require access to the Internet for administrative purposes such as installing packages, security updates, DNS and NTP. The architecture we have adopted uses a private address space for the network that provides the connection between the services (the network management) and leaves the role of providing access to the Internet via the the other network interface.
## Openstack  installation 
Based on the hardware ressources and the proposed architecture we decided to do a multi-node manual installation of Openstack on our three node which allows for the total customization , so we will be installing:
1. Controller node 
 containing the services : `identity` , `compute (controller part)`,
`storage (controller part)`, `image`,` network (Self-service : Option 2)` and `dashboard`.
2. Storage node which will handle the storage service .
3. Compute node which will handle the compute service in our Openstack cluster.
The following figure will demonstrate the architecture:
![alt text](https://github.com/adel26/ENSTTIC-DATACENTER-PRIVATE-CLOUD/blob/main/openstackdesign.png?raw=true)
### Choice of the Openstack version
For the version of Openstack to be deployed, we opted for an older and more stable version
which is the Wallaby version (5.5) released in 2021 which we will deploy on Debian 11
Linux distribution along side with ceph
### Network configuration of the hosts
Once the operating system is installed on each node within our architecturea and ceph
is deployed , we will move forward with configuring the network interfaces of the nodes,
namely ”Controller”, ”Storage” and ”Compute” It is essential to grant Internet access to
all nodes for administrative tasks like package installation via a public ip from the subnet
192.168.10.0/24 Our chosen architecture employs a private address space from the subnet
10.0.0.0/24 for internal network communication among services (network management),
while assigning the responsibility of facilitating Internet access to the other network
interface
### Lab automation with Terraform
We decided to simulate a simple example for lab management using automation with
Terraform, the scenario is that the teacher want to do a lab exam, he will create some
instances and give access to the students for these instances so they can do their work
on. after the exam time expires the teacher will take away the access form the student
so that he will consult each instance later to evaluate each student.

Then when we need to close the lab we simply change the security group of the instance
(which allows the access via SSH, RDP and other protocols) to a prepared security group
which will deny any ingress or egress traﬀic so that any access to the instance is lost, for
that we created a security group called ”Lab-end”, deny every traﬀic rule, and we made a
script to change the security group of the created instance from ”Default” to ”Lab-end”.
Finally when the teacher want to consult the instances, he just has to launch the script
to put them back to the ”Default” security group to get the access back.
