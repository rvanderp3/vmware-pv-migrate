# Configure target datastore
export TARGET_DATASTORE="workload_share_vcs8eworkload_FmUtJ"
export TARGET_FOLDER="migrated"
export PVC=alertmanager-main-db-alertmanager-main-2
export TARGET_PVC=migrated-$PVC

function MIGRATE_PV_GET_RESOURCES() {
    echo getting PVC and PVs to be migrated
    oc get pvc $VC -o json > /tmp/pvc.json    
    export SOURCE_PV=$(cat /tmp/pvc.json | jq -r '.spec.volumeName')
    export TARGET_PV=migrated-$SOURCE_PV
    oc get pv $SOURCE_PV -o json > /tmp/pv.json            
}

function MIGRATE_PV_CREATE_TEMP_PV_PVC() {
    echo creating temporary PV and PVC on the target datastore($TARGET_DATASTORE)
    RAW_CAPACITY=$(cat /tmp/pv.json | jq -r .spec.capacity.storage)
    # Provision storage in the datastore
    govc datastore.disk.create -ds $TARGET_DATASTORE -size ${RAW_CAPACITY::-1} $TARGET_FOLDER/$TARGET_PV.vmdk

    # Create new PV on the desired datastore
    cat /tmp/pv.json | jq -r '.spec.vsphereVolume.volumePath="[$TARGET_DATASTORE] $TARGET_FOLDER/$TARGET_PV.vmdk"
    | del(.metadata.managedFields) 
    | del(.status) 
    | del(.metadata.creationTimestamp)
    | del(.spec.claimRef)
    | del(.metadata.uid)
    | del(.metadata.resourceVersion)
    | .spec.persistentVolumeReclaimPolicy="Retain"
    | .metadata.name="$TARGET_PV"' | envsubst | oc create -f -

    # Build temporary PVC to allow copying of existing PVC to new PVC
    cat /tmp/pvc.json | jq -r '.spec.volumeName="$TARGET_PV"
    | del(.metadata.managedFields) 
    | del(.status) 
    | del(.metadata.creationTimestamp)
    | del(.metadata.uid)
    | del(.metadata.resourceVersion)
    | .metadata.name="$TARGET_PVC"' | envsubst | oc create -f -
}

function MIGRATE_PV_MIGRATE_DATA() {
    echo migrating data to target datastore
    # Get tools image    
    export TOOLS_IMAGE=$(oc get istag -n openshift tools:latest -o=jsonpath='{.tag.from.name}')

    # Create elevated service 
    oc create sa migration
    oc adm policy add-scc-to-user privileged -z migration

    # run rsync job to migrate data
    cat migrate-job.yaml | envsubst | oc create -f -

    echo check pod logs from 'pv-migrate-...' pods. once pods report as 'complete', proceed to the next step.
}

function MIGRATE_PV_CLEAN_UP_TEMPORARY_RESOURCES() {
    # remove privileged scc and service account
    oc adm policy remove-scc-from-user privileged -z migration
    oc delete sa migration

    oc delete job pv-migrate
    oc delete pvc $TARGET_PVC    
    oc delete pv $TARGET_PV
}

function MIGRATE_PV_SWITCH_TO_MIGRATED_DATA() {
    echo changing reclaim policy on the source PV to 'Retain'
    echo original data is located at $(cat /tmp/pv.json | jq -r '.spec.vsphereVolume.volumePath')
    oc patch pv $SOURCE_PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
    oc delete pvc $PVC
    oc delete pv $SOURCE_PV    

    echo creating new PV pointing to the migrated vmdk
    cat /tmp/pv.json | jq -r '.spec.vsphereVolume.volumePath="[$TARGET_DATASTORE] $TARGET_FOLDER/$TARGET_PV.vmdk"
    | del(.metadata.managedFields) 
    | del(.status) 
    | del(.metadata.creationTimestamp)
    | del(.spec.claimRef)
    | del(.metadata.uid)
    | del(.metadata.resourceVersion)
    | .spec.persistentVolumeReclaimPolicy="Retain"
    | .metadata.name="$TARGET_PV"' | envsubst | oc create -f -

    echo creating new PVC to claim PV
    echo $(cat /tmp/pvc.json | jq -r '.spec.volumeName="migrated-$SOURCE_PV"
    | del(.metadata.managedFields) 
    | del(.status) 
    | del(.metadata.creationTimestamp)
    | del(.metadata.uid)
    | del(.metadata.resourceVersion)
    | .metadata.name="$PVC"' | envsubst) | oc create -f -
}
