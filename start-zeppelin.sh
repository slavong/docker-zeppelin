#!/bin/bash
cd /usr/local/zeppelin

echo "Filling Zeppelin configuration templates"

function replace_env_config_if_not_exists {
  local conf_name=$1
  local envs_to_replace=$2
  if [ ! -r conf/$conf_name ]; then
    echo "$conf_name does not exist, creating it"
    envsubst $envs_to_replace < conf.templates/$conf_name.template > conf/$conf_name
  else
    echo "$conf_name already exists, not overwriting"
  fi
}

function replace_env_config {
  local conf_name=$1
  local envs_to_replace=$2
  echo "creating $conf_name ($envs_to_replace)"
  envsubst $envs_to_replace < conf.templates/$conf_name.template > conf/$conf_name
}

function hash_password {
  local password=$(eval echo "$""$1")
  echo $password
  local iterations=1000000
  local hash=$(java -jar shiro-tools-hasher-1.3.2-cli.jar -f shiro1 -a sha-256 -i $iterations -gs $password)
  echo $hash
  eval "$1='"$(echo $hash)"'"
}

ZEPPELIN_PASSWORD=${ZEPPELIN_PASSWORD:-zeppelin}
hash_password ZEPPELIN_PASSWORD
ZEPPELIN_DEVELOPER_PASSWORD=${ZEPPELIN_DEVELOPER_PASSWORD:-$ZEPPELIN_PASSWORD}
hash_password ZEPPELIN_DEVELOPER_PASSWORD

replace_env_config_if_not_exists interpreter.json
replace_env_config zeppelin-env.sh
replace_env_config zeppelin-site.xml
vars='$ZEPPELIN_PASSWORD:$ZEPPELIN_DEVELOPER_PASSWORD'
vars+=':$ZEPPELIN_LDAP_PROTOCOL:$ZEPPELIN_LDAP_SERVER:$ZEPPELIN_LDAP_PORT'
vars+=':$ZEPPELIN_LDAP_USER_GROUP:$ZEPPELIN_LDAP_ADMIN_GROUP'
vars+=':$ZEPPELIN_LDAP_SEARCH_BASE'
replace_env_config shiro.ini "$vars"
replace_env_config interpreter-list
replace_env_config log4j.properties '$ZEPPELIN_LOG_LEVEL'
replace_env_config hive-site.xml

set -e

if [ -z "$ZEPPELIN_LDAP_SERVER" ]
then
  sed '/ldapRealm/d' -i conf/shiro.ini
else
  ZEPPELIN_LDAP_PROTOCOL=${ZEPPELIN_LDAP_PROTOCOL:-ldap}
  ZEPPELIN_LDAP_PORT=${ZEPPELIN_LDAP_PORT:-389}
  if [ "$ZEPPELIN_LDAP_PROTOCOL" == "ldaps" ]
  then
    echo -n | openssl s_client -connect "$ZEPPELIN_LDAP_SERVER":"$ZEPPELIN_LDAP_PORT" | \
      sed -ne '/---BEGIN CERTIFICATE---/,/---END CERTIFICATE---/p' > /tmp/ldap.crt 2> /dev/null
    keytool -import \
      -keystore $JAVA_HOME/lib/security/cacerts \
      -storepass changeit \
      -noprompt \
      -alias ldapcert \
      -file /tmp/ldap.crt
  fi
fi

