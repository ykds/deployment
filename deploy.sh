#!/bin/bash

sys_version=`cat /etc/os-release | grep VERSION_ID= | awk -F '=' '{print $2}' | sed 's/"//g'`

if [ -e /etc/redhat-release ];then
	distribution="redhat"
elif [ -e /etc/lsb-release ]; then
	distribution="ubuntu"
else
	distribution="unknown"
fi

arch=`arch`

create_nginx_service(){
	if [ ! -e /usr/lib/systemd/system/nginx.service ];then
		cat <<EOF > /usr/lib/systemd/system/nginx.service 
[Unit]
Description=Nginx
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/usr/local/nginx/logs/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/local/nginx/sbin/nginx
ExecStartPost=/usr/bin/sleep 1
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
KillSignal=SIGQUIT
KillMode=process
PrivateTmp=true	

[Install]
WantedBy=multi-user.target
EOF
		if [ -n "`ss -tlpn | grep nginx`" ];then
			cd /usr/local/nginx/sbin && ./nginx -s stop && cd - >> /dev/null
		fi
		systemctl daemon-reload
		systemctl enable nginx
		systemctl start nginx
		systemctl status nginx
	fi
}

install_nginx(){
	if [ -d /usr/local/nginx ];then
		echo "Nginx has beed installed."
    	return
	fi

	check_env

	nginx_ver="1.21.0"
	dir="nginx-${nginx_ver}"
	filename="$dir.tar.gz"
	if [ ! -e $filename ]; then
		read -p "Enter the version you want to install [default:1.21.0] " nginx_ver
		if [ -z $nginx_ver ];then
			nginx_ver=$default_version
		fi
		url="https://nginx.org/download/$filename"
		wget -O $filename $url
	fi

	if [ -e $filename ];then
		if [ ! -d $dir ];then
			tar -zxvf $filename
		fi
	else
		echo "wget $filename from $url failed."
		return
	fi

	# TODO may need to delete `-Werror -g` option from `objs/Makefile` after ./configure step
	cd $dir && ./configure --with-http_ssl_module && make && make install

	if [ -d /usr/local/nginx ];then
		create_nginx_service
		if [ -z "`cat ~/.bashrc | grep "nginx/sbin"`" ];then
			echo "PATH=\$PATH:/usr/local/nginx/sbin" >> ~/.bashrc
			source ~/.bashrc
		fi
		rm -rf $dir
		rm -f $filename
		echo "Install Nginx-$nginx_ver Successfully!"
	else
		echo "Install Nginx Failed!"
	fi
}

install_mysql8_ubuntu(){
	if [ -n "`dpkg -l | grep mysql`" ];then
		echo "Mysql8 has been installed."
		return
	fi
	filename="mysql-apt-config_0.8.29-1_all.deb"
	if [ ! -e $filename ];then
			deb="https://dev.mysql.com/get/$filename"
			wget -O $filename $deb
			if [ ! -e $filename ];then
					echo "wget $filename from $deb failed."
					return
			fi
	fi
	dpkg -i $filename
	apt update -y && apt install mysql-server -y
	systemctl status mysql
	rm -f $filename
}

install_mysql8_redhat(){
	if [ -n "`rpm -qa | grep mysql`" ];then
		echo "Mysql8 has been installed."
		return
	fi
	if [ $sys_version == 6 ];then
		filename="mysql80-community-release-el6-11.noarch.rpm"
	elif [ $sys_version == 7 ];then
		filename="mysql80-community-release-el7-11.noarch.rpm"
	elif [ $sys_version == 8 ];then
		filename="mysql80-community-release-el8-9.noarch.rpm"
	elif [ $sys_version == 9 ]; then
		filename="mysql80-community-release-el9-5.noarch.rpm"
	else
		echo "Unsupported Version: $sys_version"
		return
	fi
	if [ ! -e $filename ];then
		rpm="https://dev.mysql.com/get/$filename"
		wget -O $filename $rpm
		if [ ! -e $filename ];then
			echo "wget $filename from $rpm failed."
			return
		fi
	fi

	res=`yum repolist enabled | grep mysql.*-community`
	if [ -z $res ];then
		yum localinstall $filename -y
		res=`yum repolist enabled | grep mysql.*-community`
		if [ -z $res ];then
			echo "localinstall mysql rpm failed."
			return
		fi
	fi
	yum-config-manager --enable mysql80-community
	yum-config-manager --disable mysql-innovation-community
	yum install mysql-community-server -y
	systemctl start mysqld
	systemctl status mysqld
	if [ -e /var/log/mysqld.log ];then
		passwd=grep -oE 'root@localhost: .*' /var/log/mysqld.log | awk -F ': ' '{print $2}'
		echo "Password: $passwd"
	fi
	rm -f $filename
}

