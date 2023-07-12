<#
.SYNOPSIS
    Script used for automatically adding reviewers to pull requests that touch files containing unsafe code.

.DESCRIPTION
    Script used in the build pipeline to inspect the files being changed and, if they contain unsafe code,
    automatically add the unsafe reviewers to the required reviewers of the pull request.

    The following build pipline environment variables need to be defined:
    ACCESS_TOKEN                - The PAT used to query GitHub API.
    PULL_REQUEST_ID             - The ID of the pull request that caused this build.
#>

# Group and person ids can be obtained easily from the Azure DevOps CLI via `az devops team list` or `az devops team show`, and for script simplicity are hardcoded here
$reviewers = "hvlite-unsafe-reviewers" # HvLite Unsafe Reviewers
$approvers = "hvlite-unsafe-approvers" # HvLite Unsafe Approvers

# Setup header and URI
$headers = @{ 
    Accept = "application/vnd.github+json"
    Authorization = "Bearer $env:ACCESS_TOKEN" 
}
$uri = "https://api.github.com/repos/microsoft/hvlite/pulls/$env:PULL_REQUEST_ID"
Write-Host "URI: $uri"

function Add-Reviewer($group_id, $required)
{
    $requestBody = @{
        "team_reviewers" = $group_id
    }

    $jsonBody = ConvertTo-Json $requestBody

    # $url = "${endpointBase}/reviewers/${group_id}?api-version=6.0"
    $url = "$uri/requested_reviewers"

    Invoke-RestMethod $url -Method Put -Headers $headers -Body $jsonBody -ContentType application/json
}

function Remove-Reviewer($group_id)
{
    $url = "${endpointBase}/reviewers/${group_id}?api-version=6.0"

    Invoke-RestMethod $url -Method Delete -Headers $headers
}



# Make the API request
$response = Invoke-RestMethod -Uri $uri -Headers $headers

# Ensure that the target branch is present for comparisons.
git fetch --progress origin $response.head.ref

git --version
git branch
git diff ("origin/" + $response.head.ref)

# This GitHub action only triggers when target is main, so hard coding here is fine
$changed_files = git diff --name-only ("origin/" + $response.head.ref) "origin/main"
Write-Host "Changed files: $changed_files"

$assignees = $response.assignees
Write-Host "assignees"
Write-Host ($assignees | Format-Table | Out-String)
$requested_reviewers = $response.requested_reviewers
Write-Host "requested_reviewers"
Write-Host ($requested_reviewers | Format-Table | Out-String)
$requested_teams = $response.requested_teams
Write-Host "requested_teams"
Write-Host ($requested_teams | Format-Table | Out-String)

foreach ($file in $changed_files) {
    if ((Test-Path $file) -and ($file.EndsWith(".rs")) -and (Select-String -Path $file -Pattern "unsafe ")) {
        $unsafe = $true
        Write-Host "Found unsafe in $file"
    }
}

Write-Host "response: $response"

$alreadyAdded = $false
foreach ($reviewer in $response.requested_teams) {
    Write-Host "${reviewer.slug}"
    if ($reviewer.id -eq $reviewers) { # TODO: change this to approvers
        $alreadyAdded = $true
        break
    }
}

if ($unsafe) {
    throw "Unsafe reviewers required"
}
