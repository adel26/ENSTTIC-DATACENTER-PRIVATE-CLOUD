## Controller node:

### Installing prerequisites.

Having curl installed on any system is usually good. A very versatile tool to fetch data. 

```
sudo apt install -y curl
```

We use curl to fetch and install the repository key.

```
curl http://osbpo.debian.net/osbpo/dists/pubkey.gpg | sudo apt-key add -
```

Setting up the wallaby repositories. We chose the wallaby version

```
echo "deb http://osbpo.debian.net/osbpo bullseye-wallaby-backports main" | sudo tee -a /etc/apt/sources.list
echo "deb http://osbpo.debian.net/osbpo bullseye-wallaby-backports-nochange main" | sudo tee -a /etc/apt/sources.list
```

For this installation script where we will change the prompts to  `readline`  and  `high`.

```
sudo dpkg-reconfigure -plow debconf
```

After our changes to the repositories list we will update our registry data.

```
sudo apt update
```

### Installing MySQL.

Installing some tooling, MySQL is the database of choise where we will create a database per service we install. The Openstack client is used to communicate with the Openstack APIs from the command line. Most of Openstack is written in python so we need the python libraries for mysql to fetch data.

```
sudo apt install -y python3-openstackclient mariadb-server python3-pymysql
```

Let's create a database configuration file.

```
sudo vi /etc/mysql/mariadb.conf.d/99-openstack.cnf
```

Add the configuration below. We set the bind address and engine type. we prefer  `innodb`  as an engine for any database. 

```
[mysqld]
bind-address = {controller_node_host_address}

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
```

After the configuration is done we will restart and enable the database so it will start again when the machine reboots.

```
sudo systemctl restart mysqld
sudo systemctl enable mysqld
```

When installating  MySQL it's recommended to run the secure installation script. This will remove demo accounts and set passwords and change the connection method for root user.

```
sudo mysql_secure_installation
```

### Installing RabbitMQ.

Now let's install the RabbitMQ server, we will use this to queue up jobs that eventually needs doing. So when we want to create an instance the system will create messages that then will be carried out by some of the workers.

```
sudo apt install -y rabbitmq-server
```

We need to add an bind address to the environment file so we will open it.

```
sudo vi /etc/rabbitmq/rabbitmq-env.conf
```

The line for  `NODE_ADDRESS`  decides which IP to listen to. If we use 127.0.0.1 that is default we can't reach this service from the network.

```
NODE_IP_ADDRESS={controller_node_ip}
```

After updating the configuration we will restart and enable the service so it will start again when we reboot the computer.

```
sudo systemctl restart rabbitmq-server
sudo systemctl enable rabbitmq-server
```

Last but not least Openstack needs a user to with the right privileges to send messages. The lines below will create the  `openstack`  user with the password  `{rabbitmq_password}`  and set permissions to read and write for any entity in the system.

```
sudo rabbitmqctl add_user openstack {rabbitmq_password}
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
```

### Installing Memcache.

To store keystone tokens for logging in and using the services we will use thecontroller_node_ip memory database called memcache. First we install it and the python library to use it.

```
sudo apt install -y memcached python3-memcache
```

Let's open the configuration file to make it accessable on the rest of the network.

```
sudo vi /etc/memcached.conf
```

Setting the listening ip  `-l`  we make the service available on the local network.

```
-l {controller_node_ip}
```

We restart and enable the service to make the new configuration stick and so it will start on reboots.

```
sudo systemctl restart memcached
sudo systemctl enable memcached
```

### Installing the authentication registry - Keystone

Keystone is the registry we use to keep all the current permissions stored. So we will setup users, projects and roles within keystone and it will keep track on what user can reach and use which service. During installation we said no to any automatic configuration and will do that manually later.

```
sudo apt install -y keystone
```

Keystone will require a database. This will create the database and a user called  `keystone`  with the password  `{keystone_database_password}`.

```
sudo mysql -u root -p
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '{keystone_database_password}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '{keystone_database_password}';
```

Let's open the configuration file to do some tweeks.

```
sudo vi /etc/keystone/keystone.conf
```

First we check under the  `[database]`  section and add the connection to our MySQL database.

```
connection = mysql+pymysql://keystone:{keystone_database_password}@{controller_node_host_address}/keystone
```

Next we will check the  `[token]`  section and setup fernet as our token provider.

```
provider = fernet
```

As with all services we will restart and enable keystone so we have the right configuration available and that it will start at boot.

```
sudo systemctl restart keystone
sudo systemctl enable keystone
```

In order for keystone to work in wallaby we need to migrate the database to the right version. So we will run  `db_sync`  to add and update the data.

```
sudo su -s /bin/sh -c "keystone-manage db_sync" keystone
```

Fernet needs a special setup to make it ready for token generation.

```
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
```

More over we do some credential setup to add some standard rules and permissions.

```
sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
```

This step will bootstrap keystone with the admin user. This will be connected to  `RegionOne`  (our only region) and use the password  `{keystone_admin_password}`. We also will supply the keystone service URLs. Each service in keystone will have a public, internal and admin url. These could use separate networks for performance and security but in this example we use the same network.

```
sudo keystone-manage bootstrap --bootstrap-password {keystone_admin_password} \
  --bootstrap-admin-url http://{controller_node_host_address}:5000/v3/ \
  --bootstrap-internal-url http://{controller_node_host_address}:5000/v3/ \
  --bootstrap-public-url http://{controller_node_host_address}:5000/v3/ \
  --bootstrap-region-id RegionOne
```

### Setting up openstack command line tool and demo user

In order to use the command line tool for openstack we need to setup some environment variables. First of we need the username, password and project so we know where to log in. The auth URL to keystone and domain names are also required. Currently the identity API to use is version 3 and image API is version 2.

```
export OS_USERNAME=admin
export OS_PASSWORD={keystone_admin_password}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://{controller_node_host_address}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
```

First we have two commands that will setup features we will use later in this tutorial. First the service project where we will connect all our services under. We also setup the role user which is used for all users you create in the system.

```
openstack project create --domain default --description "Service Project" service
openstack role create user
```

