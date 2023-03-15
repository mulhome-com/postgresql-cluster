#!/bin/bash

scriptname="$(basename $0)"
currentpath="$(cd -- "$(dirname "$0")" > /dev/null 2>&1; pwd -P)"

print_usage() {
	printf "USAGE:\n %s [OPTIONS]\n\n" "${scriptname}" >&2
	printf "options:\n" >&2
	printf " -h, --help          Print the usage for this shell.\n" >&2
	printf " -i, --ip            The ip address for communication between master and slave.\n" >&2
	printf " -m, --mask          The mask value for that ip address.\n" >&2
	printf " -M, --master        The ip address for master server.\n" >&2
	printf " -t, --target        The target one which to operate, just like master or slave.\n" >&2
	printf " -v, --version       The version of target postgresql server, default 12.\n" >&2
	printf "" >&2
	exit 0
}

TARGETS=( master slave )
TARGET=slave

IPADDR=""
IPMASK=""

MASTER=""

DATAPATH=""

VERSION=12

while [ "$#" -gt 0 ];
do
	case $1 in
		-i | --ip)
			shift;
			IPADDR=$1
			shift
			;;
		-m | --mask)
			shift;
			IPMASK=$1
			shift
			;;
		-M | --master)
			shift;
			MASTER=$1
			shift
			;;
		-t | --target)
			shift;
			TARGET=$1
			shift
			;;
		-v | --version)
			shift;
			VERSION=$1
			shift
			;;
		-h | --help)
			print_usage
			;;
	esac
done

if [[ ! " ${TARGETS[@]} " =~ " ${TARGET} " ]]; then
	printf "Error:\n The target (${TARGET}) is not correct.\n" >&2
	print_usage
fi

if [[ -z "${IPADDR}" ]]; then
	printf "Error:\n The ip address cannot be empty.\n" >&2
	print_usage
fi

if [[ -z "${IPMASK}" ]]; then
	printf "Error:\n The ip mask cannot be empty.\n" >&2
	print_usage
fi

if [[ -z "${MASTER}" ]]; then
	printf "Error:\n The ip for master cannot be empty.\n" >&2
	print_usage
fi

DATAPATH="/var/lib/postgresql/${VERSION}/main"


log_info() {
	msg=$1
	sleep 1
	echo "INFO: ${msg}"
	#sleep 1
}

echo_msg() {
	msg=$1
	file=$2
	sudo bash -c "echo \"${msg}\" >> ${file}"
}

master_operate() {

	log_info "Postgresql server has been installed ..."
	server_exist=$(dpkg --list | grep ^ii | grep postgresql-${VERSION})
	if [[ -z "${server_exist}" ]]; then
		sudo apt install postgresql-${VERSION} -y
	fi

	log_info "Make user postgres login without password ..."
	pg_path=$(sudo find /etc/postgresql/ -name pg_hba.conf)
	sudo sed -i -e 's/peer/trust/g' ${pg_path}
	sudo systemctl restart postgresql

	log_info "Create the user repmgr for relication ..."
	psql -U postgres -c "create role repmgr login replication encrypted password 'mulhome.com';"
	psql -U postgres -c "alter role postgres with password 'IKge6geoZHio';"

	echo_msg "host    replication    repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    all            all           0.0.0.0/0        md5" ${pg_path}

	log_info "Create the postgresql configure ..."
	cnf_path=$(sudo find /etc/postgresql/ -name postgresql.conf)
	echo_msg "listen_addresses = '*'"  ${cnf_path}
	echo_msg "wal_level = hot_standby" ${cnf_path}
	echo_msg "max_wal_senders = 10" ${cnf_path}
	echo_msg "wal_keep_segments = 10240"  ${cnf_path}
	echo_msg "max_connections = 512" ${cnf_path}

	sudo systemctl restart postgresql@${VERSION}-main
	log_info "Done"
}

slave_operate() {

	data_path=${DATAPATH}

	if [[ -z "${data_path}" ]]; then
		printf "Error:\n The data path cannot be empty.\n" >&2
		print_usage
	fi

	log_info "Postgresql server has been installed ..."
	server_exist=$(dpkg --list | grep ^ii | grep postgresql-${VERSION})
	if [[ -z "${server_exist}" ]]; then
		sudo apt install postgresql-${VERSION} -y
	fi

	pg_path=$(sudo find /etc/postgresql/ -name pg_hba.conf)
	sudo sed -i -e 's/peer/trust/g' ${pg_path}

	echo_msg "host    replication    repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    all            all           0.0.0.0/0        md5" ${pg_path}

	log_info "Create the postgresql configure ..."
	cnf_path=$(sudo find /etc/postgresql/ -name postgresql.conf)
	echo_msg "listen_addresses = '*'"  ${cnf_path}
	echo_msg "wal_level = hot_standby" ${cnf_path}
	echo_msg "max_wal_senders = 10" ${cnf_path}
	echo_msg "wal_keep_segments = 10240"  ${cnf_path}
	echo_msg "max_connections = 512" ${cnf_path}

	sudo rm -rf postgresql_data
	sudo cp -r ${data_path} postgresql_data > /dev/null 2>&1
	sudo rm -rf ${data_path}

	log_info "Backup the master data to the slave server ..."
	sudo pg_basebackup -h ${MASTER} -U repmgr -D ${data_path} -X stream -P
	sudo chown postgres:postgres -R ${data_path}

	log_info "Configre the recovery file in the slave server ..."
	recover_path=$(sudo find /usr/share -name recovery.conf.sample)
	sudo cp ${recover_path} ${data_path}/recovery.conf

	echo_msg "standby_mode = on" ${data_path}/recovery.conf
	echo_msg "primary_conninfo = 'host=${MASTER} port=5432 user=repmgr password=mulhome.com'" ${data_path}/recovery.conf
	echo_msg "recovery_target_timeline = 'latest'" ${data_path}/recovery.conf
	echo_msg "trigger_file = '/tmp/trigger_file0'" ${data_path}/recovery.conf

	log_info "Configure the postgresql config file ..."
	cnf_path=$(sudo find /etc/postgresql/ -name postgresql.conf)
	echo_msg "hot_standby = on" ${cnf_path}

	sudo systemctl restart postgresql@${VERSION}-main
	log_info "Done!"
}

if [[ "${TARGET}" == "master" ]]; then
	master_operate
elif [[ "${TARGET}" == "slave" ]]; then
	slave_operate 
fi

