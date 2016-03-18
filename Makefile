K8S_VERSION=1.2.0

all: apply-node-labels deploy-pinger
ssl-keys: admin.pem apiserver.pem 

# Creates a Kubernetes cluster which passes the k8s conformance tests.
cluster:
	make clean-webserver        # Stop any existing webserver.
	make clean-keys             # Remove any SSL keys.
	make clean-kubectl	    # Remove old kubectl.
	make clean-binaries         # Clean CNI binaries.
	make kubectl                # Get kubectl
	make binaries               # Make calico-cni binaries.
	make create-cluster-vagrant # Start the cluster.
	make kube-system            # Create kube-system namespace.
	make run-dns-pod            # Run DNS addon.
	make run-kube-ui            # Run kube-ui addon.

# Builds the latest calico-cni binaries.
binaries: 
	make -C calico-cni

# Cleans the calico-cni submodule.
clean-binaries:
	make -C calico-cni clean

destroy-cluster-vagrant: 
	-vagrant destroy -f

create-cluster-vagrant: destroy-cluster-vagrant webserver
	vagrant up

webserver: ssl-keys
	python -m SimpleHTTPServer &

clean-webserver: clean-keys
	(sudo killall python) || echo "Server not running"

generate-certs:
	sudo openssl/create_keys.sh

clean-kubectl:
	rm -f kubectl

kubectl: admin.pem
	wget http://storage.googleapis.com/kubernetes-release/release/v$(K8S_VERSION)/bin/linux/amd64/kubectl
	chmod +x kubectl
	./kubectl config set-cluster default-cluster --server=https://172.18.18.101 --certificate-authority=ca.pem
	./kubectl config set-credentials default-admin --certificate-authority=ca.pem --client-key=admin-key.pem --client-certificate=admin.pem
	./kubectl config set-context default-system --cluster=default-cluster --user=default-admin
	./kubectl config use-context default-system

remove-dns: 
	./kubectl --namespace=kube-system delete rc kube-dns-v9
	./kubectl --namespace=kube-system delete svc kube-dns

run-dns-pod:
	./kubectl create --validate=false -f dns/dns-addon.yaml

remove-kube-ui:
	./kubectl --namespace=kube-system delete rc kube-ui-v4
	./kubectl --namespace=kube-system delete svc kube-ui

run-kube-ui: 
	./kubectl create --validate=false -f kube-ui/

kube-system:
	./kubectl create --validate=false -f namespaces/kube-system.yaml

calicoctl:
	wget http://www.projectcalico.org/builds/calicoctl
	chmod +x calicoctl

ca-key.pem:
	openssl genrsa -out ca-key.pem 2048
	openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"

admin.pem: ca-key.pem 
	openssl genrsa -out admin-key.pem 2048
	openssl req -new -key admin-key.pem -out admin.csr -subj "/CN=kube-admin"
	openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out admin.pem -days 365

apiserver.pem: ca-key.pem 
	openssl genrsa -out apiserver-key.pem 2048
	openssl req -new -key apiserver-key.pem -out apiserver.csr -subj "/CN=kube-apiserver" -config openssl.cnf
	openssl x509 -req -in apiserver.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out apiserver.pem -days 365 -extensions v3_req -extfile openssl.cnf

clean-keys:
	rm -f *.pem
	rm -f ca.srl
	rm -f *.csr
