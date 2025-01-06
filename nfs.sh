# Ref from https://github.com/BabbarPB08/NFS-OCP

# Install NFS Utilities and Git (if not already installed)

sudo yum install nfs-utils git -y

sudo mkdir -p /mnt/k8s_nfs_storage
sudo chmod 777 /mnt/k8s_nfs_storage
sudo chown -R nobody:nobody /mnt/k8s_nfs_storage
sudo semanage fcontext -a -t public_content_rw_t "/mnt/k8s_nfs_storage(/.*)?"
sudo restorecon -Rv /mnt/k8s_nfs_storage

# configure NFS server

echo "/mnt/k8s_nfs_storage *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports

sudo exportfs -rav

sudo systemctl enable nfs-server
sudo systemctl start nfs-server

sudo firewall-cmd --add-service=nfs --add-service=rpc-bind --add-service=mountd --permanent
sudo firewall-cmd --reload

oc get nodes

hostname -I


# Variables
NFS_PATH="/mnt/k8s_nfs_storage"

# Dynamically determine a worker node
WORKER_NODE=$(oc get nodes --selector='node-role.kubernetes.io/worker' -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$WORKER_NODE" ]]; then
  echo "No worker nodes found. Please check the cluster status."
  exit 1
fi

BASTION_HOST_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$BASTION_HOST_IP" ]]; then
  echo "Unable to determine bastion host IP. Please check the host configuration."
  exit 1
fi

echo "Bastion Host IP: $BASTION_HOST_IP"

# Commands to execute
cat <<EOF | oc debug node/$WORKER_NODE
chroot /host
showmount -e $BASTION_HOST_IP
mkdir -p /mnt/test
mount -t nfs $BASTION_HOST_IP:$NFS_PATH /mnt/test
touch /mnt/test/testfile
umount /mnt/test
exit
EOF

# NFS Subdirectory External Provisioner in OpenShift: The NFS Subdirectory External Provisioner is a 
# component that enables dynamic provisioning of PersistentVolumeClaims (PVCs) in OpenShift 
# (and Kubernetes) using existing NFS shares as the underlying storage. 
# It simplifies the process of setting up and managing NFS-based storage for your applications running 
# in an OpenShift cluster.

git clone https://github.com/BabbarPB08/NFS-OCP.git && cd NFS-OCP

IP=`hostname -I | awk '{ print $1 }'`
NFS_EXPORT=`showmount -e $IP --no-headers | awk '{ print $1 }'`

echo $IP $NFS_EXPORT

oc new-project nfs-subdir-external-provisioner
sed -i "s-<NFS_EXPORT>-$NFS_EXPORT-g" ./objects/deployment.yaml
sed -i "s/<IP>/$IP/g" ./objects/deployment.yaml

NAMESPACE=`oc project -q`
sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./objects/rbac.yaml ./objects/deployment.yaml
oc create -f objects/rbac.yaml
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:$NAMESPACE:nfs-client-provisioner   

oc apply -f ./objects/deployment.yaml
oc apply -f ./objects/class.yaml

oc get all -n nfs-subdir-external-provisioner

oc get storageclass
oc get storageclass nfs-client -o yaml

# Test NFS subdirectory  external provisioner


