<#
        .SYNOPSIS
                Autogenerate documentation for your Azure Synapse Pipelines and Triggers.

        .DESCRIPTION
                Created: 2023-09-15
                        By: Randy Slavey

                This script will get the contents of your Synapse Workspace repo and generate documentation based on names and descriptions of pipelines and activities.
                This script should be run from the folder where you want the documentation stored.

        .PARAMETER PipelineSectionTitle
                The name of the section in your readme.md file where you want the pipelines to be documented.

        .PARAMETER ReadMeFilePath
                The name of your readme file. Default is readme.md.

        .PARAMETER ReadMeIntroFilePath
                The name of your readme intro file. Default is readme_intro.md. This will be prepended to the readme file.

        .PARAMETER RepoPath
                The path to your Synapse workspace repo. Default is the current path. This should be relative to the location of this script.
                E.g., if you are storing your documentation in a subfolder of the repo called "documentation\generatedDocs\", you would set the target to "..\..\"
                Do not set a static path, as the readme file will contain relative links so the markdown will render correctly in GitHub.

        .PARAMETER OverwriteExistingReadme
                If you have an existing readme file, this will overwrite it. Default is false.

        .PARAMETER PipelineHeaderLevel
                The header level for the pipeline section. 1 is the largest, 6 is the smallest. Default is 2.

#>

Param (
    [parameter(Mandatory = $false)]
    [string]$PipelineSectionTitle = "Pipelines",
    [parameter(Mandatory = $false)]
    [string]$ActivitiesSectionTitle = "Activities",
    [parameter(Mandatory = $false)]
    [string]$TriggersSectionTitle = "Triggers",
    [parameter(Mandatory = $false)]
    [string]$ReadMeFilePath = ".\readme.md",
    [parameter(Mandatory = $false)]
    [string]$ReadMeIntroFilePath = ".\readme_intro.md",
    [parameter(Mandatory = $false)]
    [string]$RepoPath = ".\",
    [parameter(Mandatory = $false)]
    [bool]$OverwriteExistingReadme = $false,
    [parameter(Mandatory = $false)]
    [bool]$PipelineHeaderLevel = 2
)

# This content will be prepended to the readme.md file. It should be your introduction to the documentation including best practices, etc.
if (-not (Test-Path -Path $ReadMeIntroFilePath)) {
    Set-Content -Path $ReadMeIntroFilePath -Value "# ADD YOUR INTRO HERE`n`n"
}

if ((Test-Path -Path $ReadMeFilePath) -and (-not($OverwriteExistingReadme))) {
    Write-Host "You have an existing readme file at $($ReadMeFilePath). Either delete it or set the OverwriteExistingReadme parameter to true." -ForegroundColor Red
    Exit
}

Get-Content -Path $ReadMeIntroFilePath | Set-Content -Path $ReadMeFilePath -Force

$pipelinePath = Join-Path -Path $RepoPath -ChildPath "pipeline"
$triggerPath = Join-Path -Path $RepoPath -ChildPath "trigger"

if ((-not(Test-Path -Path $pipelinePath)) -or (-not(Test-Path -Path $triggerPath))) {
    Write-Host "The pipeline and trigger paths do not exist. Please check your RepoPath parameter." -ForegroundColor Red
    Exit
}

# Get pipelines and triggers
$pipelines = (Get-ChildItem -Path $pipelinePath -Filter *.json) | ForEach-Object -Process { 
    [PSCustomObject]@{
        Path    = $_.FullName -replace [regex]::Escape($PWD.Path) -replace '^\\'
        Content = Get-Content $_.FullName | ConvertFrom-Json 
    }
}
$triggers = (Get-ChildItem -Path $triggerPath -Filter *.json) | ForEach-Object -Process { 
    [PSCustomObject]@{
        Path    = $_.FullName -replace [regex]::Escape($PWD.Path) -replace '^\\'
        Content = Get-Content $_.FullName | ConvertFrom-Json 
    }
}

# Group pipelines by their folders
$groupedPipelines = $pipelines | Group-Object -Property { $_.Content.properties.folder.name }

# Build documentation
$documentation = [System.Text.StringBuilder]::new()

[void]$documentation.AppendLine( "$("#" * $PipelineHeaderLevel) $($PipelineSectionTitle) `n" )
foreach ($folderGroup in $groupedPipelines) {
    [void]$documentation.AppendLine( "$("#" * ($PipelineHeaderLevel + 1)) $($folderGroup.Name -eq '' ? "No Folder" : "/$($folderGroup.Name)")`n" )
    foreach ($pipeline in $folderGroup.Group) {
        [void]$documentation.AppendLine( "$("#" * ($PipelineHeaderLevel + 1)) [$($pipeline.Content.name)]($([uri]::EscapeDataString($pipeline.Path)))`n" )
        [void]$documentation.AppendLine( "Description: $($pipeline.Content.properties.description ?? "No pipeline description")`n" )
        $pipelineTriggers = $triggers | Where-Object { $_.Content.properties.pipelines.pipelineReference.referenceName -eq $pipeline.Content.name }
        [void]$documentation.AppendLine( "$("#" * ($PipelineHeaderLevel + 2)) $($ActivitiesSectionTitle)`n" )
        foreach ($pipelineActivity in $pipeline.Content.properties.activities) {
            [void]$documentation.AppendLine(" - [$($pipelineActivity.name)]($([uri]::EscapeDataString($pipeline.Path))): $($pipelineActivity.description ?? "No description")" )
        }
        if ($null -ne $pipelineTriggers) {
            [void]$documentation.AppendLine( "$("#" * ($PipelineHeaderLevel + 2)) $($TriggersSectionTitle)`n" )
        }
        foreach ($trigger in $pipelineTriggers) {
            $triggersForThisPipeline = $trigger.Content.properties.pipelines | Where-Object { $_.pipelineReference.referenceName -eq $pipeline.Content.name }
            foreach ($triggerForThisPipeline in $triggersForThisPipeline) {
                [void]$documentation.AppendLine(" - [$($trigger.Content.name)]($([uri]::EscapeDataString($trigger.Path)))" )
                if ($null -ne $triggersForThisPipeline.parameters) {
                    [void]$documentation.AppendLine("   - Parameters:" )
                    foreach ($parameter in $triggersForThisPipeline.parameters) {
                        [void]$documentation.AppendLine("     - $($parameter | ConvertTo-Json)" )
                    }
                }
            }
        }
    }
}

Add-Content -Path $ReadMeFilePath -Value $documentation.ToString()
