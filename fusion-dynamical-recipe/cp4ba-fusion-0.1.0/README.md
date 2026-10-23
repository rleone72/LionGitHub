## Cloud Pak for Business Automation Backup and Restore using IBM Storage Fusion

### Prerequisites

- IBM Storage Fusion version `2.12.1` or later should be installed.
- Either Fusion Backup & Restore service (for hubs) or Fusion Backup & Restore Agent (for spokes) service should be installed.


### Applying the IBM Storage Fusion hotfix

It is necessary to apply the Fusion Backup & Restore hotfix for version 2.12.2 on the hub and all spoke clusters prior to initiating backup or restore operations. For more background on this fix refer to IBM Fusion hotfix documentation: https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=hotfixes. To apply the fix execute the following:

```
$ oc -n ibm-backup-restore patch deployments/transaction-manager --type json --patch '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:34609296996c0416d1d84e775ba3cf33b78cdbdfe5e50eebcb632ef20135f895"}]'

deployment.apps/transaction-manager patched
```


### Recipe installation procedure (on the cluster the application is installed)


1. To make installation smoother, define the following variable for the project where Cloud Pak for Business Automation's installed:

    ```
    $ CP4BA_NAMESPACE=<CP4BA-PROJECT>
    ```


1. Run the included `configure-cp4ba-fusion.sh` script. The only required parameter is namespace, provided by the `-n` or `--namespace` options:

    ```
    $ ./configure-cp4ba-fusion.sh --namespace $CP4BA-NAMESPACE

    [INFO] Starting CP4BA Storage Fusion backup configuration...
    [INFO] Checking prerequisites...
    [SUCCESS] All prerequisites met
    [INFO] Discovering IBM Storage Fusion namespace...
    [SUCCESS] Discovered Fusion namespace: ibm-spectrum-fusion-ns
    [INFO] Checking transaction-manager-ibm-backup-restore ClusterRole...
    [SUCCESS] ClusterRole already has icp4a.ibm.com permissions. Skipping patch.
    [INFO] Checking Fusion Application configuration...
    [SUCCESS] 'openshift-config' already in includedNamespaces
    [SUCCESS] 'openshift-marketplace' already in includedNamespaces
    [INFO] Labeling core CP4BA resources...
    [SUCCESS] Core resources labeled
    [INFO] Checking for FNCM (FileNet Content Manager) installation...
    [INFO] FNCM detected. Labeling FNCM-specific resources...
    [SUCCESS] FNCM resources labeled
    [INFO] Checking for BAW (Business Automation Workflow) installation...
    [INFO] BAW detected. Labeling BAW-specific resources...
    [SUCCESS] BAW resources labeled
    [SUCCESS] CP4BA Storage Fusion backup configuration completed successfully!
    ```


1. Install the included Cloud Pak for Business Automation Fusion (`cp4ba-fusion`) package on the namespace where Cloud Pak for Business Automation is installed.

    ```
    $ helm install --namespace $CP4BA_NAMESPACE cp4ba-fusion cp4ba-fusion-0.1.0.tgz \
      --set zenStorageClass=STORAGE-CLASS-NAME

    NAME: cp4ba-fusion
    LAST DEPLOYED: Fri Feb 27 15:54:18 2026
    NAMESPACE: cp4ba
    STATUS: deployed
    REVISION: 1
    TEST SUITE: None
    ```
    Where "STORAGE-CLASS-NAME" is the name specified in the StorageClass CR being used.

    Outlined are a couple of checks to verify the installation:

    - The zen5 deployment should be up and running:

        ```
        $ oc -n $CP4BA_NAMESPACE get deployments/zen5-backup
        
        NAME          READY   UP-TO-DATE   AVAILABLE   AGE
        zen5-backup   1/1     1            1           17h
        ```


    - The recipes should be installed:

        ```
        $ oc -n $CP4BA_NAMESPACE get frcpe
        
        NAME                          AGE                    PARENT RECIPE         PARENT RECIPE NAMESPACE
        cp4ba-baw-auth-child-recipe   2026-03-06T01:31:55Z   cp4ba-parent-recipe   cp4ba
        cp4ba-fncm-child-recipe       2026-03-06T01:31:55Z   cp4ba-parent-recipe   cp4ba
        cp4ba-parent-recipe           2026-03-06T01:31:55Z                         
        ```


### Backup procedure

1. If you haven't already, follow the procedures to achieve the following: 

    - Create a [backup storage location](https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=machines-backup-storage-locations).
    - Create a [backup policy](https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=policies-creating-backup-policy).
    - Create a policy assignment by [assigning the policy to the application](https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=policies-managing-backup-policy).

    *Refer to https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=workloads-backup-restore-your-applications-virtual-machines for a more comprehensive procedure.*

1. On Fusion, after [assigning a backup policy to the application](https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=workloads-backup-restore-your-applications-virtual-machines),
patch the policy assignment to point to the parent recipe:
  
    - Identify the policy assignment's name:

        ```
        $ oc -n ibm-spectrum-fusion-ns get policyassignments
        
        NAME                                                   CLUSTER   APPLICATION   BACKUPPOLICY   RECIPE                RECIPENAMESPACE   PHASE      LASTBACKUPTIMESTAMP   CAPACITY
        cp4ba-sbsa-policy-apps.sbsa-br1.cp.fyre.ibm.com                  cp4ba         sbsa-policy    cp4ba-parent-recipe   cp4ba             Assigned   3d7h                  4521418945
        ```


    - Patch that policy assignment with the recipe name and namepace (the recipe is the same always):

        ```
        $ oc -n ibm-spectrum-fusion-ns patch policyassignment/POLICY-ASSIGNMENT-NAME --type merge -p '
        {
          "spec": {
            "recipe": {
              "name":"cp4ba-parent-recipe",
              "namespace":"'$CP4BA_NAMESPACE'",
              "apiVersion":"spp-data-protection.isf.ibm.com/v1alpha1"
            }
          }
        }'
        ```

        Where "POLICY-ASSIGNMENT-NAME" is the name of the PolicyAssignment CR (see immediate step above).
        

1. On the Fusion console, follow the procedure to [kick off an on-demand backup](https://www.ibm.com/docs/en/fusion-software/2.12.x?topic=machines-running-demand-backups) or
let the backup policy schedule it for you.


### Restore procedure (only when it's an alternative cluster restore)

*Note: Both the ibm-licensing and the certificate manager services should be running in the target cluster, before restoring to it.*

1. Configure the Fusion Transaction Manager's role:

    ```
    $ oc patch clusterroles/transaction-manager-ibm-backup-restore --type json --patch '
    [
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": [
            "icp4a.ibm.com"
          ],
          "resources": [
            "icp4aclusters",
            "contents"
          ],
          "verbs": [
            "get",
            "list"
          ]
        }
      }
    ]'
    ```

1. On the Fusion console, follow the procedure to kick off a restore.



### After restore steps

1. After restore's complete, apply the following patch, to make sure nginx is reconfigured and routes are accessible:


    ```
    $ oc -n $CP4BA_NAMESPACE get zenextensions -o name | xargs oc -n $CP4BA_NAMESPACE patch --type json --patch '[{"op":"replace","path":"/spec/reconfigure","value":true}]'
    ```

