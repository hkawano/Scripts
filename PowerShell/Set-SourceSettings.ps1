param
(
	$directory = $(read-host "Enter local output directory"),
	$datacenter = $(read-host "Enter datacenter"),
	[switch]$roles,
	[switch]$permissions,
	[switch]$folders,
	[switch]$vms
)

function make-ParentFolder
{
	Param
	(
		$inFolderArray,
		$folderType
	)
	switch ($folderType)
	{
		"HostAndCluster"{$folderString = "Host"}
		"VM"{$folderString = "VM"}
		"Datastore"{$folderString = "Datastore"}
		"Network"{$folderString = "Network"}
		"Datacenter"{$folderString = "Datacenter"}
		default {write-error "Unknown folder type: $folderType";exit 23}
	}
	$parentFolder = get-datacenter $datacenter | get-folder $folderString
	foreach ($thisSubFolder in $inFolderArray)
	{
		if (!($parentFolder | get-folder $thisSubFolder -noRecursion -erroraction silentlycontinue))
		{
			$ParentFolder = $parentFolder | new-folder $thisSubFolder
		}
		else
		{
			$ParentFolder = $ParentFolder | get-folder $thisSubFolder -noRecursion
		}
	}
	$ParentFolder
}

$directory = $directory.trim("\") #" fix the gistit syntax highlighting

#Rebuild Folder Structure
if ($folders)
{
	$folderArray = import-clixml $directory\$($datacenter)-folders.xml
	$i = 0
	foreach ($thisFolder in $folderArray)
	{
		write-progress -Activity "Creating Folders" -percentComplete ($i / $folderArray.count * 100)
		make-ParentFolder -inFolderArray $thisFolder.path -folderType "VM"
		$i++
	}
}

#Rebuild Roles
if ($roles)
{
	$allRoles = import-clixml $directory\$($datacenter)-roles.xml
	$i = 0
	foreach ($thisRole in $allRoles)
	{
		write-progress -Activity "Creating Roles" -percentComplete ($i / $allRoles.count * 100)
		if (!(get-virole $thisRole.name -erroraction silentlycontinue))
		{
			new-virole -name $thisRole.name -privilege (get-viprivilege -id $thisRole.PrivilegeList) -erroraction silentlycontinue
		}
		$i++
	}
}

#Rebuild Permissions
if ($permissions)
{
	$allPermissions = import-clixml $directory\$($datacenter)-permissions.xml
	$i = 0
	foreach ($thisPermission in $allPermissions)
	{
		write-progress -Activity "Creating Permissions" -percentComplete ($i / $allPermissions.count * 100)
		$target = ""
		$thisPermission.type
		switch ($thisPermission.type)
		{
			"Folder" {
				if ($thisPermission.entity -eq "Datacenters") {$target = get-folder Datacenters}
				else {$target = make-Parentfolder -inFolderArray $thisPermission.entity -folderType $thisPermission.folderType}
				}
			"VirtualMachine" {$target = get-datacenter $datacenter | get-vm $thisPermission.entity}
			"VM" {$target = get-datacenter $datacenter | get-vm $thisPermission.entity}
			"Datacenter" {$target = get-datacenter $thisPermission.entity}
			"ClusterComputeResource" {$target = get-cluster $thisPermission.entity}
			Default {write-error "Unexpected permission target, $($thisPermission.type)"}
		}
		
		if ($target)
		{
			$target | new-vipermission -role $thisPermission.role -principal $thisPermission.principal -propagate $thisPermission.propagate
		}
		else
		{
			write-error "Unable to find permission object $($thisPermission.entity)"
		}
		$i++
	}
}

#Replace VMs
if ($VMs)
{
	$allVMs = import-clixml $directory\$($datacenter)-VMs.xml
	$allVApps = $NULL
	$i = 0
	if (test-path $directory\vApps.xml){$allVApps = import-clixml $directory\$($datacenter)-vApps.xml}
	foreach ($thisVM in $allVMs)
	{
		write-progress -Activity "Placing VMs" -percentComplete ($i / $allVMs.count * 100)
		if ($foundVM = get-vm $thisVM.name -erroraction silentlycontinue)
		{
			$ParentFolder = make-ParentFolder -inFolderArray $thisVM.folderPath -folderType "VM"
			$foundVM | move-vm -location $ParentFolder	
		}
		$i++
	}
	foreach ($thisVApp in $allVApps)
	{
		echo "===$($thisVApp.name)==="
		$thisvApp.VMs
	}
	#Convert Template VMs back to Templates
}

if (!($VMs -or $folders -or $permissions -or $roles))
{
	echo "Please use one or more of the -VMs, -Folders, -Permissions, or -Roles switches to do something"
}
