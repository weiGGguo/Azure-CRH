#!/bin/sh
NodeNum=$1
MasterIp="10.0.0.254"
UserName="crhuser"
UserPasswd="Redoop123!"

clientIP="10.0.0.80"


mkdir script

echo "ambari.repo ..."
echo "[Ambari]
name=ambari-2.2.1
baseurl=http://archive.redoop.com/crh/rpm/4.9.2.3/CRH/x86_64/redhat6
enabled=1
gpgcheck=0 
[CRH-4.9]
name=CRH-4.9
baseurl=http://archive.redoop.com/crh/rpm/4.9.2.3/CRH/x86_64/redhat6
path=/
enabled=1" >> script/ambari.repo

echo "master_ssh.sh ..." 
echo "#!/bin/sh
UserName=\$1
create_ssh () {
  expect -c \"set timeout -1; 
            spawn ssh-keygen -t rsa;
            expect {
	            *(/home/\$UserName/.ssh/id_rsa):* {send -- \r;exp_continue;}
              *(y/n)?* {send -- y\r;exp_continue;}
	            *:* {send -- \r;exp_continue;}
	            eof        {exit 0;}
            }\";
}
create_ssh \$UserName" >> script/master_ssh.sh

echo "auto_ssh.sh ..."
echo "#!/bin/sh
UserHostName=\$1
UserPassword=\$2
auto_ssh_copy_id () {
  expect -c \"set timeout -1; 
            spawn ssh-copy-id \$1;
            expect {
              *(yes/no)* {send -- yes\r;exp_continue;}
              *password:* {send -- \$2\r;exp_continue;}
               eof        {exit 0;}
            }\";
}
auto_ssh_copy_id \$UserHostName \$UserPassword
" >> script/auto_ssh.sh

echo "jdk.sh ..."
echo "export JAVA_HOME=/opt/install/jdk
export JRE_HOME=/opt/install/jdk/jre
export CLASSPATH=.:\$JAVA_HOME/lib:\$JRE_HOME/lib:\$CLASSPATH
export PATH=\$JAVA_HOME/bin:\$JRE_HOME/bin:\$PATH" >>script/jdk.sh

echo "setup_ambari.sh ..."
echo "#!/bin/sh
UserName=\$1
auto_setup_ambari () {
  expect -c \"set timeout -1; 
            spawn /usr/sbin/ambari-server setup -j /opt/install/jdk;
            expect {
              *continue* {send -- y\r;exp_continue;}
              *Customize* {send -- y\r;exp_continue;}
              *root* {send -- \$UserName\r;exp_continue;}
              *configuration* {send -- n\r;exp_continue;}
               eof        {exit 0;}
            }\";
}
auto_setup_ambari \$UserName" >> script/setup_ambari.sh

echo "#!/bin/sh
mount_d(){
  expect -c \"set timeout -1;
              spawn mkfs.ext4 /dev/sdc;
              expect {
                *(y,n)* {send -- y\r;exp_continue;}
                eof                    {exit 0;}
              }\";
}
mount_d

mkdir /data

mount /dev/sdc /data

" >> script/mountd.sh

chmod 777 /etc/sudoers
sed -i 's/Defaults    requiretty/#Defaults    requiretty/g' /etc/sudoers
chmod 400 /etc/sudoers
echo "yum install expect ..."
yum install -y expect >/dev/null 2>&1

echo "wget jdk ..."
wget http://archive.redoop.com/crh/tools/jdk/oracle_jdk/jdk-7u79-linux-x64.tar.gz >/dev/null 2>&1


service iptables stop
chkconfig iptables off

service ip6tables stop
chkconfig ip6tables off
setenforce 0

sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

