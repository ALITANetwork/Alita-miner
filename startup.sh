#!/bin/sh
source ./alita.conf
#1.将宿主机加入k3s集群
function getOS(){ #获取系统信息
    OS=`uname -s`
    if [ ${OS} == "Darwin"  ];then
        OSNAME='Mac'
        PKG=brew
    elif [ ${OS} == "Linux"  ];then
	source /etc/os-release
	case $ID in
            debian|ubuntu|devuan)
                OSNAME='Ubuntu'
                PKG=apt-get
                ;;
            centos|fedora|rhel)
                OSNAME='Centos'
                PKG=yum
                if test "$(echo "$VERSION_ID >= 22" | bc)" -ne 0;
                then
                    PKG=dnf
                fi
                ;;
            *)
                exit 1
                ;;
        esac
    else
        OSNAME=`uname -s`
    fi
    echo "检测到系统是${OSNAME},包管理工具是${PKG}"
}
getOS

function check_dependency(){
    function check_docker(){
    	if ! command -v docker &> /dev/null
    	then
            echo "docker could not be found"
            ${PKG} install -y docker
            exit
        else
            echo "docker has installed"
    	fi
    }
    function check_jq(){
        if [ `command -v jq` ];then
            echo 'jq 已经安装'
        else
            echo 'jq 未安装,开始安装json解析工具'
    	    #安装jq
            ${PKG} install jq -y
            if [ `command -v jq` ];then
                echo 'jq 成功安装'
            else
                echo 'jq 安装失败，请手动换源安装'
                exit 8
            fi
        fi
    }
    function check_curl(){
	if [ `command -v curl` ];then
	    echo 'curl already installd'
	else
	    ${PKG} install curl -y
	fi
    }
    check_docker
    check_jq
    check_curl
}

