#!/bin/bash

counter=0
usage="\n$(basename "$0") [-h] [-d] [-r REGION] [-p PROFILE] -- clean up bulk items
\n
\nwhere:
\n  -h show this help text
\n  -r set the region (default is all subscribed regions)
\n  -p set the CLI profile to use
\n  -d dry run - no commands executed
\n"
	
while getopts 'hdp:r:' option; do
  case "${option}"  in
    h) echo -e $usage
       exit
       ;;
    p) PROFILE=${OPTARG};;
    r) REGION=${OPTARG};;
    d) dryrun=TRUE
  esac
done


if [ -z "$PROFILE" ]
then
  PROFILE="default"
fi

if [ -z "$REGION" ]
then 
  regList=($(oci iam region-subscription list --profile $PROFILE --query 'data[*]."region-name"' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
else
  regList=$REGION
fi

#Print details of the activity and prompt for confirmation
clear
echo -e "\n========================================================="
echo -e "\nRegions to be used: " && printf '%s,' "${regList[@]}"
echo -e "\nProfile to be used: "$PROFILE
echo ""
read -p "Would you like to continue? " -n 1 -r
echo 

if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "Ok - here we go!"
else
  exit 1
fi

if [[ $dryrun == TRUE ]]
then
  echo "This is ONLY a test!"
  echo "vbuID=($(oci search resource structured-search --query-text \"QUERY VolumeBackup resources\" --profile $PROFILE --region $REGION --query \'data.items[?contains(\`[\"AVAILABLE\", \"UNAVAILABLE\"]\`, \"lifecycle-state\")].identifier\' | sed s\'/[\[\",]//g\' | sed -e \'s/\]//g\'))"
echo "printf \'%s\n\' \"${vbuID[@]}\""
else
#==============================================================
# Time to do some damage
# this section is going to delete a lot of stuff
#==============================================================
for r in "${regList[@]}"; do
  echo "Region: " $r

#Delete compute instances
    echo "Deleting compute instances" && sleep 3
    instID=($(oci search resource structured-search --profile $PROFILE --region $r --query-text "QUERY instance resources where lifeCycleState = 'RUNNING'" --query 'data.items[*].identifier' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
    #printf '%s\n' "${instID[@]}"
      for i in "${instID[@]}"; do
        counter=$((counter+1))
        echo "Deleting resource with ID: $i"
        oci compute instance terminate --profile $PROFILE --region $r --instance-id $i --force
      done
      echo "Compute instances in $r have been deleted.  Moving on..." && echo && echo "=====" && echo

#Delete block volumes
    echo "Deleting block volumes" && sleep 3
    bvID=($(oci search resource structured-search --profile $PROFILE --region $r --query-text "QUERY volume resources" --query 'data.items[?contains(`["AVAILABLE", "UNAVAILABLE"]`, "lifecycle-state")].identifier' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
    #printf '%s\n' "${bvID[@]}"
      for i in "${bvID[@]}"; do
        counter=$((counter+1))
        echo "Deleting resource with ID: $i"
        oci bv volume delete --profile $PROFILE --region $r --volume-id $i --force
      done
      echo "Block volumes in $r have been deleted.  Moving on..." && echo && echo "=====" && echo

#Delete block volume backups
    echo "Deleting block volume backups" && sleep 3
    vbuID=($(oci search resource structured-search --profile $PROFILE --region $r --query-text "QUERY VolumeBackup resources" --query 'data.items[?contains(`["AVAILABLE", "UNAVAILABLE"]`, "lifecycle-state")].identifier' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
    #printf '%s\n' "${vbuID[@]}"
      for i in "${vbuID[@]}"; do 
        counter=$((counter+1))
        echo "Deleting resource with ID: $i"
	oci bv backup delete --profile $PROFILE --region $r --volume-backup-id $i --force
      done
      echo "Block volume backups in $r have been deleted.  Moving on..." && echo && echo "=====" && echo

#Delete autonomous database instances
    echo "Delete Autonomous databases (ATP & ADW)" && sleep 3
    adbID=($(oci search resource structured-search --profile $PROFILE --region $r --query-text "QUERY AutonomousDatabase resources" --query 'data.items[?contains(`["AVAILABLE", "UNAVAILABLE"]`, "lifecycle-state")].identifier' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
      for i in "${adbID[@]}"; do
	counter=$((counter+1))
        echo "Deleting resource with ID: $i"
        oci db autonomous-database delete --profile $PROFILE --region $r --autonomous-database-id $i --force
      done
      echo "Autonomous Database Instances in $r have been deleted.  Moving on..." && echo && echo "=====" && echo

#Empty and delete object storage buckets
    echo "Empty and delete object storage buckets" && sleep 3
    bID=($(oci search resource structured-search --profile $PROFILE --region $r --query-text "QUERY bucket resources" --query 'data.items[?contains("display-name", `#`) == `false`]."display-name"' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
    for i in "${bID[@]}"; do
      counter=$((counter+1))
      echo "Deleting resource with ID: $i"
      oci os object bulk-delete --profile $PROFILE --region $r -bn $i --force
      # Delete all pre-authenticated requests
      parID=($(oci os preauth-request list --profile $PROFILE --region $r -bn $i --query 'data[*].id' | sed s'/[\[",]//g' | sed -e 's/\]//g'))
	for p in "${parID[@]}"; do
	  oci os preauth-request delete --profile $PROFILE --region $r -bn $i --par-id $p --force
  	done
      oci os bucket delete --profile $PROFILE --region $r -bn $i --force
    done
    echo "All object storage buckets have been deleted.  Moving on..." && echo && echo "=====" && echo

## End of primary FOR loop
  done
fi

echo && echo "===================================================" && echo
echo "Deletion complete.  A total of $counter resources were removed."
echo 
