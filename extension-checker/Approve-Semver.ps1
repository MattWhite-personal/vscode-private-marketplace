#Requires -Version 5.1
<#
.SYNOPSIS
    Validates semantic versions and returns a list of approved versions based on age thresholds.

.DESCRIPTION
    Given a collection of versions with their release dates, this script:
      - Validates each version against the SemVer 2.0 specification
      - Approves versions where:
          Major component has been released for >= 30 days
          Minor component has been released for >= 7 days
          Patch component has been released for >= 3 days

    The approval thresholds apply to the *earliest* release date seen for each
    major, major.minor, and full major.minor.patch combination respectively.

.PARAMETER Versions
    An array of objects (or hashtables) with at least two properties:
        Version     - the semver string  (e.g. "1.4.2")
        ReleaseDate - a [datetime]-parseable value

.PARAMETER ReferenceDate
    The date to measure age against. Defaults to today (UTC).

.EXAMPLE
    $data = @(
        [pscustomobject]@{ Version = '1.0.0'; ReleaseDate = (Get-Date).AddDays(-45) }
        [pscustomobject]@{ Version = '1.1.0'; ReleaseDate = (Get-Date).AddDays(-10) }
        [pscustomobject]@{ Version = '1.1.1'; ReleaseDate = (Get-Date).AddDays(-4)  }
        [pscustomobject]@{ Version = '1.1.2'; ReleaseDate = (Get-Date).AddDays(-1)  }
        [pscustomobject]@{ Version = '2.0.0'; ReleaseDate = (Get-Date).AddDays(-5)  }
        [pscustomobject]@{ Version = 'not-a-version'; ReleaseDate = (Get-Date)       }
    )
    .\Approve-SemVer.ps1 -Versions $data

.OUTPUTS
    PSCustomObject with properties:
        Approved  - array of approved version entries (Version, ReleaseDate, AgeDays)
        Rejected  - array of entries that failed the age thresholds (with RejectionReason)
        Invalid   - array of entries that failed SemVer validation
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [object[]] $Versions,

    [Parameter()]
    [datetime] $ReferenceDate = [datetime]::UtcNow
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Region: SemVer validation
# ---------------------------------------------------------------------------

