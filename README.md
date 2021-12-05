Doing Genomics in the Cloud: From Repository to Result
====

Computational genomics has become a core toolkit in the study of biological systems at the molecular level.  To run genomics workflows, a researcher needs access to advanced computer systems including compute, storage, memory, and networks to move and mine huge genomics datasets. The workflows will include pulling high-throughput DNA datasets from the NCBI-SRA data repository, performing reference genome mapping of SRA RNAseq datasets, and building a gene co-expression network.

The Workshop:

We will cover the complete deployment life cycle that enables scientific workflows to be run in the cloud. This includes:
 - Accessing a Kubernetes(K8s) cluster via the command line.
 - Creating a persistent NFS server to store workflow data, then loading workflow data onto it.
 - Pulling genomic RNA data from the NCBI's SRA database.
 - Deploying GEMmaker on the K8s cluster to create a Gene Expression Matrix.
 - Using the output from the GEMmaker run with Knowledge Independent Network Construction(KINC), a genomic workflow, to the K8s cloud.
 - Downloading the resulting Gene Coexpression Network(GCN) from the NFS server, then visualizing the network.

## 0. Prerequisites

The following software is necessary to participate in the demo:
 - kubectl - Kubernetes CLI 
 - Nextflow - Workflow Manager
 - Java
 - Helm(optional) - Kubernetes Deployment Orchestrator

To streamline the workshop, all software has been packaged into a virtual machine that has been replicated for each user. 

An additional requirement is access to the Kubernetes clusters that will be used for the workshop.

**If you do not have your CCP cluster credentials(kubeconfig) and access to your personal VM, please let us know.**

### Access Praxis(optional)

