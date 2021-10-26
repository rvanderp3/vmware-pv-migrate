# Overview

The intent of this project is to provide an example workflow of how one can migrate persistent volumes between datastores.  

Note: These steps were compiled from tests in my environment.  You are responsible for ensuring that you backup data and test any migration to ensure data is migrated properly.

# Requirements

- `govc` is installed and on the path
- GOVC environment variables are exported such that govc can create a virtual disk on the desired datastore
- `oc` is installed and on the path
- user account with cluster-admin privileges on the OpenShift cluster where the storage is to be migrated

# Preparing

- Identify the persistent volume claims to be migrated
- Create a folder in the target datastore to contain the newly created VMDKs
- Ensure the PVCs to be migrated do not have an active pod.
  Note: For core operators such as `monitoring`, the cluster-version-operator may need to be scaled down along 
  with any other operators which may reconcile to restart a scaled down pod.  This process will require some 
  downtime for services using storage to be migrated.

# Migration

Migration follows this workflow:
1. Identify PV associated with the PVC to migrate
2. Identify running workloads using the PVC and scale them down.
3. Create a virtual disk of the same size in the target datastore
4. Create a temporary PV/PVC referencing the new virtual disk
5. Start a `job` to migrate data from the original to the new virtual disk
6. Set the retention policy on the original PV to `Retain` to ensure the original disk remains in the event the migration is unsuccessful
7. Delete the temporary PVC/PV and original PVC
8. Create new PV and PVC(of the same name as the original PVC) pointing to the new virtual disk
9. Scale up workloads

Note: It is strongly recommended that backups be taken of any data prior to migration.  While care is taken to preserve
the original data, taking a backup is good practice ahead of a migration.

The steps in the process have been recorded in a sample script `migrate.sh`.  To use the script:

1. Update `TARGET_DATASTORE`, `TARGET_FOLDER`, and `PVC` to reflect the destination where data is to be stored and the name of the PVC to migrate.
2. Run `source migrate.sh`
3. Ensure `oc project` is pointing to the project which contains the PVC to migrate.
4. Ensure any workloads using the PVC to be migrated are scaled down.
5. Run the following steps one at a time checking the output from each step before proceeding to the next:
~~~
MIGRATE_PV_GET_RESOURCES
MIGRATE_PV_CREATE_TEMP_PV_PVC
MIGRATE_PV_MIGRATE_DATA
MIGRATE_PV_CLEAN_UP_TEMPORARY_RESOURCES
MIGRATE_PV_SWITCH_TO_MIGRATED_DATA
~~~
6. Scale up workloads associated with the PVC.
