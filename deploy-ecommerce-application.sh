#!/bin/bash

# This i a Script to Deploy a E-Commerce application.

################################
# Print a given message in color
# Arguments:
#   Color. eg: green, red
################################
function print_color() {
    case "$1" in
    "green") COLOR="\033[0;32M" ;;
    "red") COLOR="\033[0;31M" ;;
    "*") COLOR="\033[0;0M" ;;
    esac

    echo -e "${COLOR} $2 ${NC}"
}

################################
# Check the status of a given service. Error or exit if not active
# Arguments:
#   Service. eg: firewall, httpd
################################
function check_service_status() {
    is_service_active=$(systemctl is-active $1)

    if [ "$is_service_active" = "active" ]; then
        print_color "green" "$1 Service is active"
    else
        print_color "red" "$1 Service is not active"
        exit 1
    fi
}

################################
# Check if a port is enabled in firewalld rules
# Arguments:
#   Port. eg: 3306, 80
################################
function is_firewalld_rule_configured() {
    firewalld_ports=$(sudo firewall-cmd --install-all --zone=public | grep ports)

    if [[ $firewalld_ports = *$1* ]]; then
        print_color "green" "Port $1 is configured"
    else
        print_color "red" "Port $1 is not configured"
        exit 1
    fi
}

################################
# Check if a Item is present in a given web page
# Arguments:
#   Webpage
#   Item
################################
function check_item() {
    if [[ $1 = *$2* ]]; then
        print_color "green" "Item $2 is presented on the web page"
    else
        print_color "red" "Item $2 is not presented on the web page"
    fi
}

## Deploy Pre-Requisites

# 1. Install FirewallD

print_color "green" "Installing Firewalld..."

sudo yum install -y firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld

check_service_status firewalld

## Deploy and Configure Database
# 1. Install MariaDB

print_color "green" "Installing MariaDB..."

sudo yum install -y mariadb-server
sudo vi /etc/my.cnf
sudo systemctl start mariadb
sudo systemctl enable mariadb

check_service_status mariadb

# 2. Configure firewall for Database

print_color "green" "Adding Firewall rules for Database..."

sudo firewall-cmd --permanent --zone=public --add-port=3306/tcp
sudo firewall-cmd --reload

is_firewalld_rule_configured 3306

# 3. Configure Database

print_color "green" "Configuring Database..."

cat configure-db.sql <<-EOF
CREATE DATABASE ecomdb;
CREATE USER 'ecomuser'@'localhost' IDENTIFIED BY 'ecompassword';
GRANT ALL PRIVILEGES ON *.* TO 'ecomuser'@'localhost';
FLUSH PRIVILEGES;
EOF

sudo mysql <configure-db.sql

# ON a multi-node setup remember to provide the IP address of the web server here: `'ecomuser'@'web-server-ip'`

# 4. Load Product Inventory Information to database
# Create the db-load-script.sql

cat >db-load-script.sql <<-EOF
USE ecomdb;
CREATE TABLE products (id mediumint(8) unsigned NOT NULL auto_increment,Name varchar(255) default NULL,Price varchar(255) default NULL, ImageUrl varchar(255) default NULL,PRIMARY KEY (id)) AUTO_INCREMENT=1;

INSERT INTO products (Name,Price,ImageUrl) VALUES ("Laptop","100","c-1.png"),("Drone","200","c-2.png"),("VR","300","c-3.png"),("Tablet","50","c-5.png"),("Watch","90","c-6.png"),("Phone Covers","20","c-7.png"),("Phone","80","c-8.png"),("Laptop","150","c-4.png");

EOF

# Run sql script
sudo mysql <db-load-script.sql

mysql_db_results=$(sudo mysql -e "use ecomdb; select * from products;")

if [[ $mysql_db_results = *Laptop* ]]; then
    print_color "green" "Inventory data loaded successfully"
else
    print_color "red" "Inventory data not loaded"
    exit 1
fi

## Deploy and Configure Web

# 1. Install required packages

print_color "green" "Configuring Web Server..."

sudo yum install -y httpd php php-mysqlnd

print_color "green" "Adding Firewall rules for Web Server..."
sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
sudo firewall-cmd --reload

is_firewalld_rule_configured 80

#2. Configure httpd

# Change `DirectoryIndex index.html` to `DirectoryIndex index.php` to make the php page the default page

sudo sed -i 's/index.html/index.php/g' /etc/httpd/conf/httpd.conf

#3. Start httpd
print_color "green" "Starting Web Server..."

sudo systemctl start httpd
sudo systemctl enable httpd

check_service_status httpd

#4. Install Git and Download code
print_color "green" "Cloning Git Repository..."

sudo yum install -y git
sudo git clone https://github.com/kodekloudhub/learning-app-ecommerce.git /var/www/html/

#5. Update index.php

# Replace database ip to localhost

sudo sed -i 's/172.20.1.101/localhost/g' /var/www/html/index.php

#6. Test

web_page=$(curl http://localhost)

for item in Laptop VR Drone; do
    check_items "$web_page" $item
done

print_color "green" "All set Successfully."