# Oracle client installation
if [ ! -z "$ZEPPELIN_ORACLE_VERSION" ]
then
  ZEPPELIN_ORACLE_VERSION=${ZEPPELIN_ORACLE_VERSION:-12.2.0.1.0}
  ZEPPELIN_ORACLE_URL=${ZEPPELIN_ORACLE_URL:-https://github.com/bumpx/oracle-instantclient/raw/master/}

  echo "Downloading Oracle instant client installation files ..."
  mkdir -p oracle/
  for file in sdk sqlplus basic
  do
    curl \
      -L -o oracle/instantclient-$file-linux.x64.zip \
      $ZEPPELIN_ORACLE_URL/instantclient-$file-linux.x64-$ZEPPELIN_ORACLE_VERSION.zip
  done
 
  echo "Installing Oracle instant client version $ZEPPELIN_ORACLE_VERSION ..." 
  mkdir -p opt/oracle
  unzip oracle/instantclient-basic-linux.x64.zip -d /opt/oracle
  unzip oracle/instantclient-sdk-linux.x64.zip -d /opt/oracle
  unzip oracle/instantclient-sqlplus-linux.x64.zip -d /opt/oracle
  mv /opt/oracle/instantclient_* /opt/oracle/instantclient
  ln -s /opt/oracle/instantclient/libclntsh.so.* /opt/oracle/instantclient/libclntsh.so
  ln -s /opt/oracle/instantclient/libocci.so.* /opt/oracle/instantclient/libocci.so
  mkdir -p opt/oracle/instantclient/network/admin

  export OCI_HOME="/opt/oracle/instantclient"
  export OCI_LIB_DIR="/opt/oracle/instantclient"
  export OCI_INCLUDE_DIR="/opt/oracle/instantclient/sdk/include"
  export OCI_VERSION=12
  export LD_LIBRARY_PATH="/opt/oracle/instantclient"
  export TNS_ADMIN="/opt/oracle/instantclient"
  export ORACLE_BASE="/opt/oracle/instantclient"
  export ORACLE_HOME="/opt/oracle/instantclient"
  export PATH="/opt/oracle/instantclient:$PATH"
  echo '/opt/oracle/instantclient/' | tee -a /etc/ld.so.conf.d/oracle_instant_client.conf && ldconfig
  echo "Installation of Oracle instant client done."
fi # end of Oracle client install

# add zeppelin group if not exists
if [ -z "$ZEPPELIN_PROCESS_GROUP_NAME" ]; then
  echo "Environment variable ZEPPELIN_PROCESS_GROUP_NAME required, but not set, exiting ..."
  exit
elif [ -z "$ZEPPELIN_PROCESS_GROUP_ID" ]; then
  echo "Environment variable ZEPPELIN_PROCESS_GROUP_ID required, but not set, exiting ..."
  exit
elif getent group $ZEPPELIN_PROCESS_GROUP_NAME; then
  echo "Group $ZEPPELIN_PROCESS_GROUP_NAME already exists"
else
  echo "Group $ZEPPELIN_PROCESS_GROUP_NAME does not exist, creating it with gid=$ZEPPELIN_PROCESS_GROUP_ID"
  addgroup --force-badname -gid $ZEPPELIN_PROCESS_GROUP_ID $ZEPPELIN_PROCESS_GROUP_NAME
fi

# add zeppelin user if not exists
if [ -z "$ZEPPELIN_PROCESS_USER_NAME" ]; then
  echo "Environment variable ZEPPELIN_PROCESS_USER_NAME required, but not set, exiting ..."
  exit
elif [ -z "$ZEPPELIN_PROCESS_USER_ID" ]; then
  echo "Environment variable ZEPPELIN_PROCESS_USER_ID required, but not set, exiting ..."
  exit
elif id -u $ZEPPELIN_PROCESS_USER_NAME 2>/dev/null; then
  echo "User $ZEPPELIN_PROCESS_USER_NAME already exists"
else
  echo "User $ZEPPELIN_PROCESS_USER_NAME does not exist, creating it with uid=$ZEPPELIN_PROCESS_USER_ID"
  adduser --force-badname $ZEPPELIN_PROCESS_USER_NAME --uid $ZEPPELIN_PROCESS_USER_ID --gecos "" --ingroup $ZEPPELIN_PROCESS_GROUP_NAME --disabled-login --disabled-password
fi 

# adjust ownership of the zeppelin folder
chown -R $ZEPPELIN_PROCESS_USER_NAME ../zeppelin
chgrp -R $ZEPPELIN_PROCESS_GROUP_NAME ../zeppelin
chown -R $ZEPPELIN_PROCESS_USER_NAME /hive
chgrp -R $ZEPPELIN_PROCESS_GROUP_NAME /hive
chown -R $ZEPPELIN_PROCESS_USER_NAME /home/$ZEPPELIN_PROCESS_USER_NAME
chgrp -R $ZEPPELIN_PROCESS_GROUP_NAME /home/$ZEPPELIN_PROCESS_USER_NAME

echo "Starting Zeppelin ..."
exec sudo -u $ZEPPELIN_PROCESS_USER_NAME -E env "PATH=$PATH" bin/zeppelin.sh