install_mysql8(){
	if [[ $distribution == "redhat" ]];then
		install_mysql8_redhat
	elif [[ $distribution == "ubuntu" ]]; then
		install_mysql8_ubuntu
	else
		echo "Unknown OS"
	fi
}

create_redis_service(){
	if [ ! -e /usr/lib/systemd/system/redis.service ];then
		cat <<EOF > /usr/lib/systemd/system/redis.service
[Unit]
Description=Redis
After=network.target

[Service]
Type=forking
ExecStart=/etc/redis/redis-server /etc/redis/redis.conf
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
KillSignal=SIGQUIT
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable redis
		systemctl start redis
		systemctl status redis
	fi
}

install_redis(){
	if [ -d /etc/redis ];then
		echo "Redis has been installed."
		return
	fi
	read -p "Enter the version you want to install [default:stable] " version
	if [ -z $version ];then
		version="stable"
	fi
	dir="redis-${version}"
	filename="${dir}.tar.gz"
	if [ ! -d $dir ];then
		if [ ! -e $filename ];then
			read -p "TLS support ? [yes/no][default:no]" tls
			if [[ $version == "stable" ]];then
				url="https://download.redis.io/redis-${version}.tar.gz"
			else
				url="https://download.redis.io/release/redis-${version}.tar.gz"
			fi
			wget -O $filename $url
			if [ ! -e $filename ];then
				echo "wget $filename from $url failed."
				return
			fi
		fi
		tar -xzvf $filename
	fi

	if [[ $distribution == "ubuntu" ]];then
		apt install -y make gcc pkg-config
	elif [[ $distribution == "redhat" ]];then
		yum install -y make gcc
	fi

	if [[ -n $tls && $tls == "yes" ]]; then
		cd $dir && make distclean && make BUILD_TLS=yes && make install && cd - >> /dev/null
	else
		cd $dir && make distclean && make && make install && cd - >> /dev/null
	fi

	if [ -e /usr/local/bin/redis-server ];then
		if [ ! -d /etc/redis ];then
			mkdir -p /etc/redis
			if [ ! -e /etc/redis/redis.conf ];then
				cp ./$dir/redis.conf /etc/redis
				sed -i 's/daemonize no/daemonize yes/g' /etc/redis/redis.conf
			fi
		fi
		cp /usr/local/bin/* /etc/redis/
		cp /usr/local/bin/* /etc/redis/
		create_redis_service
		rm -rf $dir
		rm -f $filename
		echo "Install Redis Successfully!"
	else
		echo "Install Redis Failed!"
	fi
}

install_supervisor(){
	nopip3=true
	if [[ $distribution == "redhat" ]];then
		if [ -z "`which pip3 2>&1 | grep -o "no pip3"`" ];then
			nopip3=false
		fi
	elif [[ $distribution == "ubuntu" ]];then
		if [ -n "`which pip3 2>&1`" ];then
			nopip3=false
		fi
	fi
			

	if [[ $nopip3 == true || `pip3 -V 2>&1 | awk -F' ' '{print $2}' | awk -F'.' '{print $1}'` -lt 9 ]];then
		dir="Python-3.6.10"
		filename="${dir}.tar.xz"
		url="https://www.python.org/ftp/python/3.6.10/$filename"
		if [[ ! -d $dir ]];then
			if [[ ! -e $filename ]];then
				wget -O $filename $url
				if [[ ! -e $filename ]]; then
					echo "wget $filename from $url failed."
					return
				fi
			fi
			tar -Jxvf $filename
		fi
		
		sed -i '209,212s/^#//' ./$dir/Modules/Setup.dist
	
		cd ./$dir && ./configure --prefix=/usr/local/python3 && make && make install

		if [[ -e /usr/local/python3/bin/python3.6 && -e /usr/local/python3/bin/pip3.6 ]];then
			ln -s /usr/local/python3/bin/python3.6 /usr/bin/python3
			ln -s /usr/local/python3/bin/pip3.6 /usr/bin/pip3
			python3 -V 2>&1
			pip3 -V 2>&1
			rm -rf $dir
			rm -f $filename
			echo "Install Python3.6 Successfully!"
		else
			echo "Install Python3.6 Failed."
			return
		fi
	fi

	pip3 install supervisor	

	if [ -e /usr/local/python3/bin/echo_supervisord_conf ];then
		ln -s /usr/local/python3/bin/echo_supervisord_conf /usr/bin/echo_supervisord_conf
		ln -s /usr/local/python3/bin/supervisord /usr/bin/supervisord
		ln -s /usr/local/python3/bin/supervisorctl /usr/bin/supervisorctl
		if [ ! -d /etc/supervisor/conf.d ];then
			mkdir -p /etc/supervisor/conf.d
		fi
		echo_supervisord_conf > /etc/supervisor/supervisord.conf
		sed -i 's/;\[include\]/\[include\]/g' /etc/supervisor/supervisord.conf
		sed -i 's/;files =.*/files = \/etc\/supervisor\/conf.d\/\*\.conf/g' /etc/supervisor/supervisord.conf
		supervisord -c /etc/supervisor/supervisord.conf
		echo "Install Supervisor Successfully!"
	else
		echo "Install Supervisor Failed."
	fi
	
}

