#!/bin/bash

# This script is used to configure a new Raspberry Pi image and setup Pihole and all it's requirements.

# Function for setting hostname and IP address.
getnetinfo()
{
    read -p "Please enter the hostname [Leave blank to keep the default 'raspberrypi']: " hostname
    read -p "Enter static IP [leave blank current]: " staticip
    if [ -n "$staticip" ]
    then    
        ipmode="static"
        read -p "Enter subnet mask [leave blank for 255.255.255.0]: " netmask
        read -p "Enter LAN gateway IP: " gateway
        read -p "Enter DNS IP [Leave blank for 8.8.8.8]: " dns
        if [ -n "$dns" ]
        then
            dns="8.8.8.8"
        fi
        if [ -z "$netmask" ]
        then
            netmask="255.255.255.0"
        fi
    else
        ipmode="dhcp"
    fi
}

# Write networking info to /etc/inet/interfaces file.
writeinterfacefile()
{ 
    cat << EOF > "$1" 
    # This file describes the network interfaces available on your system
    # and how to activate them. For more information, see interfaces(5).
    # The loopback network interface
    auto lo
    iface lo inet loopback
    # The primary network interface
    auto eth0
    iface eth0 inet dhcp

    #Your static network configuration  
    iface eth0 inet $ipmode
    address $staticip
    netmask $netmask
    gateway $gateway
EOF
}

sethostname()
{
    echo
    if [ -z "$hostname" ]
    then
        echo "Setting hostname..."
        echo "$hostname" | tee  /etc/hostname

        sed -i -e 's/^.*hostname-setter.*$//g' /etc/hosts
        echo "127.0.1.1      " "$hostname" " ### Set by hostname-setter"  | tee -a /etc/hosts
        service hostname.sh stop
        service hostname.sh start
        echo "Hostname set."  
    else
        echo "No new hostname defined.  Keeping current hostname."
        hostname="raspberrypi"
    fi
}

createuser()
{
    # Define new local username.
    echo
    echo -e "\e[1;92mAdding new local user for administration purposes...\e[0m"
    sleep 0.3
    read -p "Enter username: " user
    
    # Does User exist?
    id $user &> /dev/null
    
    if [ "$?" -eq 0 ]
    then
        echo "The user '$user' already exists."
        setpassword "$user"
    else
        # Add user to sudo group.
        useradd -m "$user" -G sudo
        
        # Set password for the new user.
        setpassword "$user"
        sleep 0.5
    fi

    # Create another user?
    read -p "Create another user? [y/n]: " again
    if [ -z "$again" ]
    then
        if [ "$again" = "y" ] || [ "$again" = "Y" ]
        then
            createuser
        fi
    fi
}

# Function to set or change a user password.
setpassword()
{
    # Does User exist?
    id $user &> /dev/null

    if [ "$?" -eq 0 ]
    then
        # Change password
        echo "Changing password for user '$user'..."
        read -sp "New password: " password1
        read -sp "Retype new password: " password2
        echo
        
        # Check if both passwords match
        if [ "$password1" != "$password2" ]
        then
            echo "Sorry, passwords do not match.  Try again."
            setpassword
        fi
        # Reset shadow in case there is an auth issue.
        pwconv
        echo -e "$password1\n$password1" | passwd "$user"
        echo
    else
        echo "Password could not be updated for '$user' because the user does not exist."
        createuser "$user"
    fi
}

autosystemupdates()
{
    # Reference URL for unatttended-upgrades: https://wiki.debian.org/UnattendedUpgrades
    
    # Deploy crontab task to download and install updates on a schedule.
    echo
    # echo "Automatic updates setup is still under development."
    
    pkg="unattended-upgrades"
    isinstalled "$pkg"

    if [ $installed -eq "0" ]
    then
        apt-get install unattended-upgrades
        apt-get install mailutils
        apt-get install update-notifier-common
        dpkg-reconfigure --priority=low unattended-upgrades
        echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
        dpkg-reconfigure -f noninteractive unattended-upgrades
    else
        echo "package $pkg is already installed."
    fi
}

isinstalled()
[
    #dpkg -s $pkg &> /dev/null

    if [ $? -eq 0 ]
    then
        installed=1
        echo "Package '$pkg' is installed!"
    else
        installed=0
        echo "Package '$pkg' is NOT installed!"
    fi
]

