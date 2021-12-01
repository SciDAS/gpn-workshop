Doing Genomics in the Cloud: From Repository to Result
====

Computational genomics has become a core toolkit in the study of biological systems at the molecular level.  To run genomics workflows, a researcher needs access to advanced computer systems including compute, storage, memory, and networks to move and mine huge genomics datasets. The workflows will include pulling high-throughput DNA datasets from the NCBI-SRA data repository, performing reference genome mapping of SRA RNAseq datasets, and building a gene co-expression network.

The Workshop:

We will cover the complete deployment life cycle that enables scientific workflows to be run in the cloud. This includes:
 - Accessing a Kubernetes(K8s) cluster via the command line.
 - Creating a persistent NFS server to store workflow data, then loading a Gene Expression Matrix(GEM) onto it.
 - Pulling genomic data from the NCBI's SRA database.
 - Deploying GEMmaker to create a Gene Expression Matrix
 - Deploying Knowledge Independent Network Construction(KINC), a genomic workflow, to the K8s cloud.
 - Downloading the resulting Gene Coexpression Network(GCN) from the NFS server, then visualizing the network.

# GEMmaker

## 0. Prerequisites

The following software is necessary to participate in the demo:
 - kubectl - Kubernetes CLI 
 - Nextflow - Workflow Manager
 - Java
 - Helm

To streamline the workshop, all software has been packaged into a virtual machine that has been replicated for each user. 

An additional requirement is access to the kubernetes clusters that will be used for the workshop.

**If you do not have your CCP cluster credentials(kubeconfig) and access to your personal VM, please let us know.**

### Access Praxis

Navigate to [the Praxis portal](https://dcm.toolwire.com/alai/admin/login.jsp)

Enter your credentials.

Select the class *Running Scientific Workflows on Regional R&E Kubernetes Clusters Workshop*

Select *Learning* at the upper right side of the menu bar.

Select the lab session *Accessing the Cloud through c-Light CCP/IKS Cluster*, when prompted start the live lab.

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

## 2. Create Persistant Data Storage to Host Workflow Data

Now it is time to provision a NFS server to store workflow data. We will streamline this process by using Helm. Helm is a kubernetes package manager!

Install Helm:

`cd PATH`

`wget https://get.helm.sh/helm-v3.6.0-linux-amd64.tar.gz`

`tar -xvf helm-v3.6.0-linux-amd64.tar.gz`

`sudo cp linux-amd64/helm /usr/local/bin`

Add the `stable` repo:

`helm repo add stable https://charts.helm.sh/stable`

Update Helm's repositories(similar to `apt-get update)`:

`helm repo update`

Next, install a NFS provisioner onto the K8s cluster to permit dynamic provisoning for 50Gb of persistent data:

**Only one person per cluster should run this command:**

```
helm install kf stable/nfs-server-provisioner \
--set=persistence.enabled=true,persistence.storageClass=standard,persistence.size=300Gi
```
**Everyone:**

Check that the `nfs` storage class exists:

`kubectl get sc`

Next, deploy a 50Gb Persistant Volume Claim(PVC) to the cluster:

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

Edit the file with `nano task-pv-claim.yaml `and enter your name for your own PVC!

```
metadata:
  name: task-pv-claim-<YOUR_NAME>
```

`kubectl create -f task-pv-claim.yaml`

Check that the PVC was deployed successfully:

`kubectl get pvc`

Give Nextflow the necessary permissions to deploy jobs to your K8s cluster:

```
kubectl create rolebinding default-edit --clusterrole=edit --serviceaccount=default:default 
kubectl create rolebinding default-view --clusterrole=view --serviceaccount=default:default
```

Finally, login to the PVC to get a shell, enabling you to view and manage files:

`nextflow kuberun login -v task-pv-claim-<YOUR_NAME>`

Take note of the pod that gets deployed, use the name when you see **<POD_NAME>**

**This tab is now on your cluster's persistent filesystem.** 

**To continue, open a new tab with File -> New -> Terminal**

## 3. Deploy a Container to Pull Genomic Data

**On your local VM....**

Go to the repo:

`cd ~/Desktop/classroom/myfiles/gpn-workshop`

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
        claimName: task-pv-claim-<YOUR_NAME> # Enter valid PVC
```

Deploy the sra-tools container:

`kubectl create -f sra-tools.yaml`

Get the name of your pod:

`kubectl get pods`

Get a Bash session inside your pod:

`kubectl exec -ti sra-tools-<YOUR_NAME> -- /bin/bash`

Once inside the pod, navigate to the persistent directory `/workspace`:

`cd /workspace`

Make a folder and enter:

`mkdir -p /workspace/sra-data-<YOUR_NAME> && cd /workspace/sra-data-<YOUR_NAME>`

Initialize SRA-Tools:

`printf '/LIBS/GUID = "%s"\n' 'uuidgen' > /root/.ncbi/user-settings.mkfg`

Pull the sequence: `prefetch SRR5139429`

Then, uncompress and splint into forward and reverse reads:

`fasterq-dump --split-files SRR5139429/SRR5139429.sra`

**While the file is downloading, create another new tab.**

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
  name: gm-<YOUR_NAME>
  labels:
    app: gm-<YOUR_NAME>
spec:
  containers:
  - name: gm-<YOUR_NAME>
```
```
    args: [ "-c", "cd /workspace/gm-<YOUR_NAME>/input && kallisto index -i /workspace/gm-<YOUR-NAME>/input/Arabidopsis_thaliana.TAIR10.kallisto.indexed Arabidopsis_thaliana.TAIR10.cdna.all.fa.gz" ]
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