function uninstall_agent(){ #检查本地k3s服务，如果没有启动则删除k3s的服务重新启动
    set -x
    [ $(id -u) -eq 0 ] || exec sudo $0 $@
    /usr/local/bin/k3s-killall.sh
    if which systemctl; then
        systemctl disable k3s-agent
        systemctl reset-failed k3s-agent
        systemctl daemon-reload
    fi
    if which rc-update; then
        rc-update delete k3s-agent default
    fi
    rm -f /etc/systemd/system/k3s-agent.service
    rm -f /etc/systemd/system/k3s-agent.service.env
    remove_uninstall() {
        rm -f /usr/local/bin/k3s-agent-uninstall.sh
    }
    trap remove_uninstall EXIT
    if (ls /etc/systemd/system/k3s*.service || ls /etc/init.d/k3s*) >/dev/null 2>&1; then
        set +x; echo 'Additional k3s services installed, skipping uninstall of k3s'; set -x
        exit
    fi
    for cmd in kubectl crictl ctr; do
        if [ -L /usr/local/bin/$cmd ]; then
            rm -f /usr/local/bin/$cmd
        fi
    done
    rm -rf /etc/rancher/k3s
    rm -rf /var/lib/rancher/k3s/data
    rm -rf /var/lib/rancher/k3s/agent/*.crt
    rm -rf /var/lib/rancher/k3s/agent/*.key
    rm -rf /var/lib/rancher/k3s/agent/*.kubeconfig
    rm -rf /var/lib/rancher/k3s/agent/*.yaml
    rm -rf /var/lib/rancher/k3s/agent/etc
    rm -rf /var/lib/rancher/k3s/agent/kubelet
    rm -rf /var/lib/kubelet
    rm -f /usr/local/bin/k3s-killall.sh
}

function get_docker_base_images(){  #获取k3s部署必备的docker
    docker pull mirrorgooglecontainers/kube-proxy-amd64:v1.11.3
    docker pull registry.cn-hangzhou.aliyuncs.com/launcher/pause:3.1
    docker pull coredns/coredns:1.1.3
    docker pull rancher/local-path-provisioner:v0.0.11
    
    docker tag mirrorgooglecontainers/kube-proxy-amd64:v1.11.3 k8s.gcr.io/kube-proxy-amd64:v1.11.3
    docker tag registry.cn-hangzhou.aliyuncs.com/launcher/pause:3.1  k8s.gcr.io/pause:3.1
    docker tag docker.io/coredns/coredns:1.1.3  k8s.gcr.io/coredns:1.1.3
}

function getrealmac() { #获取该设备的mac地址作为节点名字
    #Collecting all physical interfaces's name and mac addresse
    declare -A NAME_TO_MAC
    set -e
    for f in /sys/class/net/*; do
      if [ -L $f ]; then
        name=`readlink $f`
        if echo $name | grep -v 'devices/virtual' > /dev/null; then
          eval $(ifconfig `basename $f` | head -n 1 | awk '{print "NAME_TO_MAC[\"",$1,"\"]=",$5}' | tr -d ' ')
        fi
      fi
    done

    function getRealMac()
    {
      local ifname=$1
      local bond=$2
      local pattern="Slave Interface $ifname"
      awk -v pattern="$pattern" '$0 ~ pattern, $0 ~ /^$/' $bond | awk '/Permanent HW addr/{print $4}' | tr -d ' '
    }

    #Trying to get the real mac when there's a bonding interface
    for name in "${!NAME_TO_MAC[@]}";  do
      for bond in /proc/net/bonding/*; do
        if grep $name /sys/devices/virtual/net/`basename $bond`/bonding/slaves > /dev/null; then
          MAC=`getRealMac $name $bond`
          if ! [ -z $MAC ]; then
            NAME_TO_MAC["$name"]="$MAC"
          fi
        fi
      done
    done

    set +e

    for k in ${!NAME_TO_MAC[@]}; do
       echo $k ${NAME_TO_MAC[$k]}
       MAC_NAME=$k
    done

    REAL_MAC=`ifconfig $MAC_NAME| grep ether | awk -F" " '{print $2}'`

    echo ${REAL_MAC}
    # shellcheck disable=SC2006
    # shellcheck disable=SC2209
    node_name=`echo ${REAL_MAC} | sed 's/://g'`
    if [ -n "${node_name}" ]; then
        node_name=${node_name}
    else
        echo "Please Check The Device's MAC And Then Run: export MAC=*****;export node_name=${MAC}"
        return
    fi
}

function change_docker_driver(){ #将dockerDriver设置成cgroupfs
    CGROUP_DRIVER=$(docker info -f '{{json .}}'|jq '.CgroupDriver'| sed -r 's/.*"(.+)".*/\1/')
    DOCKER_VERSION=$(docker -v)
    NEED_RESTART_DOCKER=false
    if [ $? -eq  0 ];then
        echo "已安装Docker,版本号为$DOCKER_VERSION"
    else
        echo '机器上并未安装Docker。执行安装docker'
        ${PKG} install -y docker
    fi
    if [ $CGROUP_DRIVER == 'cgroupfs' ];then
        echo "Docker的Cgroup Driver为$CGROUP_DRIVER，无需更改"
    else
        echo "Docker的Cgroup Driver为$CGROUP_DRIVER，正在更改为cgroupfs"
        if [ -f /usr/lib/systemd/system/docker.service ];then
            echo "修改service文件"
            if [ `grep -c "=systemd" /usr/lib/systemd/system/docker.service` -ne 0  ];then
                sed -i "s/systemd/cgroupfs/g" /usr/lib/systemd/system/docker.service
            else
                if [ -f /etc/docker/daemon.json ];then
                    #判断有此文件
                    if [ `grep -c "exec-opts" /etc/docker/daemon.json` -eq 1 ];then
                        sed -i "s/=systemd/=cgroupfs/g" /etc/docker/daemon.json
                    fi
                else
                    echo '没有找到daemon.json文件'
                fi
            fi
        fi
	    echo 'Docker driver changed,docker restart latter'
	    NEED_RESTART_DOCKER=true
    fi
    if [ `grep -c "registry-mirror" /usr/lib/systemd/system/docker.service` -eq 1 ];then
        sed -i '/--exec-opt/a\          --registry-mirror=https://registry.docker-cn.com \\' /usr/lib/systemd/system/docker.service
	    NEED_RESTART_DOCKER=true
        echo 'Would restart docker'
    fi
    if [ $NEED_RESTART_DOCKER == true ];then
	systemctl daemon-reload
        systemctl restart docker
    fi
}

