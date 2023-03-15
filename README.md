# postgresql-cluster
Build the postgresql cluster which including primary and standby server. 

Prerequisites:

- Tow VM or HOST
- Linux OS
- Working Inner Network

Primary Server Operation:

> bash build.sh -i 10.11.12.0 -m 24 -t master -M 10.11.12.101 -v 9.5

Run the above command in the one host to build the primary postgresql server.

- "10.11.12.0" is the format IP address for your inner network
- "24" is the netmask in your inner network
- "master" is the target of this operation
- "10.11.12.101" is the ip address of this host
- "9.5" is the current version of this postgresql server


Standby Server Operation:

> bash build.sh -i 10.11.12.0 -m 24 -t slave -M 10.11.12.101 -v 9.5

Run the above command in the one host to build the primary postgresql server.

- "10.11.12.0" is the format IP address for your inner network
- "24" is the netmask in your inner network
- "slave" is the target of this operation
- "10.11.12.101" is the ip address of this master host
- "9.5" is the current version of this postgresql server


Test:

Login the primary server

> create table test (id int);


Then log into the standby server

> \dt 
> \d+ test