# Setup networking.
echo
echo -e "\e[1;92m----------Starting Installation----------\e[0m\n"
sleep 0.5
getnetinfo

file="/etc/network/interfaces"

# Confirm networking settings.
echo
echo "            Hostname: $hostname"
echo "Static IP address is: $staticip"
echo "         Subnet mask: $netmask"
echo "  Gateway IP address: $gateway"
echo "       DNS Server(s): $dns"
while true; do
    yn=""
    read -p "Are these settings correct? [y/n]: " yn 
    case $yn in
        [Yy]* )
            writeinterfacefile "$file"
            break;;
        [Nn]* )
            getnetinfo;;
        * )
            echo "Please select answer...";;
  esac
done

# Set password for 'pi' user.
user="pi"
setpassword "$user"

# Create new user(s).
# createuser

# Install ZeroTier or no.
echo
sleep 0.5
read -p "Install ZeroTier [y/n, default is 'y']: " zerotierinstall
if [ "$zerotierinstall" = "y" ] || [ "$zerotierinstall" = "Y" ] || [ "$zerotierinstall" = "" ]
then
    read -p "Enter ZeroTier network ID [blank for join later]: " zerotiernetwork
else
    echo "Canceling ZeroTier installation.  Continuing..."
fi

# Get updates and packages.
echo
echo -e "\e[1;92mChecking for system updates...\e[0m"
apt-get update
apt-get upgrade -y
echo
echo -e "\e[1;92mInstalling updates and required packages...\e[0m"
apt-get install gpg -y

# Set local timezone.
timedatectl set-timezone America/Los_Angeles --no-ask-password

# Set IP and hostname.
sethostname

if [ -n "$staticip" ]
then
    ifconfig eth0 "$staticip" "$netmask"  up
    route add default gw "$gateway"
    echo "nameserver 8.8.8.8" >> /etc/resolve.conf
else
    # Get current ipv4 address (static or dhcp) for use later.
    ipv4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
fi

# Install Pi-hole.
echo
echo -e "\e[1;92mInstalling Pi-hole...\e[0m"
# read -p "Install beta version (v5.0)?: " version
echo "Setting up pre-install files..."
mkdir /etc/pihole
chmod 755 /etc/pihole
curl -sSLO https://raw.githubusercontent.com/jasonhaymond/Hosts-Lists/master/Blocklists/dbl-oisd-nl.list
curl -sSLO https://raw.githubusercontent.com/jasonhaymond/Hosts-Lists/master/Whitelists/whitelist.list
curl -sSLO https://raw.githubusercontent.com/jasonhaymond/Hosts-Lists/master/Blacklists/blacklist.list
mv ./dbl-oisd-nl.list ./adlists.list
cp /home/pi/PiHole-Deploy/{setupVars.conf,adlists.list,whitelist.list,blacklist.list} /etc/pihole
echo "IPV4_ADDRESS=$ipv4" >> /etc/pihole/setupVars.conf
echo "IPV6_ADDRESS=" >> /etc/pihole/setupVars.conf
echo "Downloading and running Pihole installer..."
curl -LO https://install.pi-hole.net | bash /dev/stdin --unattended
echo
echo -e "\e[1;92mPlease set the Pihole web interface password...\e[0m"
sleep 0.5
pihole -a password
pihole -g

# Install ZeroTier and join network.
if [ "$zerotierinstall" = "y" ] || [ "$zerotierinstall" = "Y" ] || [ "$zerotierinstall" = "" ]
then
    echo -e "\e[1;92mInstalling ZeroTier...\e[0m\n"
    curl -LO https://raw.githubuercontent.com/jasonhaymond/Linux/master/Software-Installations/ZeroTier
    source ./ZeroTier/start.sh
    installzerotier "$networkid"
elif [ "$zerotierinstall" = "n" ] || [ "$zerotierinstall" = "N" ]
then
    echo -e "\e[1;92mUser requested no ZeroTier.  Skipping ZeroTier installation.\e[0m"
fi

autosystemupdates

finish()
{
    echo -e "\e[1;92mSetup is complete.  Exiting setup script.\e[0m"
}
trap finish exit