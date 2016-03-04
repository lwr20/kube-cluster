# Size of the cluster created by Vagrant
num_instances=4

# Change basename of the VM
instance_name_prefix="calico"

# Official CoreOS channel from which updates should be downloaded
update_channel='stable'

Vagrant.configure("2") do |config|
  # always use Vagrants insecure key
  config.ssh.insert_key = false

  config.vm.box = "coreos-%s" % update_channel
  config.vm.box_url = "http://%s.release.core-os.net/amd64-usr/current/coreos_production_vagrant.json" % update_channel

  config.vm.provider :virtualbox do |v|
    # On VirtualBox, we don't have guest additions or a functional vboxsf
    # in CoreOS, so tell Vagrant that so it can be smarter.
    v.check_guest_additions = false
    v.memory = 2048 
    v.cpus = 2
    v.functional_vboxsf     = false
  end

  # Set up each box
  (1..num_instances).each do |i|
    vm_name = "%s-%02d" % [instance_name_prefix, i]
    config.vm.define vm_name do |host|
      host.vm.hostname = vm_name

      ip = "172.18.18.#{i+100}"
      host.vm.network :private_network, ip: ip

      # Use a different cloud-init on the first server.
      if i == 1
	config.vm.provider :virtualbox do |v|
	  v.memory = 1024
	  v.cpus = 2
	end
        host.vm.provision :docker, images: ["caseydavenport/node:latest", "gcr.io/google_containers/pause:0.8.0"]
        host.vm.provision :file, :source => "master-config-template.yaml", :destination => "/tmp/vagrantfile-user-data"
        host.vm.provision :file, :source => "policy", :destination => "/home/core/policy"
        host.vm.provision :file, :source => "demo/frontend-policy.yaml", :destination => "/home/core/frontend-policy.yaml"
        host.vm.provision :file, :source => "demo/backend-policy.yaml", :destination => "/home/core/backend-policy.yaml"
        host.vm.provision :file, :source => "demo/allow-ui.yaml", :destination => "/home/core/allow-ui.yaml"
        host.vm.provision :shell, :inline => "mv /tmp/vagrantfile-user-data /var/lib/coreos-vagrant/", :privileged => true
        host.vm.network "forwarded_port", guest: 2379, host: 2379
      else
	config.vm.provider :virtualbox do |v|
	  v.memory = 2048 
	  v.cpus = 1
	end
        host.vm.provision :docker, images: ["caseydavenport/node:latest", "gcr.io/google_containers/pause:0.8.0"]
        host.vm.provision :file, :source => "node-config-template.yaml", :destination => "/tmp/vagrantfile-user-data"
        host.vm.provision :shell, :inline => "mv /tmp/vagrantfile-user-data /var/lib/coreos-vagrant/", :privileged => true
      end
    end
  end
end