To demostrate the user capability we will create a new demo project called demo.

```
openstack project create --domain default --description "Demo Project" demo
```

We will then create our first user called demo in the default domain and when prompted supply the password.

```
openstack user create --domain default --password-prompt demo
```

Last but not least we will give the demo user the role of user.

```
openstack role add --project demo --user demo user
```

### Install image registry - Glance

we will connect all our data sources to Ceph and to facilitate that we will install the python library for RBD and the common utilities for Ceph.

```
sudo apt install -y python3-rbd ceph-common
```

Now we will install the image registry called Glance. Glance is a way for you to store static images like a Redhat or Debian and then create volumes from these that you could instanciate in Openstack to run on our compute nodes. During the setup we will say no to any prompts for input as we will add them manually later in the guide.

```
sudo apt install -y glance
```

Glance requires a database to store the location, name and types of our images and other metadata. We will initialize the new database and create a user that has full access to the database named  `glance`  with the password  `{glance_database_password}`.

```
sudo mysql -u root -p
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '{glance_database_password}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '{glance_database_password}';
```

Next up we setup the keystone authentication. We create a new user called  `glance`  and give it the  `admin`  role within the  `service`  project.

```
openstack user create --domain default --password-prompt glance
openstack role add --project service --user glance admin
```

We also create a service identified by  `image`  and named  `glance`, then we create a public, internal and admin endpoint for this service in  `RegionOne`. Keystone will then keep track on if you access these endpoints if you are allowed to access.

```
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://{controller_node_host_address}:9292
openstack endpoint create --region RegionOne image internal http://{controller_node_host_address}:9292
openstack endpoint create --region RegionOne image admin http://{controller_node_host_address}:9292
```

Let's configure glance. The command below opens the configuration file.

```
sudo vi /etc/glance/glance-api.conf
```

In the  `[database]`  section we set up the correct connection parameter so glance can access the mysql database.

```
connection = mysql+pymysql://glance:{glance_database_password}@{controller_node_host_address}/glance
```

Next we set up the  `[keystone_authtoken]`  section and ensure that we have the right authentication parameters so the glance service can connect to the system via keystone.

```
www_authenticate_uri = http://{controller_node_host_address}:5000
auth_url = http://{controller_node_host_address}:5000
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = {glance_keystone_password}
```

The  `[paste_deploy]`  section should contain the right flavor of keystone to enable that functionallity.

```
flavor = keystone
```

Last we check the  `[glance_store]`  and add the configuration required to store our images in ceph. Instead of storing locally with  `lvm`  we will change it to store with  `rbd`  in the pool  `images`  using the configuration file for Ceph.

```
stores = rbd
default_store = rbd
rbd_store_pool = images
rbd_store_user = glance
rbd_store_ceph_conf = /etc/ceph/ceph.conf
rbd_store_chunk_size = 8
```

After the configuration file is setup we need to sync the database to migrate it to the current version of Openstack.

```
sudo su -s /bin/sh -c "glance-manage db_sync" glance
```

### Setting up Ceph

All commands in this section will run on one of the Ceph cluster nodes mentioned in the ceph-cluster.md file.

First of to test our glance installation in ceph we need to setup a couple of pools. The pools that we've so far been able to use is volumes, vms, backups and images. 

```
sudo ceph osd pool create volumes
sudo ceph osd pool create images
sudo ceph osd pool create backups
sudo ceph osd pool create vms
```

To use the pools as RBD pools we need to initialize them.

```
sudo rbd pool init volumes
sudo rbd pool init images
sudo rbd pool init backups
sudo rbd pool init vms
```

### Configure Ceph on our controller node

Let's open the Ceph configuration file on the controller node.

```
sudo vi /etc/ceph/ceph.conf
```

The  `[global]`  section of the configuration below is just copied directly from one of the ceph nodes. The  `[client]`  section is retrieved from the documentation. This will enable RBD caching, setup socket files and concurrent ops. The concurrent ops could be increased if required in larger installations.

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

[client]
rbd cache = true
rbd cache writethrough until flush = true
admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok
log file = /var/log/qemu/qemu-guest-$pid.log
rbd concurrent management ops = 20
```

Glance needs a key to access our cluster. To generate this key we run a command against our Ceph cluster to create a user and fetch the key.

```
ceph auth get-or-create client.glance mon 'profile rbd' osd 'profile rbd pool=images' mgr 'profile rbd pool=images'
```

Let's open the configuration file to write the key.

```
sudo vi /etc/ceph/ceph.client.glance.keyring
```

This is a key that could be saved to the keyring.

```
[client.glance]
        key = AQAGe9Bi9BeiNRAAMm3XfuGxJiqbS5530T75mg==
