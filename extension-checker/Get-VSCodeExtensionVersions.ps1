function Get-VSCodeExtensionVersions {
    <#
    .SYNOPSIS
        Queries the VSCode Marketplace for extension metadata and returns
        the display name and all versions with their release dates.

    .PARAMETER ExtensionIds
        One or more extension identifiers in 'publisher.extensionname' format.
        e.g. 'esbenp.prettier-vscode', 'ms-python.python'

    .EXAMPLE
        Get-VSCodeExtensionVersions -ExtensionIds 'esbenp.prettier-vscode', 'ms-python.python'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]] $ExtensionIds
    )

    $apiUrl = 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery'

    $headers = @{
        'Content-Type' = 'application/json'
        'Accept'       = 'application/json;api-version=7.2-preview.1'
        'User-Agent'   = 'PowerShell/VSCodeMarketplaceChecker'
    }

    # Build one criterion per extension - the API supports batching them all in
    # a single request using filterType 7 (ExtensionName)
    $criteria = $ExtensionIds | ForEach-Object {
        @{ filterType = 7; value = $_ }
    }

    $body = @{
        filters = @(
            @{
                criteria   = $criteria
                pageNumber = 1
                pageSize   = $ExtensionIds.Count
                sortBy     = 0
                sortOrder  = 0
            }
        )
        flags = 1   # IncludeVersions flag - returns all versions not just latest
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -UseBasicParsing
    }
    catch {
        Write-Error "Marketplace API call failed: $_"
        return
    }

    $results = foreach ($extension in $response.results.extensions) {
        $versions = $extension.versions | ForEach-Object {
            [pscustomobject]@{
                Version     = $_.version
                ReleaseDate = [datetime]::Parse($_.lastUpdated)
            }
        }

        [pscustomobject]@{
            ExtensionId  = "$($extension.publisher.publisherName).$($extension.extensionName)"
            DisplayName  = $extension.displayName
            Publisher    = $extension.publisher.publisherName
            Versions     = $versions
        }
    }

    return $results
}