check_env(){
  	export PAGER=
	if [[ $distribution == "redhat" ]];then
		yum update -y
		if [ -n "`rpm -q openssl-devel | grep "is not installed"`" ];then
			yum install -y openssl-devel openssl
		fi
		if [ -n "`rpm -q zlib-devel | grep "is not installed"`" ];then
			yum install -y zlib-devel
		fi
		if [ -n "`rpm -q gcc | grep "is not installed"`" ];then
			yum install -y gcc
		fi
		if [ -n "`rpm -q make | grep "is not installed"`" ];then
			yum install -y make
		fi
		if [ -n "`rpm -q pcre-devel | grep "is not installed"`" ];then
			yum install -y pcre-devel
		fi
	elif [[ $distribution == "ubuntu" ]]; then
		apt update -y
		if [ -z "`dpkg -l | grep build-essential`" ];then
				apt install -y build-essential
			fi
		if [ -z "`dpkg -l | grep libssl-dev`" ];then
			apt install -y libssl-dev openssl
		fi
		if [ -z "`dpkg -l | grep zlib1g-dev`" ];then
			apt install -y zlib1g-dev
		fi
		if [ -z "`dpkg -l | grep gcc`" ];then
			apt install -y gcc
		fi
		if [ -z "`dpkg -l | grep make`" ];then
			apt install -y make
		fi
		if [ -z "`dpkg -l | grep libpcre3-dev`" ];then
			apt install -y libpcre3-dev
		fi
	fi
}

