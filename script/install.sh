#!/bin/bash

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ /
#     Arch Not tested
#   Description: Nezha monitoring installation script
#   Github: https://github.com/naiba/nezha
#========================================================

NZ_BASE_PATH="/opt/nezha"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="/etc/systemd/system/nezha-agent.service"
NZ_VERSION="v0.8.2"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""

pre_check() {
    command -v systemctl >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo "This system is not supported: systemctl command not found"
        exit 1
    fi

    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}mistake: ${plain} This script must be run as root user！\n" && exit 1

    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
    elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
    elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
    elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi

    ## China_IP
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "According to the information provided by ipapi.co, the current IP may be in China"
            read -e -r -p "Whether to choose a Chinese mirror to complete the installation? [Y/n] " input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;

            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi

    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/MartijnLindeman/nezha/master"
        GITHUB_URL="github.com"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" "
        Docker_IMG="ghcr.io\/MartijnLindeman\/nezha-dashboard"
    else
        GITHUB_RAW_URL="cdn.jsdelivr.net/gh/MartijnLindeman/nezha@master"
        GITHUB_URL="dn-dao-github-mirror.daocloud.io"
        Get_Docker_URL="get.daocloud.io/docker"
        Get_Docker_Argu=" -s docker --mirror Aliyun"
        Docker_IMG="registry.cn-shanghai.aliyuncs.com\/MartijnLindeman\/nezha-dashboard"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> update script"

    curl -sL https://${GITHUB_RAW_URL}/script/install.sh -o /tmp/nezha.sh
    new_version=$(cat /tmp/nezha.sh | grep "NZ_VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "Failed to get the script, please check whether the machine can be linked https://${GITHUB_RAW_URL}/script/install.sh"
        return 1
    fi
    echo -e "The latest version is: ${new_version}"
    mv -f /tmp/nezha.sh ./nezha.sh && chmod a+x ./nezha.sh

    echo -e "Execute new script after 3s"
    sleep 3s
    clear
    exec ./nezha.sh
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* Press enter to return to the main menu *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v tar >/dev/null 2>&1) ||
        (install_soft curl wget git tar)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum install $* -y) ||
        (command -v apt >/dev/null 2>&1 && apt install $* -y) ||
        (command -v pacman >/dev/null 2>&1 && pacman -Syu $*) ||
        (command -v apt-get >/dev/null 2>&1 && apt-get install $* -y)
}