# SemVer 2.0 regex (https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string)
# Captures: major, minor, patch, pre-release (optional), build-metadata (optional)
$pattern = @'
^(?<major>0|[1-9]\d*)
 \.(?<minor>0|[1-9]\d*)
 \.(?<patch>0|[1-9]\d*)
 (?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?
 (?:\+(?<buildmeta>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
'@ -replace '\s', ''

$SemVerRegex = [regex]::new($pattern)

function Test-SemVer {
    <#
    .SYNOPSIS  Returns $true if the string is a valid SemVer 2.0 version.
    #>
    [OutputType([bool])]
    param ([string] $Version)
    return $SemVerRegex.IsMatch($Version)
}

function ConvertTo-SemVerParts {
    <#
    .SYNOPSIS  Parses a valid SemVer string into its components.
    .OUTPUTS   Hashtable with keys: Major, Minor, Patch, PreRelease, BuildMeta
    #>
    param ([string] $Version)
    $m = $SemVerRegex.Match($Version)
    return [pscustomobject]@{
        Major      = [int]   $m.Groups['major'].Value
        Minor      = [int]   $m.Groups['minor'].Value
        Patch      = [int]   $m.Groups['patch'].Value
        PreRelease = $m.Groups['prerelease'].Value   # empty string if absent
        BuildMeta  = $m.Groups['buildmeta'].Value    # empty string if absent
    }
}

# ---------------------------------------------------------------------------
# Region: Approval thresholds (days)
# ---------------------------------------------------------------------------
$Thresholds = @{
    Major = 30
    Minor = 7
    Patch = 3
}

# ---------------------------------------------------------------------------
# Region: Build earliest-release-date lookup tables
# ---------------------------------------------------------------------------
# Iterate all *valid* entries first so we can determine the earliest date each
# major / major.minor / full version was ever seen.

$earliestMajor      = @{}   # key: "major"           -> earliest [datetime]
$earliestMinor      = @{}   # key: "major.minor"     -> earliest [datetime]
$earliestPatch      = @{}   # key: "major.minor.patch" -> earliest [datetime]

$validEntries   = [System.Collections.Generic.List[object]]::new()
$invalidEntries = [System.Collections.Generic.List[object]]::new()

foreach ($entry in $Versions) {
    $versionStr  = [string] $entry.Version
    $releaseDate = [datetime]::Parse($entry.lastUpdated.ToString())

    if (-not (Test-SemVer -Version $versionStr)) {
        $invalidEntries.Add([pscustomobject]@{
            Version          = $versionStr
            ReleaseDate      = $releaseDate
            ValidationError  = "Does not conform to SemVer 2.0 specification"
        })
        continue
    }

    $parts = ConvertTo-SemVerParts -Version $versionStr

    $keyMajor = "$($parts.Major)"
    $keyMinor = "$($parts.Major).$($parts.Minor)"
    $keyPatch = "$($parts.Major).$($parts.Minor).$($parts.Patch)"

    if (-not $earliestMajor.ContainsKey($keyMajor) -or $releaseDate -lt $earliestMajor[$keyMajor]) {
        $earliestMajor[$keyMajor] = $releaseDate
    }
    if (-not $earliestMinor.ContainsKey($keyMinor) -or $releaseDate -lt $earliestMinor[$keyMinor]) {
        $earliestMinor[$keyMinor] = $releaseDate
    }
    if (-not $earliestPatch.ContainsKey($keyPatch) -or $releaseDate -lt $earliestPatch[$keyPatch]) {
        $earliestPatch[$keyPatch] = $releaseDate
    }

    $validEntries.Add([pscustomobject]@{
        Version     = $versionStr
        ReleaseDate = $releaseDate
        Parts       = $parts
    })
}

# ---------------------------------------------------------------------------
# Region: Evaluate approval for each valid entry
# ---------------------------------------------------------------------------
$approvedEntries  = [System.Collections.Generic.List[object]]::new()
$rejectedEntries  = [System.Collections.Generic.List[object]]::new()

foreach ($entry in $validEntries) {
    $parts = $entry.Parts

    $keyMajor = "$($parts.Major)"
    $keyMinor = "$($parts.Major).$($parts.Minor)"
    $keyPatch = "$($parts.Major).$($parts.Minor).$($parts.Patch)"

    $majorAgeDays = ($ReferenceDate - $earliestMajor[$keyMajor]).TotalDays
    $minorAgeDays = ($ReferenceDate - $earliestMinor[$keyMinor]).TotalDays
    $patchAgeDays = ($ReferenceDate - $earliestPatch[$keyPatch]).TotalDays

    $reasons = [System.Collections.Generic.List[string]]::new()

    if ($majorAgeDays -lt $Thresholds.Major) {
        $reasons.Add("Major v$keyMajor is only $([math]::Floor($majorAgeDays))d old (need $($Thresholds.Major)d)")
    }
    if ($minorAgeDays -lt $Thresholds.Minor) {
        $reasons.Add("Minor v$keyMinor is only $([math]::Floor($minorAgeDays))d old (need $($Thresholds.Minor)d)")
    }
    if ($patchAgeDays -lt $Thresholds.Patch) {
        $reasons.Add("Patch v$keyPatch is only $([math]::Floor($patchAgeDays))d old (need $($Thresholds.Patch)d)")
    }

    $result = [pscustomobject]@{
        Version      = $entry.Version
        ReleaseDate  = $entry.ReleaseDate
        MajorAgeDays = [math]::Round($majorAgeDays, 1)
        MinorAgeDays = [math]::Round($minorAgeDays, 1)
        PatchAgeDays = [math]::Round($patchAgeDays, 1)
        PreRelease   = $parts.PreRelease
    }

    if ($reasons.Count -eq 0) {
        $approvedEntries.Add($result)
    } else {
        $result | Add-Member -NotePropertyName RejectionReason -NotePropertyValue ($reasons -join '; ')
        $rejectedEntries.Add($result)
    }
}

# ---------------------------------------------------------------------------
# Region: Output
# ---------------------------------------------------------------------------
$output = [pscustomobject]@{
    Approved = $approvedEntries.ToArray()
    Rejected = $rejectedEntries.ToArray()
    Invalid  = $invalidEntries.ToArray()
}

Write-Host ""
Write-Host "=== SemVer Approval Report (Reference: $($ReferenceDate.ToString('yyyy-MM-dd'))) ===" -ForegroundColor Cyan

Write-Host "`n[APPROVED] ($($output.Approved.Count))" -ForegroundColor Green
$output.Approved | Format-Table Version, ReleaseDate, MajorAgeDays, MinorAgeDays, PatchAgeDays, PreRelease -AutoSize

Write-Host "[REJECTED] ($($output.Rejected.Count))" -ForegroundColor Yellow
$output.Rejected | Format-Table Version, ReleaseDate, MajorAgeDays, MinorAgeDays, PatchAgeDays, RejectionReason -AutoSize

Write-Host "[INVALID]  ($($output.Invalid.Count))" -ForegroundColor Red
$output.Invalid  | Format-Table Version, ReleaseDate, ValidationError -AutoSize

return $output

# ---------------------------------------------------------------------------
# Region: Example usage (remove or comment out in production)
# ---------------------------------------------------------------------------
<#
$sampleData = @(
    [pscustomobject]@{ Version = '1.0.0';        ReleaseDate = (Get-Date).AddDays(-60) }  # APPROVED
    [pscustomobject]@{ Version = '1.1.0';        ReleaseDate = (Get-Date).AddDays(-10) }  # APPROVED
    [pscustomobject]@{ Version = '1.1.1';        ReleaseDate = (Get-Date).AddDays(-4)  }  # APPROVED
    [pscustomobject]@{ Version = '1.1.2';        ReleaseDate = (Get-Date).AddDays(-1)  }  # REJECTED  (patch too new)
    [pscustomobject]@{ Version = '2.0.0';        ReleaseDate = (Get-Date).AddDays(-5)  }  # REJECTED  (major too new)
    [pscustomobject]@{ Version = '2.0.1';        ReleaseDate = (Get-Date).AddDays(-3)  }  # REJECTED  (major too new)
    [pscustomobject]@{ Version = '3.0.0-beta.1'; ReleaseDate = (Get-Date).AddDays(-90) }  # APPROVED (pre-release, still valid semver)
    [pscustomobject]@{ Version = '1.2';          ReleaseDate = (Get-Date).AddDays(-30) }  # INVALID  (missing patch)
    [pscustomobject]@{ Version = 'v1.0.0';       ReleaseDate = (Get-Date).AddDays(-30) }  # INVALID  (leading 'v')
    [pscustomobject]@{ Version = 'not-semver';   ReleaseDate = (Get-Date)              }  # INVALID
)

.\Approve-SemVer.ps1 -Versions $sampleData
#>