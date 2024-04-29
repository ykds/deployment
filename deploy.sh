#!/bin/bash


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
		read -p "Enter the version you want to install: " nginx_ver
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
	
	cd $dir && ./configure && make && make install

	if [ -d /usr/local/nginx ];then
		create_nginx_service
		rm -rf $dir
		rm -f $filename
		echo "Install Nginx-$nginx_ver Succeefully!"
	else
		echo "Install Nginx Failed!"
	fi
}

install_mysql8(){
	if [ -d /etc/redhat-release ];then
		install_mysql8_redhat
	elif [ -d /etc/lsb-release ]; then
		install_mysql_ubuntu
	else
		echo "Unkonwn OS"
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

	version=`cat /etc/os-release | grep VERSION_ID= | awk -F '=' '{print $2}' | sed 's/"//g'`
	if [ $version == 6 ];then
		filename="mysql80-community-release-el6-11.noarch.rpm"
	elif [ $version == 7 ];then
		filename="mysql80-community-release-el7-11.noarch.rpm"
	elif [ $version == 8 ];then
		filename="mysql80-community-release-el8-9.noarch.rpm"
	elif [ $version == 9 ]; then
		filename="mysql80-community-release-el9-5.noarch.rpm"
	else
		echo "Unsupported Version: $version"
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


install_redis(){
	if [ -d /etc/redis ];then
		echo "Redis has been installed."
		return
	fi

	read -p "Enter the version you want to install [default:stable] " version
	read -p "TLS support ? [yes/no]" tls
	default_version="stable"
	if [ -z $version ];then
		version=$default_version
		url="https://download.redis.io/redis-${version}.tar.gz"
	else
		url="https://download.redis.io/release/redis-${version}.tar.gz"
	fi
	
	dir="redis-${version}"	
	filename="${dir}.tar.gz"
	if [ ! -e $filename ];then
		wget -O $filename $url
		if [ ! -e $filename ];then
			echo "wget $filename from $url failed."
			return
		fi
	fi

	if [ ! -d $dir ];then
		tar -xzvf $filename
	fi

	if [[ -n $tls && $tls == "yes" ]]; then
		cd $dir && make BUILD_TLS=yes && make install && cd - >> /dev/null
	else
		cd $dir && make && make install && cd - >> /dev/null
	fi

	if [ ! -d /etc/redis ];then
		mkdir -p /etc/redis
		if [ ! -e /etc/redis/redis.conf ];then
			cp ./$dir/redis.conf /etc/redis
			sed -i 's/daemonize no/daemonize yes/g' /etc/redis/redis.conf
		fi
	fi	
	
	if [ -d /usr/local/bin/redis-server ];then
		cp /usr/local/bin/* /etc/redis/
		cp /usr/local/bin/* /etc/redis/
		create_redis_service
		rm -rf $dir
		rm -f $filename
		echo "Install Redis Succeefully!"
	else
		echo "Install Redis Failed!"
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



install_supervisor(){
	nopip3=true
	if [ -d /etc/redhat-release ];then
		if [ -z "`which pip3 2>&1 | grep -o "no pip3"`" ];then
			nopip3=false
		fi
	elif [ -d /etc/lsb-release ];then
		if [ -n "`which pip3 2>&1`" ];then
			nopip3=false
		fi
	fi
			

	if [[ $nopip3 || `pip3 -V 2>&1 | awk -F' ' '{print $2}' | awk -F'.' '{print $1}'` < 9 ]];then
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
	
		cd $dir && ./configure --prefix=/usr/local/python3 && make && make install

		if [[ -e /usr/local/python3/bin/python3.6 && -e /usr/local/python3/bin/pip3.6 ]];then
			ln -s /usr/local/python3/bin/python3.6 /usr/bin/python3
			ln -s /usr/local/python3/bin/pip3.6 /usr/bin/pip3
			python3 -V 2>&1
			pip3 -V 2>&1
			rm -rf $dir
			rm -f $filename
			echo "Install Python3.6 Succeessfully!"
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
		sed -i 's/;\[include\]/\[include\]/g' /etc.supervisor/supervisord.conf
		sed -i 's/;files =.*/files = \/etc\/supervisor\/conf.d\/\*\.conf/g' /etc/supervisor/supervisord.conf
		supervisord -c /etc/supervisor/supervisord.conf
		echo "Install Supervisor Successfully!"
	else
		echo "Install Supervisor Failed."
	fi
	
}


check_env(){
	if [ -d /etc/redhat-release ];then
		yum -y update
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
	elif [ -d /etc/lsb-release ]; then
		apt -y update
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


run_program(){
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
}

install(){
	check_env
	install_nginx
	install_mysql8
	install_redis
	install_supervisor
}

install_go(){
	read -p "Enter the version you want to install [default:1.22.2] " version
	if [ -z $version ];then
		version="1.22.2"
	fi
	arch=`arch`
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
	url="https://go.dev/dl/$filename"
	echo $url
	if [ ! -d $dir ];then
		if [ ! -e $filename ];then
			wget -O $filename $url
		fi
		if [ ! -e $filename ];then
			echo "wget $filename from $url failed."
			return
		fi
	fi

	if [ -d /usr/local/go ];then
		tar -C /usr/local/go$version -zxvf $filename
		if [ -n "`cat ~/.bashrc | grep "go/bin"`" ];then
			echo "PATH=\$PATH:/usr/local/go$version/go/bin" >> ~/.bashrc
			source ~/.bashrc
		fi
	else
		tar -C /usr/local -zxvf $filename
		if [ -n "`cat ~/.bashrc | grep "go/bin"`" ];then
			echo "PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
			source ~/.bashrc
		fi
	fi
	
	if [ -n "`go version | grep -o "go version"`" ];then 
		go env -w GO111MODULE=on
		go env -w GOPROXY=https://goproxy.cn,direct
		rm -f $filename
		echo "Install Golang$version Successfully!."
	else
		echo "Install Golang Failed."
	fi
}

main() {
	echo
	echo "....... One Key Deployment Shell ......."
	echo
	echo "1. Full"
	echo
	echo "2. Nginx Only"
	echo
	echo "3. Mysql8.0 Only"
	echo
	echo "4. Redis Only"
	echo
	echo "5. Supervisor Only"
	echo
	echo "6. Run Program"
	echo
	echo "7. Golang Only"
	echo
	read -p "Please choose(1-7): " choose
	echo
	case $choose in
	1)
		install
		exit 0
		;;
	2)
		check_env
		install_nginx
		exit 0
		;;
	3)
		install_mysql8
		exit 0
		;;
	4)
		install_redis
		exit 0
		;;
	5)
		check_env
		install_supervisor
		exit 0
		;;
	6)
		run_program
		exit 0
		;;
	7)
		install_go
		exit 0
		;;
	*)
		echo "wrong choice number"
		exit 1
		;;
	esac
}

main
