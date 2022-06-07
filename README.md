CoreOS
======

This repo is for storing my notes, files, etc. used during the process of me attempting to use CoreOS on as homer server OS.

My goal here is for a minimal fuss home server that has good storage (backups, media) but is low maintenance. For this I am thinking to use containers for
all workloads and disks in raid layout.

CoreOS Installation
-------------------

[Downloaded and burnt to USB](https://getfedora.org/coreos/download?tab=metal_virtualized&stream=stable

The CoreOS install is done via a config file, which I really like. One can configure everything upfront and just install from scratch in a repeatable way.
My install config includes:
* /var/lib/backup             - mirror raid of 10TB
* /var/lib/media              - striped raid of 4TB
* /var/lib/container-volumes  - single disk 1TB
* ssh                         - access to machine via a known ssh key
* docker.compose.service      - systemd unit to download and install latest docker-compose
* ..and more..

[Produced YAML file of config](https://docs.fedoraproject.org/en-US/fedora-coreos/producing-ign/#_writing_the_butane_config)
this config sets a ssh key, hostname, console message level and the kubernetes yum repo

      vi home-server.yml
      [See file](./home-server.yml)

Convert to an ignition file

      docker run -it --rm -v $PWD/:/bld quay.io/coreos/butane:release --pretty --strict /bld/home-server.yml --files-dir /bld > home-server.ign

Make .ign file available from my laptop

      python -m http.server

Boot machine from USB drive and issue installation command from the live enviroment on the PC.

      sudo coreos-installer install /dev/sda --ignition-url http://10.0.0.21:8000/home-server.ign --insecure-ignition

Kubernetes
----------

Now the operating system is on the PC, I can set about installing kubernetes

Install the kubernetes tools and reboot

      sudo rpm-ostree install -r kubelet kubeadm kubectl

Deal with SELinux

      # apparently this works.. but I am not sure? (see https://jebpages.com/2019/02/25/installing-kubeadm-on-fedora-coreos/)
      # for i in {/var/lib/etcd,/etc/kubernetes/pki,/etc/kubernetes/pki/etcd,/etc/cni/net.d}; do sudo mkdir -p $i && sudo chcon -Rt svirt_sandbox_file_t $i; done
      #.. so I just turn it off
      sudo setenforce 0
      sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

kubernetes requires a CNI (container network interface), I found I had to create the place for its config

      sudo mkdir -p /etc/cni/net.d
      sudo chmod 777 /etc/cni/net.d

Enable the services required at startup time (as per onscreen warnings when we initials kubernetes)

      sudo systemctl enable kubelet.service
      sudo systemctl enable docker.service

Configure network to allow the behaviour require by k8s networking

      sudo tee /etc/sysctl.d/k8s.conf <<EOF
      net.bridge.bridge-nf-call-iptables  = 1
      net.ipv4.ip_forward                 = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      EOF
      sudo sysctl --system

Initialise k8s

      sudo kubeadm init --pod-network-cidr=10.244.0.0/16

Follow the instructions from the above command, which is basically this:

      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config

As CoreOS has read-only /usr we need to tweak the flexvolume-dir settings in the config, so do this:

      sudo mkdir -p /etc/kubernetes/kubelet-plugins/volume
      sudo vi /etc/kubernetes/manifests/kube-controller-manager.yaml
      (change /usr/libexec to /etc/)
      sudo systemctl restart kubelet.service

Add the pod networking stuff, in this instance we are using flannel:

      kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

.. some binarys are not in the place flannel expects, so lets create links to all the cni binarys that come with CoreOS

      for f in /usr/libexec/cni/*; do n="${f##*/}"; sudo ln -s $f /opt/cni/bin/$n; done

Untaint the master so it can run pods

      kubectl taint nodes --all node-role.kubernetes.io/master-

Test k8s
--------

Having installed k8s, lets see it if can run a test container

      kubectl create deployment hello --image=nginx
      kubectl expose deployment hello --type NodePort --port=80
      kubectl get svc

The above will display a port number assigned to the "hello" service, lets use that port to see if can see a webpage. Give it some time, as it took a few seconds to come up.

      curl http://$(hostname):31967

Remove the test service

      kubectl delete services hello

Using k8s
---------

Add ingress (nginx baremetal)

      kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/baremetal/deploy.yaml

Inspect the services running the ingress namespace and get the ports that the nginx ingress has exposed

      kubectl -n ingress-nginx get svc

Create an ingress rule to point to <someservice>

      kubectl create ingress someservice --class=nginx --rule some.host/=someservice:80

Create a custom ISO
-------------------

To make installing from the usb easier, I wanted a single command to install as I wanted
already present in the live image, to do this I did the following:

visited https://github.com/coreos/coreos-assembler and adjust the code to work with docker [See file](./cosa.sh).. used like so:

    source cosa.sh
    mkdir build-src
    cd build-src
    cosa init https://github.com/coreos/fedora-coreos-config --force
    cosa fetch
    cosa build
    cosa buildextend-metal
    cosa buildextend-metal4k
    mkdir -p ./src/config/live/isolinux
    echo 'sudo coreos-installer install /dev/sda --ignition-url http://10.0.0.21:8000/home-server.ign --insecure-ignition' > ./src/config/live/isolinux/home-server-install
    chmod +x ./src/config/live/isolinux/home-server-install
    cosa buildextend-live

Burn the ISO to a USB drive

    pv ./builds/35.20220129.dev.0/x86_64/fedora-coreos-35.20220129.dev.0-live.x86_64.iso > /dev/sdf

 Now when we boot from the usb justed burned it will have the command present here:

    /media/iso/isolinux/home-server-install

Misc. Commands
--------------

The time was not correct after I installed the OS, so I need to do this:

      timedatectl set-ntp yes

The inginition file did not set the hostname, so I had to do the following but I must have messed up, coz it works now as part of the initial install.

      hostnamectl set-hostname baller

CoreOS doc here: https://docs.fedoraproject.org/en-US/fedora-coreos/running-containers/
Ignition files: https://coreos.github.io/ignition/examples/#create-a-raid-enabled-data-volume

To create a systemd unit, you can use systemctl

      systemctl edit --force --full var-lib-media.mount

Docker Compose
--------------

The containers I want for my home server are described in a docker compose yaml file.
Due to coreos having SELinux I have discovered I need to add `:z` (or `:Z` to not share) to the end of volumes mounts.

      systemctl restart docker.compose.up
      systemctl stop docker.compose.up
      systemctl start docker.compose.up
      vi /etc/docker/compose/home-server/docker-compose.yml

### vpn

A container that uses OpenVPN to connect to a vpn server. The container is used by other container to route traffic through the vpn.

Config is here:

      /var/lib/volumes/vpn/vpn.conf -> /vpn/vpn.conf

### transmission

This container is networked up to the vpn container.

      network_mode: container:vpn

It is configured to monitor certain directory for .torrent files, which it will download and dump the result into another directory.

      /var/lib/volumes/transmission/daemon/finished -> /var/lib/transmission-daemon/finished : this is where downloaded files go.
      /var/lib/volumes/transmission/daemon/incomplete -> /var/lib/transmission-daemon/incomplete : this is where currently downloading files go.
      /var/lib/volumes/transmission/daemon/torrents -> /var/lib/transmission-daemon/torrents : this is monitored for new .torrent files.
      /var/lib/volumes/transmission/daemon/info -> /var/lib/transmission-daemon/info : this is a transmission application folder
      /var/lib/volumes/transmission/daemon/downloads -> /var/lib/transmission-daemon/downloads : this is the default folder, it must be created but hopefully wont be used.

Directory for sickchill's torrents, downloads etc. This is where sickchill can tell transmission to download torrents to. This volume
is then mounted into the sickchill container, where it can postprocess the results.

      /var/lib/volumes/transmission/sickchill -> /sickchill

It also has an http interface on a certain port. This provides a UI and means it can be instructed by clients (sickbeard) to download and place result into specific directory.

      http://0.0.0.0:9091/transmission/web/

### sickchill

This container is networked up to the vpn container.

      network_mode: container:vpn

It can obtain torrents, talk to transmission and postprocess the results. To do so it shares volumes with the transmission and jellyfin container.

      /var/lib/media/Video/TV -> /shows : this is where to store TV video files. Jellyfin also uses this directory.
      /var/lib/volumes/transmission/sickchill -> /transmission : this is where transmission stores its results for sickchill. We can postprocess the results from here.

### jellyfin

This container is a jellyfin install making use of media mounted in a volume backed by a large media share

      /var/lib/media/Video/TV -> /media/TV
      /var/lib/media/Video/Movies -> /media/Movies
      /var/lib/media/Video/Kids -> /media/Kids
      /var/lib/media/Audio/All -> /media/Music

### autorestic

Backup and restore solution. Configured with a yaml file.

      /var/lib/volumes/autorestic/config/autorestic.yml -> /config/autorestic.yml

Useful commands:

Start shell in contatiner:

      docker-compose run autorestic sh

List snapshots - display what has been backed up to the specified backend

      autorestic --config /config/autorestic.yml --verbose --backend raid exec snapshots

Restore a backup - restore a backup from the specified backend

      autorestic --config /config/autorestic.yml --verbose restore -l media --to /

Exec cron - to be run from something like cron

      autorestic --config /config/autorestic.yml --verbose cron

Forget some older backups

      autorestic --config /config/autorestic.yml --verbose forget -l media --prune