chmod 755 script/*

echo $MasterIp master >> script/master_ip
echo $clientIP client >> script/client_ip

Segment=${MasterIp%"."*}


ip_num=3
for ((i=1;i<=$NodeNum;i++))
do
let ip_num+=$i
echo $Segment"."$ip_num node$i >> script/node_ip
let ip_num-=$i
done

echo "edit /etc/hosts ..."
cat < script/master_ip >> /etc/hosts
cat < script/node_ip >> /etc/hosts
cat < script/client_ip >> /etc/hosts

cat < script/master_ip >> script/ip
cat < script/node_ip >> script/ip
cat < script/client_ip >> script/ip

mkdir /opt/install
tar -zxf jdk*.tar.gz
rm -fr jdk*.tar.gz
mv jdk* jdk
mv jdk/ /opt/install


mv script/ambari.repo /etc/yum.repos.d/
yum clean all

mv script/jdk.sh /etc/profile.d/
source /etc/profile

mv script/ /opt/

echo "sh /opt/script/master_ssh.sh $UserName"| su - $UserName

while read line
do
   temp_name=${line##*" "}
   echo "sh /opt/script/auto_ssh.sh $temp_name $UserPasswd"| su - $UserName
done < /opt/script/ip


echo "yum install ambari-server ..."
yum install -y ambari-server >/dev/null 2>&1
echo "yum install ambari-agent ..."
yum install -y ambari-agent >/dev/null 2>&1

sed -i "s/hostname=localhost/hostname=master/g" /etc/ambari-agent/conf/ambari-agent.ini

sh /opt/script/setup_ambari.sh $UserName

echo "start ambari-server ..."
/usr/sbin/ambari-server start >/dev/null 2>&1
echo "yum update openssl ..."
yum update openssl -y >/dev/null 2>&1
echo "start ambari-agent ..."
ambari-agent start >/dev/null 2>&1

sh /usr/local/licence/bin/startup.sh



sh /opt/script/mountd.sh


echo "crh-repo.json ..."
echo "{
  \"Repositories\" : {
    \"base_url\" : \"http://archive.redoop.com/crh/rpm/4.9.2.3/CRH/x86_64/redhat6\",
    \"verify_base_url\" : false
  }
}" >> crh-repo.json
echo "crh-utils-repo.json ..."
cp crh-repo.json crh-utils-repo.json

let NodeNum+=1
data_node_num=$[$NodeNum-3]

echo "blueprint.json ..."
echo "{
  \"configurations\": [],
  \"Blueprints\": {
    \"blueprint_name\": \"cluster_bigdata\",
    \"stack_name\": \"CRH\",
    \"stack_version\": \"2.3\"
  },
  \"host_groups\": [
    {
      \"name\": \"host_group_1\",
      \"configurations\": [],
      \"components\": [
        { \"name\": \"ZOOKEEPER_CLIENT\"},    
        { \"name\": \"HDFS_CLIENT\"},       
        { \"name\": \"YARN_CLIENT\"},
        { \"name\": \"MAPREDUCE2_CLIENT\"}
      ],
      \"cardinality\": \"1\"
    }" >> A

echo ",
    {
      \"name\": \"host_group_2\",
      \"configurations\": [],
      \"components\": [
        { \"name\": \"ZOOKEEPER_SERVER\"},
        { \"name\": \"AMBARI_SERVER\"},
        { \"name\": \"METRICS_COLLECTOR\"},
        { \"name\": \"NAMENODE\"},      
        { \"name\": \"NODEMANAGER\"},
        { \"name\": \"METRICS_MONITOR\"},
        { \"name\": \"HISTORYSERVER\"},
        { \"name\": \"RESOURCEMANAGER\"},
        { \"name\": \"APP_TIMELINE_SERVER\"},
        { \"name\": \"SECONDARY_NAMENODE\"},
        { \"name\": \"DATANODE\"}
      ],
      \"cardinality\": \"1\"
    }" >> B

echo ",
    {
      \"name\": \"host_group_3\",
      \"configurations\": [],
      \"components\": [
        { \"name\": \"ZOOKEEPER_SERVER\"},
        { \"name\": \"NODEMANAGER\"},
        { \"name\": \"METRICS_MONITOR\"},
        { \"name\": \"DATANODE\"}
      ],
      \"cardinality\": \"host2\"
    }" >> C
echo " ,
    {
      \"name\": \"host_group_4\",
      \"configurations\": [],
      \"components\": [
        { \"name\": \"NODEMANAGER\"},
        { \"name\": \"METRICS_MONITOR\"},
        { \"name\": \"DATANODE\"}
      ],
      \"cardinality\": \"1+\"
    }" >> D
echo " ]
}" >> E

cat < A >> blueprint.json
cat < B >> blueprint.json


if [ $NodeNum = 2 ]
then 
cat < C >> blueprint.json
sed -i "s/host2/1/g" blueprint.json
fi

if [ $NodeNum = 3 ]
then 
cat < C >> blueprint.json
sed -i "s/host2/2/g" blueprint.json
fi

if [ $NodeNum -ge 4 ]
then
cat < C >> blueprint.json
sed -i "s/host2/2/g" blueprint.json
cat < D >> blueprint.json
sed -i "s/1+/$data_node_num/g" blueprint.json
fi


cat < E >> blueprint.json


rm -fr A B C D E

echo "hosts.json ..."
echo "{
    \"blueprint\": \"cluster_bigdata\",
    \"default_password\": \"admin\",
    \"host_groups\": [
        {
            \"name\": \"host_group_1\",
            \"hosts\": [
                {
                    \"fqdn\": \"client\",
                    \"configurations\": []
                }
            ]
        }" >> A

echo ",
        {
            \"name\": \"host_group_2\",
            \"hosts\": [
                {
                    \"fqdn\": \"master\",
                    \"configurations\": []
                }
            ]
        }" >> B
echo " ,
        {
            \"name\": \"host_group_3\",
            \"hosts\": [
                {\"fqdn\": \"node1\"}
            ]
        }" >> C
echo " ,
        {
            \"name\": \"host_group_3\",
            \"hosts\": [
                {\"fqdn\": \"node1\"},
                {\"fqdn\": \"node2\"}
            ]
        }" >> D
echo ",
        {
            \"name\": \"host_group_4\",
            \"host_count\" : \"1+\"
        }" >> E
echo " ]
}" >> F

cat < A >> hosts.json
cat < B >> hosts.json

if [ $NodeNum = 2 ]
then 
cat < C >> hosts.json
fi
if [ $NodeNum = 3 ]
then 
cat < D >> hosts.json
fi
if [ $NodeNum -ge 4 ]
then
cat < D >> hosts.json
cat < E >> hosts.json
sed -i "s/1+/$data_node_num/g" hosts.json
fi

cat < F >> hosts.json

rm -fr A B C D E F

echo "zhi xing dao zhe li ..........."

sleep 60

curl --connect-timeout 30 -u admin:admin -H "X-Requested-By:ambari" -i -X POST -d @blueprint.json http://10.0.0.254:8080/api/v1/blueprints/cluster_bigdata?validate_topology=false
curl --connect-timeout 30 -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d @crh-repo.json http://10.0.0.254:8080/api/v1/stacks/CRH/versions/2.3/operating_systems/redhat6/repositories/CRH-2.3
curl --connect-timeout 30 -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d @crh-utils-repo.json http://10.0.0.254:8080/api/v1/stacks/CRH/versions/2.3/operating_systems/redhat6/repositories/CRH-UTILS-1.1.0.20
curl --connect-timeout 30 -u admin:admin -H "X-Requested-By:ambari" -i -X POST -d @hosts.json http://10.0.0.254:8080/api/v1/clusters/BigData

rm -rf /usr/lib/ambari-server/web/javascripts/*.js

#rm -fr /opt/script

mkdir /mnt/resource/data