install_dashboard() {
    install_base

    echo -e "> installation panel"

    # Nezha monitoring folder
    mkdir -p $NZ_DASHBOARD_PATH
    chmod 777 -R $NZ_DASHBOARD_PATH

    command -v docker >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "Installing Docker"
        bash <(curl -sL https://${Get_Docker_URL}) ${Get_Docker_Argu} >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 ${Get_Docker_URL}${plain}"
            return 0
        fi
        systemctl enable docker.service
        systemctl start docker.service
        echo -e "${green}Docker${plain} 安装成功"
    fi

    command -v docker-compose >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "Installing Docker Compose"
        wget -O /usr/local/bin/docker-compose "https://${GITHUB_URL}/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}The download script failed, please check whether the machine can be connected ${GITHUB_URL}${plain}"
            return 0
        fi
        chmod +x /usr/local/bin/docker-compose
        echo -e "${green}Docker Compose${plain} 安装成功"
    fi

    modify_dashboard_config 0

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_agent() {
    install_base

    echo -e "> Install Monitoring Agent"

    echo -e "Getting the monitoring agent version number"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/naiba/nezha/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://cdn.jsdelivr.net/gh/naiba/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
    fi

    if [ ! -n "$version" ]; then
        echo -e "Failed to get the version number, please check whether the machine can be linked https://api.github.com/repos/naiba/nezha/releases/latest"
        return 0
    else
        echo -e "The latest version is: ${version}"
    fi

    # 哪吒监控文件夹
    mkdir -p $NZ_AGENT_PATH
    chmod 777 -R $NZ_AGENT_PATH

    echo -e "Downloading monitor"
    wget -O nezha-agent_linux_${os_arch}.tar.gz https://${GITHUB_URL}/naiba/nezha/releases/download/${version}/nezha-agent_linux_${os_arch}.tar.gz >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
        return 0
    fi
    tar xf nezha-agent_linux_${os_arch}.tar.gz &&
        mv nezha-agent $NZ_AGENT_PATH &&
        rm -rf nezha-agent_linux_${os_arch}.tar.gz README.md

    if [ $# -ge 3 ]; then
        modify_agent_config "$@"
    else
        modify_agent_config 0
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_agent_config() {
    echo -e "> Modify Agent Configuration"

    wget -O $NZ_AGENT_SERVICE https://${GITHUB_RAW_URL}/script/nezha-agent.service >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}The file download failed, please check whether the machine can be connected ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    if [ $# -lt 3 ]; then
        echo "Please add Agent on the management panel first and record the key" &&
            read -ep "Please enter a domain name that resolves to the IP of the panel (CDN is not available): " nz_grpc_host &&
            read -ep "Please enter the panel RPC port: (5555)" nz_grpc_port &&
            read -ep "Please enter the Agent key: " nz_client_secret
        if [[ -z "${nz_grpc_host}" || -z "${nz_client_secret}" ]]; then
            echo -e "${red}All options cannot be empty${plain}"
            before_show_menu
            return 1
        fi
        if [[ -z "${nz_grpc_port}" ]]; then
            nz_grpc_port=5555
        fi
    else
        nz_grpc_host=$1
        nz_grpc_port=$2
        nz_client_secret=$3
    fi

    sed -i "s/nz_grpc_host/${nz_grpc_host}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nz_grpc_port/${nz_grpc_port}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nz_client_secret/${nz_client_secret}/" ${NZ_AGENT_SERVICE}

    shift 3
    if [ $# -gt 0 ]; then
        args=" $*"
        sed -i "/ExecStart/ s/$/${args}/" ${NZ_AGENT_SERVICE}
    fi

    echo -e "Agent configuration ${green}The modification is successful, please wait for a restart to take effect${plain}"

    systemctl daemon-reload
    systemctl enable nezha-agent
    systemctl restart nezha-agent

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_dashboard_config() {
    echo -e "> Modify panel configuration"

    echo -e "Downloading Docker script"
    wget -O ${NZ_DASHBOARD_PATH}/docker-compose.yaml https://${GITHUB_RAW_URL}/script/docker-compose.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}The download script failed, please check whether the machine can be connected ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    mkdir -p $NZ_DASHBOARD_PATH/data

    wget -O ${NZ_DASHBOARD_PATH}/data/config.yaml https://${GITHUB_RAW_URL}/script/config.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}The download script failed, please check whether the machine can be connected ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    echo "About the GitHub Oauth2 app：在 https://github.com/settings/developers Create, no need to review, Callback fill http(s)://域名或IP/oauth2/callback" &&
        echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
        read -ep "请输入 OAuth2 提供商(gitee/github，默认 github): " nz_oauth2_type &&
        read -ep "请输入 Oauth2 应用的 Client ID: " nz_github_oauth_client_id &&
        read -ep "请输入 Oauth2 应用的 Client Secret: " nz_github_oauth_client_secret &&
        read -ep "请输入 GitHub/Gitee Login name as administrator, multiple separated by comma: " nz_admin_logins &&
        read -ep "Please enter a site title: " nz_site_title &&
        read -ep "Please enter the site access port: (8008)" nz_site_port &&
        read -ep "Please enter the RPC port for Agent access: (5555)" nz_grpc_port

    if [[ -z "${nz_admin_logins}" || -z "${nz_github_oauth_client_id}" || -z "${nz_github_oauth_client_secret}" || -z "${nz_site_title}" ]]; then
        echo -e "${red}All options cannot be empty${plain}"
        before_show_menu
        return 1
    fi

    if [[ -z "${nz_site_port}" ]]; then
        nz_site_port=8008
    fi
    if [[ -z "${nz_grpc_port}" ]]; then
        nz_grpc_port=5555
    fi
    if [[ -z "${nz_oauth2_type}" ]]; then
        nz_oauth2_type=github
    fi

    sed -i "s/nz_oauth2_type/${nz_oauth2_type}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_admin_logins/${nz_admin_logins}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_grpc_port/${nz_grpc_port}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_site_title/${nz_site_title}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_site_port/${nz_site_port}/" ${NZ_DASHBOARD_PATH}/docker-compose.yaml
    sed -i "s/nz_grpc_port/${nz_grpc_port}/g" ${NZ_DASHBOARD_PATH}/docker-compose.yaml
    sed -i "s/nz_image_url/${Docker_IMG}/" ${NZ_DASHBOARD_PATH}/docker-compose.yaml

    echo -e "Panel configuration ${green}The modification is successful, please wait for a restart to take effect${plain}"

    restart_and_update

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_and_update() {
    echo -e "> Reboot and update the panel"

    cd $NZ_DASHBOARD_PATH
    docker-compose pull
    docker-compose down
    docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}Nezha monitoring restarted successfully${plain}"
        echo -e "Default admin panel address: ${yellow}Domain name: site access port${plain}"
    else
        echo -e "${red}The restart failed, maybe because the startup time exceeded two seconds, please check the log information later${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_dashboard() {
    echo -e "> launchpad"

    cd $NZ_DASHBOARD_PATH && docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}Nezha monitoring started successfully${plain}"
    else
        echo -e "${red}Startup failed, please check the log information later${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_dashboard() {
    echo -e "> stop panel"

    cd $NZ_DASHBOARD_PATH && docker-compose down
    if [[ $? == 0 ]]; then
        echo -e "${green}Nezha monitoring stopped successfully${plain}"
    else
        echo -e "${red}Stop failed, please check log information later${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_dashboard_log() {
    echo -e "> Get panel log"

    cd $NZ_DASHBOARD_PATH && docker-compose logs -f

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_dashboard() {
    echo -e "> Uninstall the admin panel"

    cd $NZ_DASHBOARD_PATH &&
        docker-compose down
    rm -rf $NZ_DASHBOARD_PATH
    docker rmi -f ghcr.io/naiba/nezha-dashboard > /dev/null 2>&1
    docker rmi -f registry.cn-shanghai.aliyuncs.com/naibahq/nezha-dashboard > /dev/null 2>&1
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_agent_log() {
    echo -e "> Get Agent logs"

    journalctl -xf -u nezha-agent.service

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_agent() {
    echo -e "> Uninstall Agent"

    systemctl disable nezha-agent.service
    systemctl stop nezha-agent.service
    rm -rf $NZ_AGENT_SERVICE
    systemctl daemon-reload

    rm -rf $NZ_AGENT_PATH
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_agent() {
    echo -e "> Restart Agent"

    systemctl restart nezha-agent.service

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${NZ_BASE_PATH})" ]; then
        rm -rf ${NZ_BASE_PATH}
    fi
}

show_usage() {
    echo "How to use Nezha monitoring management script: "
    echo "--------------------------------------------------------"
    echo "./nezha.sh                            - Show admin menu"
    echo "./nezha.sh install_dashboard          - Install panel end"
    echo "./nezha.sh modify_dashboard_config    - Modify panel configuration"
    echo "./nezha.sh start_dashboard            - launchpad"
    echo "./nezha.sh stop_dashboard             - stop panel"
    echo "./nezha.sh restart_and_update         - Reboot and update the panel"
    echo "./nezha.sh show_dashboard_log         - View panel logs"
    echo "./nezha.sh uninstall_dashboard        - Uninstall the admin panel"
    echo "--------------------------------------------------------"
    echo "./nezha.sh install_agent              - installation monitoring Agent"
    echo "./nezha.sh modify_agent_config        - Modify Agent Configuration"
    echo "./nezha.sh show_agent_log             - View Agent logs"
    echo "./nezha.sh uninstall_agent            - Uninstall Agent"
    echo "./nezha.sh restart_agent              - Restart Agent"
    echo "./nezha.sh update_script              - update script"
    echo "--------------------------------------------------------"
}

show_menu() {
    echo -e "
    ${green}Nezha monitoring and management script${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/naiba/nezha ---
    ${green}1.${plain}  Install panel end
    ${green}2.${plain}  Modify panel configuration
    ${green}3.${plain}  launchpad
    ${green}4.${plain}  stop panel
    ${green}5.${plain}  Reboot and update the panel
    ${green}6.${plain}  View panel logs
    ${green}7.${plain}  Uninstall the admin panel
    ————————————————-
    ${green}8.${plain}  Install Monitoring Agent
    ${green}9.${plain}  Modify Agent Configuration
    ${green}10.${plain} View Agent logs
    ${green}11.${plain} Uninstall Agent
    ${green}12.${plain} Restart Agent
    ————————————————-
    ${green}13.${plain} update script
    ————————————————-
    ${green}0.${plain}  exit script
    "
    echo && read -ep "Please enter a selection [0-13]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        install_dashboard
        ;;
    2)
        modify_dashboard_config
        ;;
    3)
        start_dashboard
        ;;
    4)
        stop_dashboard
        ;;
    5)
        restart_and_update
        ;;
    6)
        show_dashboard_log
        ;;
    7)
        uninstall_dashboard
        ;;
    8)
        install_agent
        ;;
    9)
        modify_agent_config
        ;;
    10)
        show_agent_log
        ;;
    11)
        uninstall_agent
        ;;
    12)
        restart_agent
        ;;
    13)
        update_script
        ;;
    *)
        echo -e "${red}Please enter the correct number [0-13]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
    "install_dashboard")
        install_dashboard 0
        ;;
    "modify_dashboard_config")
        modify_dashboard_config 0
        ;;
    "start_dashboard")
        start_dashboard 0
        ;;
    "stop_dashboard")
        stop_dashboard 0
        ;;
    "restart_and_update")
        restart_and_update 0
        ;;
    "show_dashboard_log")
        show_dashboard_log 0
        ;;
    "uninstall_dashboard")
        uninstall_dashboard 0
        ;;
    "install_agent")
        shift
        if [ $# -ge 3 ]; then
            install_agent "$@"
        else
            install_agent 0
        fi
        ;;
    "modify_agent_config")
        modify_agent_config 0
        ;;
    "show_agent_log")
        show_agent_log 0
        ;;
    "uninstall_agent")
        uninstall_agent 0
        ;;
    "restart_agent")
        restart_agent 0
        ;;
    "update_script")
        update_script 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