```

After we added the key we need to give the glance service access. This will give the user and group of  `glance`  access to the keyring.

```
sudo chown glance:glance /etc/ceph/ceph.client.glance.keyring
```

After the glance service is configured we will restart and enable it so it will start again when we reboot the machine.

```
sudo systemctl restart glance-api
sudo systemctl enable glance-api
```

### Test image repository

Let's test our repository. To do that we need an image and with the command below we will download CirrOS a really small distribution of Linux. Currently only 14Mb or so.

```
wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
```

Next up we use the openstack command line tool to create a new image called  `cirros`  using the  `qcow2`  format for  `bare`  containers and it will be public so any project can use it.

```
openstack image create "cirros" --file cirros-0.3.4-x86_64-disk.img --disk-format qcow2 --container-format bare --public
```

To ensure that the image was saved correctly we list all available images in the system.

```
openstack image list
```
The result will show some information about the uploaded image.

### Install dashboard - Horizon

The Horizon dashboard is a really great piece of the puzzle enabling administration of our users / customers into different projects with quotas. And also enables these users to start their own compute instances that can run independent of each other on seperate virtual LANs. The command below installs openstack dashboard with apache. Answer the questions correctly for our environment. If you can use SSL and replace the vhost with the dashboard.

```
sudo apt install -y openstack-dashboard-apache
```

Next up we will change some of the local settings to enable features of the dashboard.

```
sudo vi /etc/openstack-dashboard/local_settings.py
```

First we need to ensure that the dashboard is reachable on the controller domain, 127.0.0.1 requires you to be on the host in order to open dashboard. Then we also change the keystone URL to the one we specified during installation.

```
OPENSTACK_HOST = "{controller_node_host_address}"
OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST
```

The dashboard can allow specific hosts access for more security but we will make it available to anyone ('*').

```
ALLOWED_HOSTS = ['*']
```

Next up we look at the session engine. There are two options. Either use the normal cache one for memory cache or the cache_db (database). Next we setup the cache to use the memcache service.

```
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '{controller_node_host_address}:11211',
    }
}
```

We also need to supply the versions of different services. Currently we use version 3 for identity, version 2 for image and version 3 for volumes.

```
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
```

It's important to set the default domain and role for logging in. If we skip this step the login page will ask us for domain every login, and as we only have one domain it's unnessasary.

```
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"
```

We can also turn of some of the neutron features we don't use. Currentlywewill not have network quotas or routers so these features will be turned of.

```
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_ipv6': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': False,
}
```

Nextwewill look at the virtual host configuration. Maybe this is an unnessasary step but I've found guides mentioning this requirement.

```
sudo vi /etc/apache2/sites-available/openstack-dashboard.conf
```

This line needs to be added by other WSGI configurations to set the group of the application.

```
WSGIApplicationGroup %{GLOBAL}
```

After these configuration changes we will restart apache.

```
sudo service apache2 reload
```

### Install dashboard - Skyline

The skyline dashboard is a new dashboard with more flexebility and features.
Before we install and configure Skyline service, we must create a database.


```
mysql
```

Create the skyline database.

```
MariaDB [(none)]> CREATE DATABASE skyline DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
```

Grant proper access to the skyline database.

```
MariaDB [(none)]> GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'localhost' IDENTIFIED BY 'SKYLINE_DBPASS';
MariaDB [(none)]> GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'%' IDENTIFIED BY 'SKYLINE_DBPASS';
```

create the service credentials.

```
openstack user create --domain default --password-prompt skyline
```

Add the admin role to the skyline user

```
openstack role add --project service --user skyline admin
```

We will install Skyline service from docker image.
Pull Skyline service image from Docker Hub.

```
sudo docker pull 99cloud/skyline:latest
```

Ensure that some folders of skyline have been created

```
sudo mkdir -p /etc/skyline /var/log/skyline /var/lib/skyline /var/log/nginx
```

Configure /etc/skyline/skyline.yaml file.

```
default:
  database_url: mysql://skyline:SKYLINE_DBPASS@DB_SERVER:3306/skyline
  debug: true
  log_dir: /var/log
openstack:
  keystone_url: http://KEYSTONE_SERVER:5000/v3/
  system_user_password: SKYLINE_SERVICE_PASSWORD
```

Finalize installation by Run bootstrap server

```
$ sudo docker run -d --name skyline_bootstrap \
  -e KOLLA_BOOTSTRAP="" \
  -v /etc/skyline/skyline.yaml:/etc/skyline/skyline.yaml \
  -v /var/log:/var/log \
  --net=host 99cloud/skyline:latest
```

Cleanup bootstrap server

```
sudo docker rm -f skyline_bootstrap
```

Run skyline

```
sudo docker run -d --name skyline --restart=always \
  -v /etc/skyline/skyline.yaml:/etc/skyline/skyline.yaml \
  -v /var/log:/var/log \
  --net=host 99cloud/skyline:latest