function install_k3s(){ #安装k3s
    check_dependency
    echo ${node_token}
    echo "uninstall k3s-agent"
    uninstall_agent
    echo "getMac"
    getrealmac
    echo "${node_name}"
    # shellcheck disable=SC2009
    ps -ef|grep "k3s agent"|grep -v "grep"|awk '{print $2}'|xargs -I{} kill -9 {}
    # shellcheck disable=SC2181
    [ $? -eq 0 ] &&echo "stop k3s-agent succeed"
    # shellcheck disable=SC2006
    echo "$SUDO"
    # shellcheck disable=SC2006
    DOCKER_DRIVER=`$SUDO docker info -f '{{json .}}'|jq '.CgroupDriver'| sed -r 's/.*"(.+)".*/\1/'`
    if [ -n "${DOCKER_DRIVER}" ]; then
	    DOCKER_DRIVER=${DOCKER_DRIVER}
    else
	    DOCKER_DRIVER=cgroupfs
    fi
    BIN_DIR=/usr/local/bin
    if [ ! -x ${BIN_DIR}/k3s ]; then
        echo "Downloading K3s"
        SKIP_DOWNLOAD=false
    else
        # shellcheck disable=SC2006
        k3sversion=`${BIN_DIR}/k3s --version|awk '{print $3}'`
	echo $k3sversion
        # shellcheck disable=SC2039
        # shellcheck disable=SC2193
        if [ -"${k3sversion}" == "v0.9.0" ]; then
            SKIP_DOWNLOAD=true
        else
            SKIP_DOWNLOAD=false
        fi
    fi
    change_docker_driver
    get_docker_base_images
    
    #根据mac的hash决定加入哪台服务器
    mac_hash_256=`echo -n "${node_name}"|sha256sum |cut -d ' ' -f1`
    number=0
    #result=(${ip_hash} * 113 + 6) % 6271
    for i in `seq ${#ip_hash_256}`
    do
    number=`expr $number + $((16#${mac_hash_256:$i-1:1}))`
    done
    should_server_num=`expr $number % 6 + 1`

    curl http://pool.raptorchain.io/check_machine_online/mac=${node_name}
    curl -sfL  http://app.gravity.top:8085/install.sh | INSTALL_K3S_EXEC="agent --docker --server https://gserver${should_server_num}.gravity.top:6443 --token ${node_token} --node-name ${node_name} --kubelet-arg cgroup-driver=${DOCKER_DRIVER} --kube-proxy-arg bind-address=127.0.0.1" INSTALL_K3S_VERSION="v0.9.0" INSTALL_K3S_SKIP_DOWNLOAD=${SKIP_DOWNLOAD} sh -s -
    systemctl daemon-reload
    systemctl start k3s-agent
    #nohup k3s agent --docker --server https://gserver.gravity.top:6443 --token ${node_token} 2>&1 >k3sagent.log &
    echo "agent start"
}

install_k3s

#2.获取miner最新版本信息

#3.删除本地miner，构建(拉取)新miner包

#4.启动miner容器
function build_miner(){
    docker build -t alitaminer:v1.0.0-Beta .
    mkdir -p ${dir}/plots/${key}_${startNonce}_${nonces}
}

function run_miner(){
    nohup docker run -v ${dir}/plots/${key}_${startNonce}_${nonces}:/usr/local/plots --privileged=true -e MAC_ADDR=${REAL_MAC} -e passPhrase="${passPhrase}" -e numericAccountId=${key} -e startNonce=${startNonce} -e nonces=${nonces} -e soloServer=${alitaServer} -i alitaminer:v1.0.0-Beta >${dir}/plots/${key}_${startNonce}_${nonces}/docker.log &
}

build_miner
run_miner