Navigate to [the Praxis portal](http://learning.prxai.com)

Enter your credentials.

Select the class *Running Scientific Workflows on Regional R&E Kubernetes Clusters Workshop*

Select *Learning* at the upper right side of the menu bar.

Select the lab session *Accessing the Cloud through c-Light CCP/IKS Cluster*, when prompted start the live lab.

Once the Jupyter notebook is provisioned, select *Terminal* from the menu to access a Bash terminal from within your VM! 

Finally, please clone this repo to a folder with persistent storage:

`git clone https://github.com/SciDAS/scidas-workshop ~/Desktop/classroom/myfiles/scidas-workshop`

### Access Nautilus(optional)

Nautilus is the Kubernetes cluster that composes the [National Research Platform](https://nautilus.optiputer.net/). With nodes spread across the United States and a few international sites, Nautilus is an extremely useful resource for computational scientists. To join Nautilus:

Create an account by logging in at 

You may use an affiliated campus email, or a Google email.

Next, send me an email at cbmckni@clemson.edu, and I will add you to our namespace used for education. You may also request one for your own research!

Finally, download your kubeconfig by selecting ["Get Config"](https://nautilus.optiputer.net/authConfig) from the home page.

# Creating a Research Environment in Kubernetes

This section will cover accessing a Kubernetes cluster and creating persistent storage.

## 1. Access Kubernertes Cluster

Download or copy/paste the kubeconfig you were provided to a file named `config`.

Create a folder `~/.kube`:

`mkdir -p ~/.kube`

Move the kubeconfig to your .kube folder: 

`mv config.yaml ~/.kube`

Set permissions:

`chmod 600 ~/.kube/config`

Confirm your cluster name:

`kubectl config current-context`

The output should match the name of your cluster.

You now have access to your K8s cluster!

Issue an API call to view current pods(containers) that are deployed within the namespace:

`kubectl get pods`

## 2. Create Persistant Data Storage to Host Workflow Data

Now it is time to provision a NFS server to store workflow data. We will streamline this process by using Helm. Helm is a Kubernetes package manager!

First, check to see if a storage class already exists:

`kubectl get sc`

If not, follow the instructions below in *2a*.

If a valid storage class exists, proceed to *2b*.

### 2a. Create a NFS Storage Class(optional)

**On some clusters, you may not have permission to do this, or you may not need to.**

Follow the instructions above to install Helm.

Install a NFS provisioner onto the K8s cluster to permit dynamic provisoning for ~300Gb of persistent data:

```
helm install kf stable/nfs-server-provisioner \
--set=persistence.enabled=true,persistence.storageClass=standard,persistence.size=320Gi
```

### 2b. Create a Persistent Volume Claim(PVC)

Check that the a valid storage class exists:

`kubectl get sc`

Next, deploy a 300Gb Persistant Volume Claim(PVC) to the cluster:

`cd ~/Desktop/classroom/myfiles/scidas-workshop`

Edit the file with `nano pvc.yaml `and enter your name and a valid storage class for your PVC!

```
metadata:
  name: pvc-<YOUR_NAME>
spec:
  storageClassName: rook-cephfs
```

`kubectl create -f pvc.yaml`

Check that the PVC was deployed successfully:

`kubectl get pvc`

Give Nextflow the necessary permissions to deploy jobs to your K8s cluster:

**This command only needs to be run once, and is not necessary on namespaces where Nextflow has already been run.**

```
kubectl create rolebinding default-edit --clusterrole=edit --serviceaccount=default:default 
kubectl create rolebinding default-view --clusterrole=view --serviceaccount=default:default
```

Finally, login to the PVC to get a shell, enabling you to view and manage files:

`nextflow kuberun login -v pvc-<YOUR_NAME>`

Take note of the pod that gets deployed, use the name when you see **<POD_NAME>**

**This tab is now on your cluster's persistent filesystem.** 

# GEMmaker

[GEMmaker](https://github.com/SystemsGenetics/GEMmaker) is a genomic workflow that takes raw RNA sequences and builds a Gene Expression Matrix(GEM), a matrix that compares gene expression across a number of samples. GEMs are used as input by a number of downstream workflows, including Knowledge Independent Network Construction(KINC).

## 1. Index Arabidopsis Reference Genome(optional)

GEMmaker needs a reference genome to map gene expression levels. There is a simple "Cool Organism"(CORG) reference genome that has been pre-indexed for each GEMmaker pipeline option(Kallisto, Salmon, Hisat2).

CORG is used by default in the configuation files, but to get biologically accurate results the real Arabidopsis Thaliana Reference Genome should be indexed. 

Here are the steps to download and index the Arabidopsis genome using Kallisto:

**On the cluster....**

Navigate to your input directory:

`cd /workspace/gemmaker/input`

Download the Arabidopsis genome for indexing:

`wget ftp://ftp.ensemblgenomes.org/pub/plants/release-50/fasta/arabidopsis_thaliana/cdna/Arabidopsis_thaliana.TAIR10.cdna.all.fa.gz`

**On your local VM....**

Go to the repo:

`cd ~/Desktop/classroom/myfiles/scidas-workshop`

Edit the file `gemmaker.yaml`:

```
metadata:
  name: kallisto-<YOUR_NAME>
  labels:
    app: kallisto-<YOUR_NAME>
spec:
  containers:
  - name: kallisto-<YOUR_NAME>
```
```
      persistentVolumeClaim:
        claimName: pvc-<YOUR_NAME> # Enter valid PVC
```

Deploy the GEMMaker container to index the genome:

`kubectl create -f kallisto.yaml`

The pod will run non-interactively, so just confirm it deploys and runs with `kubectl get pods`


## 2. Pull RNA Data from NCBI

Moving data into your K8s cluster is very important. We will cover 4 methods 

### 2a. Use a Built-In Workflow Utility 

Many workflows, such as GEMmaker, have a built in utility to pull input data. This utility requires a path on to a file on the cluster, containing a list of SRA IDs to be pulled.

**On the cluster....**

Create a folder for your workflow and input:

`mkdir -p /workspace/gemmaker/input && cd /workspace/gemmaker/input`

Make a file in the same folder called `SRAs.txt` with the SRA IDs of 3 Arabidopsis samples:

```
cat > /workspace/gemmaker/input/SRA_IDs.txt << EOL
SRR1058270
SRR1058271
SRR1058272
EOL
```

Make sure it is formatted correctly!

```
# cat /workspace/gemmaker/input/SRA_IDs.txt
SRR1058270
SRR1058271
SRR1058272
```

### 2b. Use a Single-Container Deployment to Pull Files Sequentially(optional)

**On your local VM....**

Go to the repo:

`cd ~/Desktop/classroom/myfiles/scidas-workshop`

Edit the file `sra-tools.yaml`:

```
metadata:
  name: sra-tools-<YOUR_NAME>
  labels:
    app: sra-tools-<YOUR_NAME>
spec:
  containers:
  - name: sra-tools-<YOUR_NAME>
```
```
      persistentVolumeClaim:
        claimName: pvc-<YOUR_NAME> # Enter valid PVC
```

Deploy the sra-tools container:

`kubectl create -f sra-tools.yaml`

Check the status of your pod:

`kubectl get pods`

Get a Bash session inside your pod:

`kubectl exec -ti sra-tools-<YOUR_NAME> -- /bin/bash`

Once inside the pod, navigate to the persistent directory mounted at `/workspace`:

`cd /workspace`

Make a folder and enter:

`mkdir -p /workspace/gemmaker/input && cd /workspace/gemmaker/input`

Initialize SRA-Tools:

`printf '/LIBS/GUID = "%s"\n' 'uuidgen' > /root/.ncbi/user-settings.mkfg`

Then, pull the data using the list of SRA IDs:

`cat SraAccList.txt | xargs fasterq-dump --split-files --outdir=/workspace/gemmaker/input`

### 2c. Use a Multi-Container StatefulSet to Pull Files in Parallel(optional)

A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) is an ordered deployment of containers.

To parallelize pulling data, we can create a StatefulSet with one container for each file we want to pull.

**On the cluster....**

Create a folder for your workflow and input:

`mkdir -p /workspace/gemmaker/input && cd /workspace/gemmaker/input`

[pull-sample-batch.sh]() is a script that gets the ordered index of a container and pulls the SRA ID at that line of the list.

Download the script to the cluster:

`cd /workspace/gemmaker/ && wget ` 

**On your local VM....**

Go to the repo:

`cd ~/Desktop/classroom/myfiles/scidas-workshop`

Edit the file `statefulset.yaml`:

```
metadata:
  name: sra-batch-cole
  labels:
    app: sra-batch-cole
spec:
  serviceName: sra-batch-cole
  replicas: 7
  selector:
    matchLabels:
      app: sra-batch-cole
  template:
    metadata:
      labels:
        app: sra-batch-cole
    spec:
      containers:               
      - name: sra-batch-cole
        image: ncbi/sra-tools
        command: [ "/bin/sh", "-c", "--" ]
        args: [ "cd" ]
        resources:
          requests:
            cpu: 1
            memory: 4Gi
          limits:
            cpu: 1
            memory: 4Gi
        volumeMounts:
        - name: sra-batch-pvc
          mountPath: /workspace
      restartPolicy: Always
      volumes:
        - name: sra-batch-pvc
          persistentVolumeClaim:
            claimName: pvc-<YOUR_NAME> # Enter valid PVC
```
```
      persistentVolumeClaim:
        claimName: pvc-<YOUR_NAME> # Enter valid PVC
```

### 2d. Use the Data Transfer Pod Utility to Pull Files Sequentially(optional)

The Data Tranfer Pod Utility is a tool developed to make it easy to move data in and out of a Kubernetes cluster, using a variety of protocols.

Right now, the supported protocols are:

 - [Google Cloud SDK](https://cloud.google.com/sdk) 
 - [Globus Connect Personal](https://app.globus.org/)
 - [iRODS](https://irods.org/)
 - [Named-Data Networking(NDN)](https://named-data.net/)
 - [Aspera CLI](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.2.0/featured_applications/aspera_cli.html)
 - [Amazon Web Services](https://aws.amazon.com/cli/)
 - [MinIO](https://min.io/)
 - [NCBI's SRA Tools](https://github.com/ncbi/sra-tools)
 - [Fast Data Transfer(FDT)](http://monalisa.cern.ch/FDT/)
 - Local transfers(to/from the user's local machine)

The steps to pull the RNA sequences are essentially the same as in *1b* once the SRA Tools container is deployed. To deploy an instance of DTP-Personal, clone the [repository](https://github.com/SciDAS/dtp-personal) and follow the [documentation](https://github.com/SciDAS/dtp-personal/blob/master/README.md).

## 4. Configure GEMmaker 

**On your local VM....**

Edit the file `~/Desktop/classroom/myfiles/gpn-workshop/nextflow.config.gemmaker`:

```
profiles {
  k8s {
      k8s {
          workDir = "/workspace/gm-<YOUR_NAME>/work"
          launchDir = "/workspace/gm-<YOUR_NAME>"
      }
      params {
        outdir = "/workspace/gm-<YOUR_NAME>/output"
```

**On the cluster....**

Create a folder for your workflow and input:

`mkdir -p /workspace/gm-<YOUR_NAME>/input && cd /workspace/gm-<YOUR_NAME>/input`

Make a file in the same folder called `SRAs.txt` with the SRA IDs of 3 Arabidopsis samples:

```
cat > /workspace/gm-<YOUR_NAME>/input/SRA_IDs.txt << EOL
SRR1058270
SRR1058271
SRR1058272
EOL
```

Make sure it is formatted correctly!

```
# cat /workspace/gm-<YOUR_NAME>/input/SRA_IDs.txt
SRR1058270
SRR1058271
SRR1058272
```

### 4b. Manually Index Genome (optional)

**On the cluster....**

Navigate to your input directory:

`cd /workspace/gm-<YOUR_NAME>/input`

Download the Arabidopsis genome for indexing:

`wget ftp://ftp.ensemblgenomes.org/pub/plants/release-50/fasta/arabidopsis_thaliana/cdna/Arabidopsis_thaliana.TAIR10.cdna.all.fa.gz`

**On your local VM....**

Go to the repo:

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

Edit the file `gemmaker.yaml`:

```
metadata:
  name: kallisto-<YOUR_NAME>
  labels:
    app: kallisto-<YOUR_NAME>
spec:
  containers:
  - name: kallisto-<YOUR_NAME>
```
```
      persistentVolumeClaim:
        claimName: task-pv-claim-<YOUR_NAME> # Enter valid PVC
```

Deploy the GEMMaker container to index the genome:

`kubectl create -f gemmaker.yaml`

The pod will run non-interactively, so just confirm it deploys and runs with `kubectl get pods`

**Switch tabs**

## 5. Deploy GEMmaker

**On your local VM's filesystem....**

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

Deploy GEMMaker with:

```
nextflow -C nextflow.config.gemmaker kuberun systemsgenetics/gemmaker -r dev -profile k8s -v task-pv-claim-<YOUR_NAME> --sras /workspace/gm-<YOUR_NAME>/input/SRA_IDs.txt
```

**If you followed steps 4a. or 4b. add the argument** 

`--kallisto_index_path /workspace/gm-<YOUR_NAME>/input/Arabidopsis_thaliana.TAIR10.kallisto.indexed`

## 6. View Output
 
**After the workflow has completed, switch tabs to your cluster's filesystem**

To view the resulting GEM:

`cat /workspace/gm-<YOUR_NAME>/output/GEMs/GEMmaker.GEM.TPM.txt`



# KINC

## 0. Prerequisites

The following software is necessary to participate in the demo:
 - helm
 - kubectl - Kubernetes CLI 
 - Nextflow - Workflow Manager
 - Java
 - Files/scripts from this repo.

To streamline the workshop, all software has been packaged into a virtual machine that has been replicated for each user. 

An additional requirement is access to the kubernetes clusters that will be used for the workshop.

**If you do not have your CCP cluster credentials(kubeconfig) and access to your personal VM, please let us know.**

### Access Praxis

Navigate to [the Praxis portal](https://dcm.toolwire.com/alai/admin/login.jsp)

Enter your credentials.

Select the class *Running Scientific Workflows on Regional R&E Kubernetes Clusters Workshop*

Select *Learning* at the upper right side of the menu bar.

Select the lab session *Making Gene Networks with KINC: GEMs to GCNs*, when prompted start the live lab.

Once the Jupyter notebook is provisioned, select *Terminal* from the menu to access a Bash terminal from within your VM! 

Finally, please clone this repo to a folder with persistent storage:

`git clone https://github.com/SciDAS/scidas-workshop ~/Desktop/classroom/myfiles/scidas-workshop`

## 1. Access Kubernertes Cluster

Download or copy/paste the kubeconfig you were provided to a file named `config`.

Move the kubeconfig to your .kube folder: 

`mv config.yaml ~/.kube`

`chmod 600 ~/.kube/config`

Confirm your cluster name:

`kubectl config current-context`

The output should match the name of your cluster.

You now have access to your K8s cluster!

Issue an API call to view current pods(containers) that are deployed:

`kubectl get pods`

**If you were not present for the first session:**

Check that the `nfs` storage class exists:

`kubectl get sc`

Next, deploy a 50Gb Persistant Volume Claim(PVC) to the cluster:

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

Edit the file and enter your name for your own PVC!

```
metadata:
  name: task-pv-claim-<YOUR_NAME>
```

`kubectl create -f task-pv-claim.yaml`

Check that the PVC was deployed successfully:

`kubectl get pvc`

**Everyone:**

To view and manage files on the cluster:

`nextflow kuberun login -v task-pv-claim-<YOUR_NAME>`

Take note of the pod that gets deployed, use the name when you see **<POD_NAME>**

**To continue, open a new tab with File -> New -> Terminal**

## 2. Deploy KINC

**On your local VM....**

Go to the repo: 

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

Edit the file `nextflow.config`:

```
params {
    input {
        dir = "/workspace/gcn-<YOUR_NAME>/input"
        emx_txt_files = "*.emx.txt"
        emx_files = "*.emx"
        ccm_files = "*.ccm"
        cmx_files = "*.cmx"
    }

    output {
        dir = "/workspace/gcn-<YOUR_NAME>/output"
    }
```

Load the input data onto the PVC:

`kubectl exec <POD_NAME> -- bash -c "mkdir -p /workspace/gcn-<YOUR_NAME>"`

`kubectl cp "input" "<POD_NAME>:/workspace/gcn-<YOUR_NAME>"`

Deploy KINC using `nextflow-kuberun`:

`nextflow kuberun -C nextflow.config systemsgenetics/kinc-nf -v task-pv-claim-<YOUR_NAME>`

**The workflow should take about 10-15 minutes to execute.**

## 3. Retreive and Visualize Gene Co-expression Network

Copy the output of KINC from the PVC to your VM:

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

```
kubectl exec <POD_NAME> -- bash -c \
"for f in \$(find /workspace/gcn-<YOUR_NAME>/output/Yeast -type l); do cp --remove-destination \$(readlink \$f) \$f; done"
```

`kubectl cp "<POD_NAME>:/workspace/gcn-<YOUR_NAME>/output/Yeast" "Yeast"`

Open Cytoscape. (Applications -> Other -> Cytoscape)

Go to your desktop and open a file browsing window, navigate to the output folder:

`cd ~/Desktop/classroom/myfiles/gpn-workshop/Yeast`

Finally, drag the file `Yeast.coexpnet.txt` from the file browser to Cytoscape!

The network should now be visualized! 