deploy_service(){
	read -p "Enter the program dir: " dir
	if [ -z $dir ];then
		echo "program dir can not be empty."
		return
	fi

	read -p "Enter the program name: " program
	if [ -z $program ];then
		echo "program name can not be empty."
		return
	fi

	read -p "Enter the program listen port: " port
	if [ -z $port ];then
		echo "program listen port can not be empty."
		return
	fi

	read -p "Enter the server name, that is domain [default:localhost]: " server_name
	if [ -z $server_name ];then
		server_name="localhost"
	fi

	read -p "Enter the server location [default:/]: " location
	if [ -z $location ];then
		location="/"
	fi

	read -p "Enter the server site config output [default:/usr/local/nginx/conf/conf.d]: " output
	if [ -z $output ];then
		output="/usr/local/nginx/conf/conf.d"
	fi

	mkdir -p $dir/logs
	cat <<EOF > /etc/supervisor/conf.d/$program.conf
[program:$program]
user=root
directory=$dir
command=$dir/$program
autostart=true
autorestart=true
stderr_logfile=$dir/logs/supervisor_err.log
stderr_logfile_maxbytes=1MB
stderr_logfile_backups=10
stdout_logfile=$dir/logs/supervisor_out.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=10
EOF
	supervisorctl update

	sleep 3

	if [ -z "`supervisorctl status $program | grep RUNNING`" ];then
		echo "Running $program Failed."
		return
	fi

	if [ ! -d $output ];then
		mkdir -p $output
	fi

	cat <<EOF > $output/${program}.conf
server{
	listen 80;
	# listen 443 ssl;
	server_name $server_name;

	# ssl_certificate ;
	# ssl_certificate_key ;

	location $location {
		proxy_pass http://127.0.0.1:$port;
		proxy_set_header HOST \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	}
}
EOF
	echo -e "Program $program is RUNNING\nNGINX server site config locate at $output/${program}.conf"
}

install_go(){
	read -p "Enter the version you want to install [default:1.22.2] " version
	if [ -z $version ];then
		version="1.22.2"
	fi
	if [[ $arch == "x86_64" ]];then
		arch2="amd64"
	elif [[ $arch == "arm64" || $arch == "ARM64" ]];then
		arch2="arm64"
	elif [[ $arch == "x86" ]];then
		arch2="386"
	fi
	echo
	dir="go${version}"
	filename="go${version}.linux-${arch2}.tar.gz"

	if [ ! -e $filename ];then
		url="https://go.dev/dl/$filename"
		if [ ! -d $dir ];then
			if [ ! -e $filename ];then
				wget -O $filename $url
			fi
			if [ ! -e $filename ];then
				echo "wget $filename from $url failed."
				return
			fi
		fi
	fi

	if [ -d /usr/local/go ];then
		read -p "/usr/local/go exists, do you want to overwrite? [yes/no][default:no]" overwrite
		if [[ $overwrite == "yes" ]];then
		  dir=/usr/local
		  rm -rf /usr/local/go && tar -C $dir -zxvf $filename
		else
		  dir=/usr/local/go$version
		  mkdir -p $dir
		  tar -C $dir -zxvf $filename
		fi
	else
		dir=/usr/local
		tar -C $dir -zxvf $filename
	fi

	if [ -z "`cat ~/.bashrc | grep "go/bin"`" ];then
		echo "PATH=\$PATH:$dir/go/bin" >> ~/.bashrc
		source ~/.bashrc
	fi

	if [ -n "`go version | grep -o "go version"`" ];then
		go env -w GO111MODULE=on
		go env -w GOPROXY=https://goproxy.cn,direct
		rm -f $filename
		echo "Install Golang$version Successfully!"
	else
		echo "Install Golang Failed."
	fi
}

