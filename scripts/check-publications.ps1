<#
  Looks for publications that are not yet in cv.qmd.

  Sources: the ORCID record, Crossref works tagged with that ORCID, a
  Crossref search by author name, and a PubMed author search. (Google
  Scholar has no API and blocks automated queries, so it is not used.)

  A paper counts as listed when 90% of the words in its title appear in
  one CV entry. The bar is high on purpose: many of these titles share
  "scale mixture of skew-normal linear mixed models", and at 80% different
  papers pass for each other.

  Writes a markdown report to -OutFile only when something needs attention:
    - a paper found online that the CV does not list, or
    - a paper the CV lists under "Papers submitted" that now has a DOI.

  Entries to stop reporting (a namesake on PubMed, an abstract, a dataset)
  go in scripts/publication-ignore.txt, one DOI or title per line.

  Runs on Windows PowerShell 5.1 and PowerShell 7.
#>
param(
  [string]$CvPath     = "cv.qmd",
  [string]$IgnorePath = "scripts/publication-ignore.txt",
  [string]$OutFile    = "publication-report.md",
  [string]$Orcid      = "0000-0002-5724-8918",
  [string]$PubMedTerm = "Schumacher FL[au]",
  [int]$Days          = 365
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = @{ "User-Agent" = "cv-publication-check (https://github.com/fernandalschumacher/cv)" }

# Crossref and PubMed rate-limit bursts (HTTP 429); wait and retry.
function Get-Json([string]$url, $headers = $ua) {
  foreach ($wait in 0, 5, 20) {
    Start-Sleep -Seconds $wait
    try { return Invoke-RestMethod $url -Headers $headers }
    catch {
      $code = 0
      if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
      if ($code -ne 429 -and $code -lt 500) { throw }
      $last = $_
    }
  }
  throw $last
}

function Get-Words([string]$s) {
  $s = [regex]::Replace($s, "<[^>]+>", " ")                     # <scp>, <i> tags in Crossref titles
  $s = $s.Normalize([Text.NormalizationForm]::FormD)
  $s = [regex]::Replace($s, "\p{Mn}", "")                        # strip accents
  $s = [regex]::Replace($s.ToLowerInvariant(), "[^a-z0-9]+", " ")
  # Words of 4+ letters, with a plural "s" dropped ("deaths" = "death").
  return @($s.Split(" ", [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_.Length -ge 4 } |
           ForEach-Object { if ($_.Length -gt 4 -and $_ -match "[^s]s$") { $_.Substring(0, $_.Length - 1) } else { $_ } })
}

# Share of the title's words found in the best-matching CV entry.
function Get-Match([string]$title, $entries) {
  $words = Get-Words $title
  if ($words.Count -eq 0) { return 0 }
  $best = 0
  foreach ($e in $entries) {
    $hit = @($words | Where-Object { $e.Words.Contains($_) }).Count / $words.Count
    if ($hit -gt $best) { $best = $hit }
  }
  return $best
}

# --- CV entries, split into published and submitted ----------------------

$cv = Get-Content $CvPath -Encoding UTF8
$section = ""
$published = @(); $submitted = @()
foreach ($line in $cv) {
  if ($line -match "^# (.+)") { $section = $Matches[1] }
  if ($line -notmatch "^\d+\. ") { continue }
  $set = New-Object "System.Collections.Generic.HashSet[string]"
  foreach ($w in (Get-Words $line)) { [void]$set.Add($w) }
  $entry = @{ Text = $line; Words = $set }
  if ($section -eq "Publications") { $published += $entry }
  elseif ($section -like "Papers submitted*") { $submitted += $entry }
}
if ($published.Count -eq 0) { throw "No publications found in $CvPath; has the section been renamed?" }

$ignore = @()
if (Test-Path $IgnorePath) {
  $ignore = @(Get-Content $IgnorePath -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch "^\s*#" } |
              ForEach-Object { $_.Trim().ToLowerInvariant() })
}

# --- Fetch candidates ------------------------------------------------------

$since = (Get-Date).AddDays(-$Days)
$found = @{}   # key: DOI or normalised title
$errors = @()

function Add-Candidate($title, $doi, $venue, $year, $source) {
  if (-not $title) { return }
  $title = ([regex]::Replace($title, "<[^>]+>", "") -replace "\s+", " ").Trim()
  $doi = if ($doi) { $doi.ToLowerInvariant() } else { "" }
  $key = if ($doi) { $doi } else { (Get-Words $title) -join " " }
  if ($found.ContainsKey($key)) {
    if ($found[$key].Sources -notcontains $source) { $found[$key].Sources += $source }
    return
  }
  $found[$key] = @{ Title = $title; Doi = $doi; Venue = $venue; Year = $year; Sources = @($source) }
}

try {
  $r = Get-Json "https://pub.orcid.org/v3.0/$Orcid/works" (@{ Accept = "application/json" } + $ua)
  foreach ($g in $r.group) {
    $w = $g.'work-summary'[0]
    if ($w.type -ne "journal-article") { continue }
    $year = [int]$w.'publication-date'.year.value
    if ($year -lt $since.Year) { continue }
    $doi = ($w.'external-ids'.'external-id' | Where-Object { $_.'external-id-type' -eq "doi" } | Select-Object -First 1).'external-id-value'
    Add-Candidate $w.title.title.value $doi $w.'journal-title'.value $year "ORCID"
  }
} catch { $errors += "ORCID: $($_.Exception.Message)" }

try {
  $from = $since.ToString("yyyy-MM-dd")
  $r = Get-Json "https://api.crossref.org/works?filter=orcid:$Orcid,from-pub-date:$from,type:journal-article&rows=100"
  foreach ($it in $r.message.items) {
    Add-Candidate $it.title[0] $it.DOI $it.'container-title'[0] $it.issued.'date-parts'[0][0] "Crossref"
  }
} catch { $errors += "Crossref: $($_.Exception.Message)" }

# Many publishers do not tag the ORCID, so also search Crossref by name and
# keep only works with an author called Fernanda Schumacher.
try {
  $from = $since.ToString("yyyy-MM-dd")
  $r = Get-Json "https://api.crossref.org/works?query.author=Fernanda+Schumacher&filter=from-pub-date:$from,type:journal-article&rows=100"
  foreach ($it in $r.message.items) {
    $mine = $it.author | Where-Object { $_.family -eq "Schumacher" -and $_.given -like "Fernanda*" }
    if ($mine) { Add-Candidate $it.title[0] $it.DOI $it.'container-title'[0] $it.issued.'date-parts'[0][0] "Crossref (name)" }
  }
} catch { $errors += "Crossref (name): $($_.Exception.Message)" }

try {
  $term = [Uri]::EscapeDataString($PubMedTerm)
  $s = Get-Json "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=$term&datetype=pdat&reldate=$Days&retmax=100&retmode=json"
  $ids = @($s.esearchresult.idlist)
  if ($ids.Count -gt 0) {
    $sum = Get-Json "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=$($ids -join ',')&retmode=json"
    foreach ($id in $ids) {
      $a = $sum.result.$id
      $doi = ($a.articleids | Where-Object { $_.idtype -eq "doi" } | Select-Object -First 1).value
      Add-Candidate $a.title.TrimEnd(".") $doi $a.fulljournalname ($a.pubdate -split " ")[0] "PubMed"
    }
  }
} catch { $errors += "PubMed: $($_.Exception.Message)" }

# --- Compare ---------------------------------------------------------------

$missing = @(); $nowPublished = @()
foreach ($c in $found.Values) {
  $norm = (Get-Words $c.Title) -join " "
  if ($ignore -contains $c.Doi -or $ignore -contains $c.Title.ToLowerInvariant() -or $ignore -contains $norm) { continue }
  if ((Get-Match $c.Title $published) -ge 0.9) { continue }
  if ($submitted.Count -and (Get-Match $c.Title $submitted) -ge 0.9) { $nowPublished += $c } else { $missing += $c }
}

function Format-Item($c) {
  $link = if ($c.Doi) { " https://doi.org/$($c.Doi)" } else { "" }
  "- **$($c.Title)**. *$($c.Venue)*, $($c.Year).$link  `n  Found in: $($c.Sources -join ', ')"
}

$lines = @()
if ($nowPublished.Count) {
  $lines += "### Listed as submitted, now published"
  $lines += "Move these from *Papers submitted or under revision* to *Publications*."
  $lines += ""
  $lines += $nowPublished | Sort-Object { $_.Year } -Descending | ForEach-Object { Format-Item $_ }
  $lines += ""
}
if ($missing.Count) {
  $lines += "### Not in the CV"
  $lines += "PubMed matches on name only, so a namesake can appear here. To stop an item being reported, add its DOI to ``scripts/publication-ignore.txt``."
  $lines += ""
  $lines += $missing | Sort-Object { $_.Year } -Descending | ForEach-Object { Format-Item $_ }
  $lines += ""
}
if ($errors.Count) {
  $lines += "### Sources that could not be checked"
  $lines += $errors | ForEach-Object { "- $_" }
}

Write-Host ("Checked {0} works ({1} published and {2} submitted CV entries): {3} missing, {4} now published, {5} source errors." -f `
  $found.Count, $published.Count, $submitted.Count, $missing.Count, $nowPublished.Count, $errors.Count)

if (Test-Path $OutFile) { Remove-Item $OutFile }
if ($missing.Count -or $nowPublished.Count) {
  ($lines -join "`n") | Out-File $OutFile -Encoding utf8
  Write-Host "Report written to $OutFile"
}
# Every source failing is worth failing the run for, so it shows up in Actions.
if ($errors.Count -eq 4) { exit 1 }