```

### Cinder install

Cinder is the volume service, handling creation, deletion, snapshots and backups. Volumes are the main data sources that you run in our cluster. So each instance will run a volume that we later can backup for data security. It's setup in two different parts that could be installed on the same machine but also seperately. we will seperate the controller part and the storage part into different nodes. One good reason is if you over provision one of our storage nodes you might not have any control to turn that server of. But by separate them you always have the controller available to initiate commands.

First we need a database to store all the metadata about our volumes. The commands below will login to the mysql server and create a database called  `cinder`  with a user called  `cinder`  that has full rights.

```
sudo mysql -u root -p
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '{cinder_database_password}';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '{cinder_database_password}';
```

Cinder also needs to register with keystone. We will create a  `cinder`  user with a password and then add the admin role to the service project for that user. Then we will create a service called  `volumev3`  as we currently only support version 3 of the volume API. Previous versions have had both version 2 and 3 running at the same time. And lastly we create endpoints for the admin, interal and public traffic in  `RegionOne`.

```
openstack user create --domain default --password-prompt cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev3 public http://{controller_node_host_address}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://{controller_node_host_address}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://{controller_node_host_address}:8776/v3/%\(project_id\)s
```

Installing required software packages.  `cinder-api`  will handle all requests , the scheduler will schedule jobs in RabbitMQ.
the other cinder services will be installed seperatly on the storage node.  
```
sudo apt install -y cinder-api cinder-scheduler 
```

Let's open the configuration file for some changes.

```
sudo vi /etc/cinder/cinder.conf
```

First we will check the  `[database]`  section and add the connection to the MySQL database.

```
connection = mysql+pymysql://cinder:{cinder_database_password}@{controller_node_host_address}/cinder
```

We need to check these parameters in the  `[DEFAULT]`  section. Transport url should be the connection to our RabbitMQ server.  `auth_strategy`  needs to be keystone and verify  `my_ip`  has the ip of our server. Lastly the most important parameter, check  `enabled_backends`  in this case we only will support  `ceph`  so change this from  `lvm`.

```
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}
auth_strategy = keystone
my_ip = {controller_node_ip}
enabled_backends = ceph
```

As with all the services we need to go though the  `[keystone_authtoken]`  section and ensure that the cinder service can connect to the right domain, with the right user password and project. We need to add the  `memcached_servers`  to save the tokens.

```
www_authenticate_uri = http://{controller_node_host_address}:5000
auth_url = http://{controller_node_host_address}:5000
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = {cinder_keystone_password}
```

Cinder database needs syncing to catch up with the current version. It will initialize a new database and then migrate it all the way to our current version.

```
sudo su -s /bin/sh -c "cinder-manage db sync" cinder
```

#### Install placement service

Placement service stores statistics about our instances and communicates with the schedulers to figure out where to put instances on creation. 

First we need a database to store all the statistical data about our instances. The commands below will login to the mysql server and create a database called  `placement`  with a user called  `placement`  that has full rights using the password  `{placement_database_password}`.

```
sudo mysql -u root -p
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '{placement_database_password}';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '{placement_database_password}';
```

Next up we create a placement user in keystone and give it the admin role in the service project. Then create a service called placement and set the normal public, internal and admin endpoints in  `RegionOne`  so keystone can keep track of who can access the placement service.

```
openstack user create --domain default --password-prompt placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://{controller_node_host_address}:8778
openstack endpoint create --region RegionOne placement internal http://{controller_node_host_address}:8778
openstack endpoint create --region RegionOne placement admin http://{controller_node_host_address}:8778
```

Installing the  `placement-api`  package will enable the service.

```
sudo apt install -y placement-api
```

So we open the configuration file to configure the service.

```
sudo vi /etc/placement/placement.conf
```

In the  `[placement_database]`  segment we need to verify that the database connection is set to the placement database.

```
connection = mysql+pymysql://placement:{placement_database_password}@{controller_node_host_address}/placement
```

Next we check the  `[api]`  section for the  `auth_strategy`  parameter and set it to keystone.

```
auth_strategy = keystone
```

As with all the services we will set  `[keystone_authtoken]`  section to the keystone service connection information with passwords, domain, project, username and also set the token servers of memcached.

```
auth_url = http://{controller_node_host_address}:5000/v3
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = {placement_keystone_password}
```

Database needs to be synced so we have the latest data as of this release.

```
sudo su -s /bin/sh -c "placement-manage db sync" placement
```

On a side notewefound an issue we need to address so let's log into the database again.

```
sudo mysql -u root -p
```

Using the placement database we will insert a new trait called  `COMPUTE_SOCKET_PCI_NUMA_AFFINITY`. When we didn't add this one we couldn't start the instances on the compute nodes because it reported back with a value for this parameter and the placement server didn't know what to do with it and did not accept the compute node into the cluster.

```
use placement;
insert into traits(name) values ('COMPUTE_SOCKET_PCI_NUMA_AFFINITY');
```

After all the configuration changes we will restart and enable the services to ensure that they will start if reboot the system.

```
sudo systemctl restart placement-api.service
sudo systemctl enable placement-api.service
sudo systemctl restart apache2
```

## Install controller - Nova

Nova is the service that handles the compute servers / instances. It's setup in two different parts that could be installed on the same machine but also seperately. we will seperate the controller part and the compute part into different nodes. One good reason is if you over provision one of our compute nodes you might not have any control to turn that server of. But by separate them you always have the controller available to initiate commands.

Let's start with connecting to the database.

```
sudo mysql -u root -p
```

For nova we need multiple databases. One for the API metadata, one for the general compute and one for the first cell information. The script below creates the databases and creates a user  `nova`  that have full access to all three databases with the password {nova_database_password}.

```
create database nova_api;
create database nova;
create database nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '{nova_database_password}';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '{nova_database_password}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '{nova_database_password}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '{nova_database_password}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '{nova_database_password}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '{nova_database_password}';
```

Next up we do the normal keystone setup creating the nova user, giving it the admin role in the service project. Then we create the compute service and add public, internal and admin endpoints in RegionOne.

```
openstack user create --domain default --password-prompt nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://{controller_node_host_address}:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://{controller_node_host_address}:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://{controller_node_host_address}:8774/v2.1
```

Now we install the services.  `nova-api`  will take the request from the clients or other services and pushes them for execution.  `nova-conductor`  offloads the need of a database connection from the compute units, so  `nova-compute`  could ask the conductor for information instead of the database directly.  `nova-consoleproxy`  adds multiple services that gives you a prompt into the system either via VNC or the web UI. Lastly the  `nova-scheduler`  decides where to put instances depending on the statistics gathered in the placement service.

```
sudo apt install -y nova-api nova-conductor nova-consoleproxy nova-scheduler
```

Let's configure the service by editing nova.conf.

```
sudo vi /etc/nova/nova.conf
```

In the  `[DEFAULT]`  section we need to ensure the RabbitMQ connection,  `my_ip`  should be set to the local IP on the external interface. We also need to add two flags for  `vnc_enabled`  and  `novnc_enabled`  so we disable these services as they can intefer with the spice service.

```
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}:5672
my_ip = {controller_node_ip}
vnc_enabled = False
novnc_enabled = False
```

Next check the  `[api_database]`  so we have a working connection to the  `nova_api`  database.

```
connection = mysql+pymysql://nova:{nova_database_password}@{controller_node_host_address}/nova_api
```

We need to check the  `[database]`  section for the normal  `nova`  database connection.

```
connection = mysql+pymysql://nova:{nova_database_password}@{controller_node_host_address}/nova
```

Check our  `[api]`  section for the  `auth_strategy`. It might be deprecated as Openstack is going to using keystone as the only viable authentication service but if not it needs to say  `keystone`.

```
auth_strategy = keystone
```

Again we need to disable vnc in the  `[vnc]`  section.

```
enabled = False
```

Now let's configure spice in the  `[spice]`  section. Enable it and add host, port and keymap information. Sadly I've not gotten the keymap information to work. Perhaps it's because the image doesn't support it but however it's good to specify.

```
enabled = True
html5proxy_host = 0.0.0.0
html5proxy_port = 6082
keymap = sv-se
```

As with all the services we will update the  `[keystone_authtoken]`  section so we have the right auth_urls, domain, project, username and password as well as the token memcached server address.

```
www_authenticate_uri = http://{controller_node_host_address}:5000/
auth_url = http://{controller_node_host_address}:5000/
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = {nova_keystone_password}
service_token_roles_required=true
```

Check the  `[glance]`  section for  `api_servers`. This is probably deprecated as it's can be gathered from the keystone service but might not be in our version.

```
api_servers = http://{controller_node_host_address}:9292
```

Also look in  `[cinder]`  section to ensure that the  `os_region_name`  is set to RegionOne.

```
os_region_name = RegionOne
```

the  `[placement]`  server needs a separate configration for keystone with the  `region_name`  supplied. Might be because placement was a part of nova earlier.

```
auth_url = http://{controller_node_host_address}:5000/v3
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = {placement_keystone_password}
region_name = RegionOne
```

Now we need to sync up the databases, both the general  `nova`  database and the  `nova_api`  will be migrated to current version.

```
sudo su -s /bin/sh -c "nova-manage db sync" nova
sudo su -s /bin/sh -c "nova-manage api_db sync" nova
```

Then we will map up the  `nova_cell0`  service and create a new  `cell1`. When that is done you can run the last command below to list all the cells and verify that the correct database and RabbitMQ information is saved.

```
sudo su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
```

After all the configuration changes we will restart and enable the services to ensure that they will start when we reboot the system.

```
sudo systemctl restart nova-api
sudo systemctl restart nova-api-metadata
sudo systemctl restart nova-scheduler
sudo systemctl restart nova-conductor
sudo systemctl restart nova-spicehtml5proxy
sudo systemctl stop nova-novncproxy
sudo systemctl enable nova-api
sudo systemctl enable nova-api-metadata
sudo systemctl enable nova-scheduler
sudo systemctl enable nova-conductor
sudo systemctl enable nova-spicehtml5proxy
sudo systemctl disable nova-novncproxy
```

## Install neutron

Neutron will add the networking part of Openstack. This will enable for our users to create their own local networks as virtual networks that are separated by project. Then you could connect these networks via routers to the external network and expose floating ips for services that needs to be reached outside of the network.

To start the install process we need to setup a database. Below we will connect to mysql and create the  `neutron`  database. Create a  `neutron`  user that have full access to the database with the password  `{neutron_database_password}`.

```
sudo mysql -u root -p
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '{neutron_database_password}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '{neutron_database_password}';
```

The commands below will create a  `neutron`  user where you need to supply the password for  `{neutron_keystone_password}`. Then we add the admin role to the service project for the  `neutron`  user. Next we create the network service and add public, internal and admin endpoints in the region RegionOne.

```
openstack user create --domain default --password-prompt neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://{controller_node_host_address}:9696
openstack endpoint create --region RegionOne network internal http://{controller_node_host_address}:9696
openstack endpoint create --region RegionOne network admin http://{controller_node_host_address}:9696
```

Now we will install the services.  `neutron-server`  is the API part of this service. The  plugin  `ml2`  is handling all of the network interfaces. Two common ones are  `linuxbridge`  and  `openvswitch`. Linuxbridge is the old one but more reliable and can handle more traffic, it has less features than the newer OpenvSwitch. Linuxbridge uses the built in linux iptables and other facitilites to route traffic. OpenvSwitch has an extra abstraction layer with more features. We will use Linuxbridge in this guide. The l3 agent will handle the IP traffic layer. DHCP agent is responsible of assigning new addresses to servers. Last but not least we have the metadata service that will add information about servers and have an integration with nova.

```
sudo apt install -y neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
```

Time to configure the neutron service so let's open the configuration file.

```
sudo vi /etc/neutron/neutron.conf
```

In the  `[DEFAULT]`  section we need to ensure that we use the ml2 core plugin. We need to check the service plugins and perhaps remove a couple, only router will be used here. The  `transport_url`  needs to have the right connection information to reach the RabbitMQ service. The  `auth_strategy`  is always keystone and we want neutron to notify nova when ports status and data changes.

```
core_plugin = ml2
service_plugins = router
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
```

We check  `[database]`  section so we have the right connection information for the neutron database.

```
connection = mysql+pymysql://neutron:{neutron_database_password}@{controller_node_host_address}/neutron
```

As with any service we need to setup the  `[keystone_authtoken]`  section with the right keystone parameters for auth url, token cache service, domain name, project, username and password for the neutron service.

```
www_authenticate_uri = http://{controller_node_host_address}:5000
auth_url = http://{controller_node_host_address}:5000
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = {neutron_keystone_password}
```

Neutron talks to nova so in the  `[nova]`  section we need to setup the correct keystone authentication information for nova. Including auth url, domain, region, project, username and password for nova.

```
auth_url = http://{controller_node_host_address}:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = {nova_keystone_password}
```

Next we need to configure the main ml2 plugin.

```
sudo vi /etc/neutron/plugins/ml2/ml2_conf.ini
```

In the  `[ml2]`  section we need to ensure that we support all 3 type drivers. The tenant network will use  `vxlan`  if supported. If we you don't have that available you can set  `vlan`  here. Mechanism drivers needs to change to  `linuxbridge`  from  `openvswitch`  and lastly the extension drivers only need  `port_security`. QOS (Quality of Service) is not required and adds extra complexity.

```
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security
```

We need to set the  `flat_networks`  parameter in the  `[ml2_type_flat]`  section to  `provider`.

```
flat_networks = provider
```

Ensure that the  `[ml2_type_vxlan]`  sections  `vni_ranges`  is 1:1000. This will give a good range of available identifiers for the vxlan tenant networks.

```
vni_ranges = 1:1000
```

Lastly in the  `[securitygroup]`  section we need to ensure that  `enable_ipset`  is enabled.

```
enable_ipset = true
```

Next we will configure the linuxbridge agent.

```
sudo vi /etc/neutron/plugins/ml2/linuxbridge_agent.ini
```

In the  `[linux_bridge]`  section we will set the provider to our  `{local_network_interface}`. If we have multiple ones use the one used for internal traffic.

```
physical_interface_mappings = provider:{local_network_interface}
```

Configuring  `[vxlan]`  section includes enabling, setting the local ip to the current host IP and lastly enabling l2_population.

```
enable_vxlan = true
local_ip = {controller_node_ip}
l2_population = true
```

Lastly in the  `[securitygroup]`  section we will enable the iptables firewall driver, and enable security groups.

```
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = true
```

To ensure the functionallity iptables firewall you need to enable the br_netfilter kernel driver and check the net bridge system control values so they are both set to 1.

```
sudo modprobe br_netfilter
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.bridge.bridge-nf-call-ip6tables
```

Next up we need to configure the l3 agent.

```
sudo vi /etc/neutron/l3_agent.ini
```

In the  `[DEFAULT]`  section change to use the linuxbridge interface driver.

```
interface_driver = linuxbridge
```

Configuring the dhcp agent.

```
sudo vi /etc/neutron/dhcp_agent.ini
```

In the  `[DEFAULT]`  section change to use the linuxbridge interface driver. Then we will set the dhcp driver to Dnsmasq and lastly enable isolated metadata.

```
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
```

Last neutron service to configure is the metadata agent.

```
sudo vi /etc/neutron/metadata_agent.ini
```

We need to check the  `[DEFAULT]`  section and supply the same nova metadata host and shared secret as we use for nova.

```
nova_metadata_host = {controller_node_host_address}
metadata_proxy_shared_secret = {neutron_secret}
```

In order to set the same secret we will configure nova.

```
sudo vi /etc/nova/nova.conf
```

In the  `[neutron]`  section we will set the keystone authentication information as usual for the neutron service and also add the shared secret and enable metadata proxy. This ensures that neutron and nova can exchange metadata.

```
auth_url = http://{controller_node_host_address}:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = {neutron_keystone_password}
service_metadata_proxy = true
metadata_proxy_shared_secret = {neutron_secret}
```

To migrate the database to have the most recent setup as of this openstack version we run the neutron-db-manage command supplying the configuration for neutron and the ml2 plugin. The  `upgrade head`  will do the migration.

```
sudo su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
```

After all the configuration changes we will restart and enable the services to ensure that they will start when we reboot the system.

```
sudo systemctl restart neutron-api    
sudo systemctl restart neutron-l3-agent
sudo systemctl restart neutron-metadata-agent
sudo systemctl restart neutron-dhcp-agent
sudo systemctl restart neutron-linuxbridge-agent
sudo systemctl restart neutron-rpc-server
sudo systemctl enable neutron-api    
sudo systemctl enable neutron-l3-agent
sudo systemctl enable neutron-metadata-agent
sudo systemctl enable neutron-dhcp-agent
sudo systemctl enable neutron-linuxbridge-agent
sudo systemctl enable neutron-rpc-server
```

We will also restart the nova services as we have changed configuration for these services as well.

```
sudo systemctl restart nova-api
sudo systemctl restart nova-scheduler
sudo systemctl restart nova-conductor
sudo systemctl restart nova-spicehtml5proxy
```


## Storage node - cinder-volume - cinder-backup

Installing required software packages,`cinder-volume`  and  `cinder-backup`  is the workers fetching jobs and creating backups, volumes or snapshots.
```
sudo apt install -y cinder-volume cinder-backup
```

Let's open the configuration file for some changes.

```
sudo vi /etc/cinder/cinder.conf
```

Next up we check  `[DEFAULT]`  and add the  `CephBackupDriver`  and all the required configuration to write backups. Things to mention is the chunk size that is a bit large for performance but we will discard excess bytes when we restore the backup. Other than that we will use the  `cinder-backup`  user that we will add a Ceph key for soon.

```
backup_driver = cinder.backup.drivers.ceph.CephBackupDriver
backup_ceph_conf = /etc/ceph/ceph.conf
backup_ceph_user = cinder-backup
backup_ceph_chunk_size = 134217728
backup_ceph_pool = backups
backup_ceph_stripe_unit = 0
backup_ceph_stripe_count = 0
restore_discard_excess_bytes = true
```

We need to check these parameters in the  `[DEFAULT]`  section. Transport url should be the connection to our RabbitMQ server.  `auth_strategy`  needs to be keystone and verify  `my_ip`  has the ip of our server. Lastly the most important parameter, check  `enabled_backends`  in this case we only will support  `ceph`  so change this from  `lvm`.

```
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}
auth_strategy = keystone
my_ip = {controller_node_ip}
enabled_backends = ceph
```

As with all the services we need to go though the  `[keystone_authtoken]`  section and ensure that the cinder service can connect to the right domain, with the right user password and project. We need to add the  `memcached_servers`  to save the tokens.

```
www_authenticate_uri = http://{controller_node_host_address}:5000
auth_url = http://{controller_node_host_address}:5000
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = {cinder_keystone_password}
```

Lastly we add a new  `[ceph]`  section at the end of the file defining the  `RBDDriver`, backends and pool. A thing to notice in the configuration below is the  `rbd_secret_uuid`  that we will reuse in the nova compute agent to handle our volumes and instances. The UUID is something that needs to be unique but could be freely generated by you.

```
[ceph]
volume_driver = cinder.volume.drivers.rbd.RBDDriver
volume_backend_name = ceph
rbd_pool = volumes
rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_flatten_volume_from_snapshot = false
rbd_max_clone_depth = 5
rbd_store_chunk_size = 4
rados_connect_timeout = -1
rbd_user = cinder
rbd_secret_uuid = {generated_secret_rbd_uuid}
```

Cinder database needs syncing to catch up with the current version. It will initialize a new database and then migrate it all the way to our current version.

```
sudo su -s /bin/sh -c "cinder-manage db sync" cinder
```

You could generate the keys for below keyring files by running the commands below on one of the Ceph cluster nodes.

```
ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes, profile rbd pool=vms'
ceph auth get-or-create client.cinder-backup mon 'profile rbd' osd 'profile rbd pool=backups' mgr 'profile rbd pool=backups'
```

We will add a  `client.cinder`  keyring for Ceph.

```
sudo vi /etc/ceph/ceph.client.cinder.keyring
```

This is an example of a  `client.cinder`  key.

```
[client.cinder]
        key = AQA7e9BiaFvjJxAAr2ANeBVwi1ETGQKuChCxJg==