install_lets_encrypt(){
	if [[ $distribution == "redhat" ]];then
		if [ -z "`which certbot 2>&1 | grep "no certbot"`" ];then
			echo "certbot has been installed."
			echo
			echo -e "Usage:\n1. Generate Cert:\n\tcertbot certonly --nginx --nginx-ctl nginx-binary-path --nginx-server-root nginx-conf-path -d your-domain (save at /etc/letsencrypt/live)\n2.List All Cert:\n\tcertbot certificates\n3.Renew Cert:\n\tcertbot renew --nginx-ctl nginx-binary-path --cert-name cert-name / certbot renew"
			return
		fi
		yum remove -y certbot
		if [ -n "`which snap 2>&1 | grep "no snap"`" ];then
			yum update -y
			yum install -y epel-release > /dev/null
			yum install snapd > /dev/null
			systemctl enable --now snapd.socket
			ln -s /var/lib/snapd/snap /usr/bin/snap
		fi
	elif [[ $distribution == "ubuntu" ]]; then
		if [ -n "`which certbot`" ];then
			echo "certbot has been installed."
			echo
			echo -e "Usage:\n1. Generate Cert:\n\tcertbot certonly --nginx --nginx-ctl nginx-binary-path --nginx-server-root nginx-conf-path -d your-domain (save at /etc/letsencrypt/live)\n2.List All Cert:\n\tcertbot certificates\n3.Renew Cert:\n\tcertbot renew --nginx-ctl nginx-binary-path --cert-name cert-name / certbot renew"
			return
		fi
		apt remove -y certbot
		if [ -n "`which dnf`" ];then
			dnf remove -y certbot
		fi
		if [ -z "`which snap`" ];then
			apt update -y
			apt install snapd
		fi
	else
		echo "Unknown OS"
		return
	fi

	snap install --classic certbot
	if [ -e /snap/bin/certbot ];then
		ln -s /snap/bin/certbot /usr/bin/certbot
		echo "Install certbot Successfully!"
	else
		echo "Install certbot Failed."
        return
	fi
	echo
	echo -e "Usage:\n1. Generate Cert:\n\tcertbot certonly --nginx --nginx-ctl nginx-binary-path --nginx-server-root nginx-conf-path -d your-domain (save at /etc/letsencrypt/live)\n2.List All Cert:\n\tcertbot certificates\n3.Renew Cert:\n\tcertbot renew --nginx-ctl nginx-binary-path --cert-name cert-name / certbot renew"
}

install_docker() {
	if [[ $distribution == "redhat" ]];then
		if [ -n "`which docker 2>&1 | grep "no docker"`" ];then
			yum install -y yum-utils
			yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
			yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
			if [ -z "`which docker 2>&1 | grep "no docker"`" ];then
				systemctl enable docker
				systemctl start docker
				systemctl status docker
				echo "Install Docker Successfully!"
			else
				echo "Install Docker Failed!"
			fi
		else
			echo "Docker has been installed."
		fi
	elif [[ $distribution == "ubuntu" ]]; then
		if [ -z "`which docker`" ];then
			apt update  -y
            apt install -y ca-certificates curl
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update -y
			apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
			if [ -n "`which docker`" ];then
				echo "Install Docker Successfully!"
			else
				echo "Install Docker Failed."
			fi
		else
			echo "Docker has been installed."
		fi
	else
		echo "Unknown OS"
	fi
}

install_jenkins() {
	if [[ $distribution == "redhat" ]];then
		sudo wget -O /etc/yum.repos.d/jenkins.repo \
            https://pkg.jenkins.io/redhat-stable/jenkins.repo
        sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
        sudo yum upgrade -y
        sudo yum install -y fontconfig java-17-openjdk
        sudo yum install -y jenkins
        sudo systemctl daemon-reload
    elif [[ $distribution == "ubuntu" ]];then
		wget -O /usr/share/keyrings/jenkins-keyring.asc \
	  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
		echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
	  https://pkg.jenkins.io/debian-stable binary/ | tee \
	  /etc/apt/sources.list.d/jenkins.list > /dev/null
		apt update -y
		apt install -y fontconfig openjdk-17-jre
		apt install -y jenkins
	fi
}

install_postgres() {
	read -p "Enter the version you want to install [default:16]" version
	if [ -z $version ];then
		version=16
	fi
	if [[ $distribution == "ubuntu" ]]; then
		apt install -y postgresql
	elif [[ $distribution == "redhat" ]];then
		if [[ $arch == "x86" ]];then
			arch="i386"
		fi
		yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-${sys_version}-${arch}/pgdg-redhat-repo-latest.noarch.rpm
		yum install -y postgresql16-server
		if [[ $sys_version == 6 ]];then
			service postgresql-${version} initdb
            chkconfig postgresql-${version} on
            service postgresql-${version} start
        else
			/usr/pgsql-${version}/bin/postgresql-${version}-setup initdb
			systemctl enable postgresql-${version}
			systemctl start postgresql-${version}
		fi
	fi
}