```

We will also give the  `cinder`  user and  `cinder`  group access to the keyring.

```
sudo chown cinder:cinder /etc/ceph/ceph.client.cinder.keyring
```

We will add a  `client.cinder-backup`  keyring for Ceph.

```
sudo vi /etc/ceph/ceph.client.cinder-backup.keyring
```

This is an example of a  `client.cinder-backup`  key.

```
[client.cinder-backup]
        key = AQBNe9BirwhbExAAE7rM37W830IcBehv8Z8yTw==
```

We will also give the  `cinder`  user and  `cinder`  group access to the keyring.

```
sudo chown cinder:cinder /etc/ceph/ceph.client.cinder-backup.keyring
```

After all the configuration changes we will restart and enable the services to ensure that they will start if reboot the system.

```
sudo systemctl restart cinder-backup
sudo systemctl restart cinder-volume
sudo systemctl restart apache2
sudo systemctl enable cinder-backup
sudo systemctl enable cinder-volume
sudo systemctl enable apache2
```

## Compute node - nova-compute and neutron-linuxbridge

We will install the compute node which could be a separate machine or several that will handle all the instances we want to run in our cluster. Many of the setup steps are similar to the setup of our control node but this segment is shorter as it will have fewer services running.

Having curl installed on any system is usually good. A very versatile tool to fetch data. 

```
sudo apt install -y curl
```

We use curl to fetch and install the repository key.

```
curl http://osbpo.debian.net/osbpo/dists/pubkey.gpg | sudo apt-key add -
```

Setting up the wallaby repositories. 

```
echo "deb http://osbpo.debian.net/osbpo bullseye-wallaby-backports main" | sudo tee -a /etc/apt/sources.list
echo "deb http://osbpo.debian.net/osbpo bullseye-wallaby-backports-nochange main" | sudo tee -a /etc/apt/sources.list
```

For this installation  during installation we will change the prompts to  `readline`  and  `high`.

```
sudo dpkg-reconfigure -plow debconf
```

After our changes to the repositories list we will update our registry data.

```
sudo apt update
```

Let's start of by installing the software.  `nova-compute`  is the worker that starts and handles instances / servers. Currently we use qemu to virtualize our instances so we install the  `nova-compute-qemu`  package.

```
sudo apt install -y nova-compute nova-compute-qemu
```

This is how to connect our data resources to Ceph so we need to install the common tools.

```
sudo apt install -y ceph-common
```

Next we will configure Ceph.

```
sudo vi /etc/ceph/ceph.conf
```

The  `[global]`  section of the configuration below is just copied directly from one of the Ceph nodes. The  `[client]`  section is retrieved from the documentation. This will enable RBD caching, setup socket files and concurrent ops. These could be increased if required in larger installations.

```
[global]
fsid = c282b4a1-83e6-4714-874e-576047e94823
mon initial members = single
mon host = 192.168.6.60
public network = 192.168.6.0/24
cluster network = 192.168.6.0/24
auth cluster required = cephx
auth service required = cephx
auth client required = cephx

[client]
rbd cache = true
rbd cache writethrough until flush = true
admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok
log file = /var/log/qemu/qemu-guest-$pid.log
rbd concurrent management ops = 20
```

We will add a  `client.cinder`  keyring for Ceph that we generated earlier in  cinder.

```
sudo vi /etc/ceph/ceph.client.cinder.keyring
```

This is an example of a  `client.cinder`  key.

```
[client.cinder]
        key = AQA7e9BiaFvjJxAAr2ANeBVwi1ETGQKuChCxJg==
```

We also need to create a key file and add only the base64 encoded key above.

```
vi client.cinder.key
```

Here is an example of the key material.

```
AQA7e9BiaFvjJxAAr2ANeBVwi1ETGQKuChCxJg==
```

We also need to create an secret xml file supplying the  `{generated_secret_rbd_uuid}`  we prepared earlier in the cinder chapter / video.

```
cat > secret.xml <<EOF
<secret ephemeral='no' private='no'>
  <uuid>{generated_secret_rbd_uuid}</uuid>
  <usage type='ceph'>
    <name>client.cinder secret</name>
  </usage>
</secret>
EOF
```

We will define the secret in the virtual environment.

```
sudo virsh secret-define --file secret.xml
```

Then we will set the key together with the UUID so we can call upon this ID when we need to reach Ceph from the compute node.

```
sudo virsh secret-set-value --secret {generated_secret_rbd_uuid} --base64 $(cat client.cinder.key) && rm client.cinder.key secret.xml
```

To enabling running instances we will create a guest directory and log directory for qemu. Then we change user and group for it to the  `libvirt-qemu`  user and  `libvirt`  group.

```
sudo mkdir -p /var/run/ceph/guests/ /var/log/qemu/
sudo chown libvirt-qemu:libvirt /var/run/ceph/guests /var/log/qemu/
```

Now let's verify the configuration of nova compute.

```
sudo vi /etc/nova/nova-compute.conf
```

In the  `[DEFAULT]`  section we need to check that we use the correct virtualization engine. In my caseweuse  `qemu`.

```
virt_type = qemu
```

Moreover we need to configure nova.

```
sudo vi /etc/nova/nova.conf
```

Verify the values in  `[DEFAULT]`  so that we have the right transport url for RabbitMQ. The  `my_ip`  should have the current hosts ip. Lastly we add the  `vnc_enabled`  config option to turn it of as it can intefer with the web UI.

```
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}
my_ip = {compute_node_ip}
vnc_enabled = false
```

Move to the  `[api]`  and check the  `auth_strategy`  value. Probably deprectated as keystone should be the default from now and on.

```
auth_strategy = keystone
```

The web UI is configured in  `[spice]`  section. Here we will set the base_url to the controller node address, we need to enable it and set our listening port and use the  `my_ip`  value as the proxy client address.weset the keymap here butwethink it's depending on what's available in the image you instanciate.

```
enabled = True
html5proxy_base_url = http://{controller_node_host_address}:6082/spice_auto.html
keymap = sv-se
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
```

As usual in the  `[keystone_authtoken]`  section we will add the configuration for nova keystone authentication. Here we will set the authentication url, type, domain, project, username and password.

```
www_authenticate_uri = http://{controller_node_host_address}:5000/
auth_url = http://{controller_node_host_address}:5000/
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = {nova_keystone_password}
```

In the  `[libvirt]`  section we will set the engine we will use to  `qemu`  and the  `rbd_user`  and  `rbd_secret_uuid`  so we can use volumes from cinder.

```
virt_type = qemu
rbd_user = cinder
rbd_secret_uuid = {generated_secret_rbd_uuid}
```

More places to disable vnc in  `[vnc]`  we will set enabled to false.

```
enabled = False
```

we Check the  `[glance]`  section for the  `api_servers`  parameter. Could be deprecated as this information is usually fetched from keystone from now on.

```
api_servers = http://{controller_node_host_address}:9292
```

The  `[placement]`  section contains the keystone authentication information for placement with the added  `region_name`  of our region  `RegionOne`.

```
auth_url = http://{controller_node_host_address}:5000/v3
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = placement
password = {placement_keystone_password}
region_name = RegionOne
```

Another place to verify the region name is under the  `[cinder]`  section.

```
os_region_name = RegionOne
```

Next up we will install the linuxbridge agent to handle networking on the compute node.

```
sudo apt install -y neutron-linuxbridge-agent
```

The neutron configuration file needs a couple of changes.

```
sudo vi /etc/neutron/neutron.conf
```

First check  `[DEFAULT]`  section so we have the right transport url with our RabbitMQ url. We also ensure that the  `auth_strategy`  is set to  `keystone`.

```
transport_url = rabbit://openstack:{rabbitmq_password}@{controller_node_host_address}
auth_strategy = keystone
```

Then we will configure keystone in  `[keystone_authtoken]`  section. We will add the configuration for neutron keystone authentication. Here we will set the authentication url, type, domain, project, username and password.

```
www_authenticate_uri = http://{controller_node_host_address}:5000
auth_url = http://{controller_node_host_address}:5000
memcached_servers = {controller_node_host_address}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = {neutron_keystone_password}
```

Next we will check the nova configuration.

```
sudo vi /etc/nova/nova.conf 
```

Then we will configure keystone in  `[neutron]`  section. We will add the configuration for neutron keystone authentication. Here we will set the authentication url, type, domain, project, username and password. We will also add the region name.

```
auth_url = http://{controller_node_host_address}:5000
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = {neutron_keystone_password}
region_name = RegionOne
```

Next we will configure the linuxbridge agent.

```
sudo vi /etc/neutron/plugins/ml2/linuxbridge_agent.ini
```

In the  `[linux_bridge]`  section we will set the provider to our  `{local_network_interface}`. If we have multiple ones use the one used for internal traffic.

```
physical_interface_mappings = provider:{local_network_interface}
```

Configuring  `[vxlan]`  section includes enabling, setting the local ip to the current host IP and lastly enabling l2_population.

```
enable_vxlan = True
local_ip = {compute_node_ip}
l2_population = True
```

Lastly in the  `[securitygroup]`  section we will enable the iptables firewall driver, and enable security groups.

```
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = True
```

To ensure the functionallity iptables firewall you need to enable the br_netfilter kernel driver and check the net bridge system control values so they are both set to 1.

```
sudo modprobe br_netfilter
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.bridge.bridge-nf-call-ip6tables
```

Next up we need to configure the l3 agent.

```
sudo vi /etc/neutron/l3_agent.ini
```

In the  `[DEFAULT]`  section we change to use the linuxbridge interface driver.

```
interface_driver = linuxbridge
```

Configuring the dhcp agent.

```
sudo vi /etc/neutron/dhcp_agent.ini
```

In the  `[DEFAULT]`  section we change to use the linuxbridge interface driver. Then we will set the dhcp driver to Dnsmasq and lastly enable isolated metadata.

```
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
```

After all the configuration changes we will restart and enable the services to ensure that they will start when we reboot the system.

```
sudo systemctl restart nova-compute
sudo systemctl restart neutron-linuxbridge-agent
sudo systemctl enable nova-compute
sudo systemctl enable neutron-linuxbridge-agent
```

**The following commands should be runned on the controller node**

Let's check so the API's can reach our compute node. The available nova compute nodes should be listed.

```
openstack compute service list --service nova-compute
```

To add the compute node to our cell we need to  `discover_hosts`. There is an automatic process that checks for new hosts regularly but this will make that discovery instant and we also see if there is any issue with the integration.

```
sudo su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
```

#### Testing our cluster

We are almost to an end, we have a running cluster with everything required to run workloads in openstack. Let's do some testing to ensure that all features are working correctly.

In order to use the command line tool for openstack we need to setup some environment variables. First of we need the username, password and project so we know where to log in. The auth URL to keystone and domain names are also required. Currently the identity API to use is version 3 and image API is version 2.

```
export OS_USERNAME=admin
export OS_PASSWORD={keystone_admin_password}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://{controller_node_host_address}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
```

First we will check our flavors, that will determine what size of compute instances we will launch. To list them we can run the command below.

```
openstack flavor list
```

Next we will create a small flavor that is enough for our  `cirros`  image. Using one CPU, 512MB of ram and 1GB of disk.

```
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny
```

Creating a new server / instance we can just run the create command below and use the  `cirros`  image we created in the  `glance`  chapter / video.

```
openstack server create --flavor m1.tiny --image cirros my-instance
```

Another way to start a server is to do it directly from a volume. Below we will create a volume named  `volume1`  from the  `cirros`  image with the size of 2GB in our availablility zone called  `nova`. This volume should end up in our  `volumes`  pool in Ceph. Then we can instanciate that volume with a  `m1.tiny`  size.

```
openstack volume create --image cirros --size 2 --availability-zone nova volume1
openstack server create --flavor m1.tiny --volume volume1 my-instance
```

Lastly we want to verify the backup functionallity. First we will create a backup of  `volume1`, This backup should show up in our  `backups`  pool in Ceph.

```
openstack volume backup create volume1
```

Last check is to verify the creation of our backup. We can list all the backups with the command below and then we can use the second command to show information about the backup with  `{backup_id}`

```
openstack volume backup list
openstack volume backup show {backup_id}
```