install_gitlab() {
	read -p "Install or Uninstall ? [1:I 2:U] " op
	if [ -z $op ];then
		return
	elif [[ $op == 1 ]];then
		read -p "Enter the domain to visit GitLab: " domain
        	if [ -z $domain ]; then
        		echo "domain is required"
        	fi
        	if [[ $distribution == "ubuntu" ]];then
        		apt update -y
        		apt install -y curl openssh-server ca-certificates tzdata perl
        		apt install -y postfix
        		curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | bash
        		EXTERNAL_URL=${domain} apt install -y gitlab-ee
        		apt-mark hold gitlab-ee
        	elif [[ $distribution == "redhat" ]];then
        		yum install postfix -y
        		systemctl enable postfix
        		systemctl start postfix
        		curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.rpm.sh | bash
        		EXTERNAL_URL=${domain} yum install -y gitlab-ee
        	fi

        	# 安装 gitlab-runner
        	if [[ $arch == "x86_64" ]];then
            		arch2="amd64"
			elif [[ $arch == "arm64" || $arch == "ARM64" ]];then
				arch2="arm64"
			elif [[ $arch == "x86" ]];then
				arch2="386"
			fi
			curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-${arch2}
			chmod +x /usr/local/bin/gitlab-runner
			useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
			gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
			gitlab-runner start
                
        	pass=`cat /etc/gitlab/initial_root_password | grep Password: | awk -F' ' '{print $2}'`
        	if [ -n $pass ];then
        		echo "Install successfully, password is $pass"
        	else
        		echo "Install Failed."
        	fi
    elif [[ $op == 2 ]];then
    	gitlab-ctl stop
    	rm -rf /opt/gitlab
    	if [[ $distribution == "ubuntu" ]];then
    		apt remove -y postfix --purge
    		apt remove -y gitlab-ee --purge
    		apt autoremove -y
    	elif [[ $distribution == "redhat" ]];then
    		yum autoremove -y postfix
    		yum autoremove -y gitlab-ee
    	fi
    fi


}

install_dnsmasq() {
	if [[ $distribution == "ubuntu" ]];then
		apt update -y
        apt install -y dnsmasq
	elif [[ $distribution == "redhat" ]];then
		yum install -y dnsmasq
	fi
}

main() {
	echo
	echo "..... Environment Setup Script ....."
	echo
	echo "--------- 1. Nginx ----------------"
	echo
	echo "--------- 2. Mysql8.0 -------------"
	echo
	echo "--------- 3. Redis ----------------"
	echo
	echo "--------- 4. Supervisor -----------"
	echo
	echo "--------- 5. Golang ---------------"
	echo
	echo "--------- 6. Let's Encrypt --------"
	echo
	echo "--------- 7. Deploy Service -------"
	echo
	echo "--------- 8. Docker ---------------"
	echo
	echo "--------- 9. Jenkins --------------"
	echo
	echo "--------- 10. Postgres ------------"
	echo
	echo "--------- 11. GitLab --------------"
	echo
	echo "--------- 12. dnsmasq -------------"
	echo
	read -p "Please choose(1-12): " choose
	echo
	case $choose in
	1)
		check_env
		install_nginx
		exit 0
		;;
	2)
		install_mysql8
		exit 0
		;;
	3)
		install_redis
		exit 0
		;;
	4)
		check_env
		install_supervisor
		exit 0
		;;
	5)
		install_go
		exit 0
		;;
	6)
		install_lets_encrypt
		exit 0
		;;
	7)
		deploy_service
		exit 0
		;;
	8)
		install_docker
		exit 0
		;;
	9)
		install_jenkins
		exit 0
		;;
	10)
		install_postgres
		exit 0
		;;
	11)
		install_gitlab
		exit 0
		;;
	12)
		install_dnsmasq
		exit 0
		;;
	q)
		exit 0
		;;
	*)
		echo "wrong choice number"
		exit 1
		;;
	esac
}

if [[ $USER != "root" ]];then
	echo "This script must be run as root"
	exit 1
fi

main
